import Foundation

final class MoveNode {
    let board: PuzzleBoard
    /// Tile number moved to reach this node (0 for the root).
    let tile: UInt8
    unowned(unsafe) let parent: MoveNode?
    private(set) var children: [MoveNode] = []
    /// Index into `children` of the most recently visited child.
    fileprivate(set) var preferred = 0

    init(board: PuzzleBoard, tile: UInt8, parent: MoveNode?) {
        self.board = board; self.tile = tile; self.parent = parent
    }
    fileprivate func add(_ n: MoveNode) { children.append(n); preferred = children.count - 1 }
}

/// Full history of positions reached from a scramble. Pure; no UI.
final class MoveTree {
    let root: MoveNode
    private(set) var current: MoveNode
    private var all: [MoveNode] = []   // keeps nodes alive (parent refs are unowned)

    init(root board: PuzzleBoard) {
        root = MoveNode(board: board, tile: 0, parent: nil)
        current = root
        all.append(root)
    }

    /// Slides the tile at `index` from the current node, reusing an existing child for the same tile.
    /// Returns true if a tile movement happened (a new child or a reused one).
    @discardableResult
    func play(cellIndex index: Int) -> Bool {
        let b = current.board
        guard b.isAdjacentToEmpty(index) else { return false }
        let tile = b.cells[index]
        if let i = current.children.firstIndex(where: { $0.tile == tile }) {
            current.preferred = i
            current = current.children[i]
        } else {
            var nb = b
            nb.move(at: index)
            let n = MoveNode(board: nb, tile: tile, parent: current)
            current.add(n)
            all.append(n)
            current = n
        }
        return true
    }

    @discardableResult
    func back() -> Bool {
        guard let p = current.parent else { return false }
        if let i = p.children.firstIndex(where: { $0 === current }) { p.preferred = i }
        current = p
        return true
    }

    @discardableResult
    func forward() -> Bool {
        guard !current.children.isEmpty else { return false }
        current = current.children[min(current.preferred, current.children.count - 1)]
        return true
    }

    /// delta = -1 previous sibling, +1 next sibling. No wrap.
    @discardableResult
    func sibling(_ delta: Int) -> Bool {
        guard let p = current.parent, let i = p.children.firstIndex(where: { $0 === current }) else { return false }
        let j = i + delta
        guard j >= 0, j < p.children.count else { return false }
        p.preferred = j
        current = p.children[j]
        return true
    }

    var nodeCount: Int { all.count }
}
