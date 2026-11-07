import AppKit
import SwiftUI

enum Palette {
    static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
    static let background = rgb(0x121212)
    static let numberInk = rgb(0x08081F)
    static let button = rgb(0x808080)
    static let gold = rgb(0xFFD700)

    static func tileColor(_ n: Int) -> NSColor {
        switch n {
        case 1...4: return rgb(0xFF6464)
        case 5, 9, 13: return rgb(0xFFF55A)
        case 6, 7, 8: return rgb(0x75FF60)
        case 10, 14: return rgb(0x75FFDC)
        case 11, 12: return rgb(0x8FB1FA)
        default: return rgb(0xC78AF5)
        }
    }
}

/// Receives raw mouse events and applies hover-to-move synchronously in the handler.
final class BoardView: NSView {
    var controller: GameController! {
        didSet {
            needsDisplay = true
            controller?.cursorCellIndex = { [weak self] in self?.cursorCell?.index }
            controller?.onBackwardNavigation = { [weak self] in self?.cursorActive = false }
            controller?.onHintsChanged = { [weak self] in self?.needsDisplay = true }
            controller?.onBoardReplaced = { [weak self] in self?.boardDidReset() }
        }
    }

    private var draggedTile: UInt8?
    private var dragPoint: CGPoint?
    private var cursorActive = true
    private var lastCell: Cell?
    private var lastPoint: CGPoint?
    private var tracking: NSTrackingArea?
    private var attrCacheSize: CGFloat = 0
    private var cachedAttrs: [NSAttributedString.Key: Any] = [:]

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isOpaque: Bool { false }

    override init(frame: NSRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = Palette.background.cgColor
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) * 0.036
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        syncLastCellToCursor()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero,
                               options: [.mouseMoved, .mouseEnteredAndExited, .inVisibleRect, .activeInKeyWindow],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    private var cellSize: Double { Double(min(bounds.width, bounds.height)) / Double(PuzzleBoard.width) }

    // MARK: Events -> one path

    override func mouseMoved(with event: NSEvent) { handle(event) }
    override func mouseDown(with event: NSEvent) {
        guard controller.planning else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let cell = GridTraversal.cell(at: point, cellSize: cellSize) else { return }
        let ghost = controller.planTargets.filter { $0.value == cell.index }.keys.sorted().last
        let tile = ghost ?? controller.board.cells[cell.index]
        if tile != 0 { draggedTile = tile; dragPoint = point; needsDisplay = true }
    }

    override func mouseDragged(with event: NSEvent) {
        if controller.planning {
            dragPoint = convert(event.locationInWindow, from: nil)
            needsDisplay = true
        } else { handle(event) }
    }

    override func mouseUp(with event: NSEvent) {
        if controller.planning, let tile = draggedTile,
           let cell = GridTraversal.cell(at: convert(event.locationInWindow, from: nil), cellSize: cellSize) {
            controller.placeTarget(tile: tile, at: cell.index)
        }
        draggedTile = nil
        dragPoint = nil
        needsDisplay = true
    }
    override func rightMouseDragged(with event: NSEvent) { handle(event) }
    override func otherMouseDragged(with event: NSEvent) { handle(event) }
    override func mouseEntered(with event: NSEvent) { handle(event) }

    override func mouseExited(with event: NSEvent) {
        // Process the path up to the exit point so a fast exit doesn't lose cells.
        process(to: convert(event.locationInWindow, from: nil))
        lastCell = nil
        lastPoint = nil
    }

    private func handle(_ event: NSEvent) {
        process(to: convert(event.locationInWindow, from: nil))
    }

    private func process(to p: CGPoint) {
        if controller.planning || controller.planBusy { return }
        let cs = cellSize
        let path = GridTraversal.cells(from: lastPoint, to: p, cellSize: cs)
        lastPoint = p
        if GridTraversal.cell(at: p, cellSize: cs) == nil {
            // Cursor is outside the board: only the walked prefix counts, then forget position.
            apply(path)
            lastCell = nil
            lastPoint = nil
            return
        }
        apply(path)
    }

    private func apply(_ path: [Cell]) {
        for c in path where c != lastCell {
            lastCell = c
            if !cursorActive {
                if c.index == controller.board.emptyIndex { cursorActive = true }
                continue
            }
            let oldEmpty = controller.board.emptyIndex
            if controller.tryMove(at: c.index) {
                invalidate(Cell(index: oldEmpty))
                invalidate(c)
                if controller.phase == .solved { return }
            }
        }
    }

    private func invalidate(_ c: Cell) {
        let cs = CGFloat(cellSize)
        setNeedsDisplay(NSRect(x: CGFloat(c.col) * cs, y: CGFloat(c.row) * cs, width: cs, height: cs).insetBy(dx: -1, dy: -1))
    }

    private var cursorCell: Cell? {
        guard let window, !isHiddenOrHasHiddenAncestor else { return nil }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return GridTraversal.cell(at: point, cellSize: cellSize)
    }

    /// Call after a reshuffle: nothing moves until the cursor enters a different cell.
    func syncLastCellToCursor() {
        guard let w = window else { lastCell = nil; lastPoint = nil; return }
        let p = convert(w.mouseLocationOutsideOfEventStream, from: nil)
        lastCell = GridTraversal.cell(at: p, cellSize: cellSize)
        lastPoint = lastCell == nil ? nil : p
    }

