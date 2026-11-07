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
            controller?.onBoardReplaced = { [weak self] in self?.boardDidReset() }
        }
    }

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
    override func mouseDragged(with event: NSEvent) { handle(event) }
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
        for i in 0..<PuzzleBoard.count {
            let c = Cell(index: i)
            let r = NSRect(x: CGFloat(c.col) * cs, y: CGFloat(c.row) * cs, width: cs, height: cs)
            guard r.intersects(dirtyRect), cells[i] != 0 else { continue }
            Palette.tileColor(Int(cells[i])).setFill()
            r.fill()
            let s = NSAttributedString(string: "\(cells[i])", attributes: cachedAttrs)
            let gb = CTLineGetImageBounds(CTLineCreateWithAttributedString(s), nil)
            let asc = (cachedAttrs[.font] as! NSFont).ascender
            // Flipped view: baseline sits gb.midY below the cell center so the glyph box is centered.
            s.draw(at: NSPoint(x: r.midX - gb.midX, y: r.midY + gb.midY - asc))
        }
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