    func boardDidReset() {
        draggedTile = nil
        dragPoint = nil
        needsDisplay = true
        cursorActive = true
        syncLastCellToCursor()
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let controller else { return }
        let cs = CGFloat(cellSize)
        Palette.background.setFill()
        dirtyRect.fill()
        let size = cs * 0.4
        if attrCacheSize != size {
            attrCacheSize = size
            let style = NSMutableParagraphStyle(); style.alignment = .center
            cachedAttrs = [.font: NSFont.systemFont(ofSize: size, weight: .bold),
                           .foregroundColor: Palette.numberInk, .paragraphStyle: style]
        }
        let cells = controller.board.cells
        func rect(_ index: Int) -> NSRect {
            let cell = Cell(index: index)
            let r = NSRect(x: CGFloat(cell.col) * cs, y: CGFloat(cell.row) * cs, width: cs, height: cs)
            return controller.planning ? r.insetBy(dx: cs * 0.025, dy: cs * 0.025) : r
        }
        func tile(_ number: UInt8, in r: NSRect, ghost: Bool = false) {
            Palette.tileColor(Int(number)).withAlphaComponent(ghost ? 0.75 : 1).setFill()
            r.fill()
            if ghost {
                NSColor.white.withAlphaComponent(0.9).setStroke()
                let border = NSBezierPath(rect: r.insetBy(dx: 1, dy: 1))
                border.lineWidth = 2
                border.stroke()
            }
            let label = NSAttributedString(string: "\(number)", attributes: cachedAttrs)
            let gb = CTLineGetImageBounds(CTLineCreateWithAttributedString(label), nil)
            let asc = (cachedAttrs[.font] as! NSFont).ascender
            label.draw(at: NSPoint(x: r.midX - gb.midX, y: r.midY + gb.midY - asc))
        }
        for i in 0..<PuzzleBoard.count where cells[i] != 0 {
            let r = rect(i)
            if controller.planning && (controller.planTargets[cells[i]] != nil || draggedTile == cells[i]) {
                Palette.button.withAlphaComponent(0.45).setFill()
                r.fill()
            } else { tile(cells[i], in: r) }
        }
        if controller.planning {
            for number in controller.planTargets.keys.sorted() where number != draggedTile {
                let r = rect(controller.planTargets[number]!).offsetBy(dx: cs * 0.045, dy: cs * 0.045)
                tile(number, in: r, ghost: true)
            }
            if let number = draggedTile, let point = dragPoint {
                tile(number, in: NSRect(x: point.x - cs * 0.475, y: point.y - cs * 0.475,
                                       width: cs * 0.95, height: cs * 0.95), ghost: true)
            }
        } else { drawGhost(cellSize: cs) }
    }

    private func drawGhost(cellSize cs: CGFloat) {
        let indices: [Int]
        if let plan = controller.planPath {
            indices = plan.isEmpty ? [] : [controller.board.emptyIndex] + Array(plan.prefix(5))
        } else if controller.ghostEnabled { indices = controller.ghostPath }
        else { indices = [] }
        guard let first = indices.first else { return }
        func center(_ index: Int) -> NSPoint {
            let cell = Cell(index: index)
            return NSPoint(x: (CGFloat(cell.col) + 0.5) * cs,
                           y: (CGFloat(cell.row) + 0.5) * cs)
        }
        let path = NSBezierPath()
        path.move(to: center(first))
        let points = indices.map(center)
        for step in 1..<points.count {
            let corner = points[step]
            if step == points.count - 1 {
                path.line(to: corner)
                continue
            }
            let previous = points[step - 1], next = points[step + 1]
            let radius = cs * 0.12
            func near(_ point: NSPoint) -> NSPoint {
                let dx = point.x - corner.x, dy = point.y - corner.y
                let scale = radius / hypot(dx, dy)
                return NSPoint(x: corner.x + dx * scale, y: corner.y + dy * scale)
            }
            let entry = near(previous), exit = near(next)
            path.line(to: entry)
            path.curve(to: exit,
                       controlPoint1: NSPoint(x: entry.x + (corner.x - entry.x) * 2 / 3,
                                              y: entry.y + (corner.y - entry.y) * 2 / 3),
                       controlPoint2: NSPoint(x: exit.x + (corner.x - exit.x) * 2 / 3,
                                              y: exit.y + (corner.y - exit.y) * 2 / 3))
        }
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor.black.withAlphaComponent(0.55).setStroke()
        path.lineWidth = cs * 0.085
        path.stroke()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        path.lineWidth = cs * 0.035
        path.stroke()

    }
}

struct BoardRepresentable: NSViewRepresentable {
    let controller: GameController
    func makeNSView(context: Context) -> BoardView {
        let v = BoardView(frame: .zero)
        v.controller = controller
        BoardRegistry.shared.view = v
        return v
    }
    func updateNSView(_ nsView: BoardView, context: Context) {}
}

/// Lets the app delegate (R key) tell the board to resync after restart.
final class BoardRegistry {
    static let shared = BoardRegistry()
    weak var view: BoardView?
}
