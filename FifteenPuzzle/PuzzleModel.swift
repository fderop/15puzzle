import Foundation

/// A cell position on the 4x4 grid (row/col from the top-left).
struct Cell: Equatable, Hashable {
    var row: Int
    var col: Int
    var index: Int { row * PuzzleBoard.width + col }
    init(row: Int, col: Int) { self.row = row; self.col = col }
    init(index: Int) { self.init(row: index / PuzzleBoard.width, col: index % PuzzleBoard.width) }
}

/// Pure puzzle state. 16 entries, 0 = empty.
struct PuzzleBoard: Equatable {
    static let width = 4
    static let count = 16
    static let solvedCells: [UInt8] = (1...15).map { UInt8($0) } + [0]
    static let solved = PuzzleBoard(cells: solvedCells)

    private(set) var cells: [UInt8]
    private(set) var emptyIndex: Int

    init(cells: [UInt8]) {
        precondition(cells.count == PuzzleBoard.count)
        self.cells = cells
        self.emptyIndex = cells.firstIndex(of: 0)!
    }

    var isSolved: Bool { cells == PuzzleBoard.solvedCells }

    func isAdjacentToEmpty(_ index: Int) -> Bool {
        guard index >= 0, index < PuzzleBoard.count, index != emptyIndex else { return false }
        let a = Cell(index: index), b = Cell(index: emptyIndex)
        return abs(a.row - b.row) + abs(a.col - b.col) == 1
    }

    /// Slides the tile at `index` into the empty cell if legal. Returns true if moved.
    @discardableResult
    mutating func move(at index: Int) -> Bool {
        guard isAdjacentToEmpty(index) else { return false }
        cells[emptyIndex] = cells[index]
        cells[index] = 0
        emptyIndex = index
        return true
    }

    // MARK: Solvability (4-wide board)

    static func inversions(_ cells: [UInt8]) -> Int {
        let tiles = cells.filter { $0 != 0 }
        var n = 0
        for i in 0..<tiles.count { for j in (i + 1)..<tiles.count where tiles[i] > tiles[j] { n += 1 } }
        return n
    }

    /// Even-width rule: solvable iff inversions + (1-based row of empty from the bottom) is odd.
    static func isSolvable(_ cells: [UInt8]) -> Bool {
        guard cells.count == count, let e = cells.firstIndex(of: 0) else { return false }
        let rowFromBottom = width - e / width
        return (inversions(cells) + rowFromBottom) % 2 == 1
    }

    /// Fisher-Yates over all 16 cells, parity-fix by swapping two tiles, reshuffle if solved.
    static func shuffled<R: RandomNumberGenerator>(emptyIndex: Int? = nil, using rng: inout R) -> PuzzleBoard {
        while true {
            var c = solvedCells
            for i in stride(from: count - 1, to: 0, by: -1) {
                let j = Int.random(in: 0...i, using: &rng)
                c.swapAt(i, j)
            }
            if let emptyIndex { c.swapAt(c.firstIndex(of: 0)!, emptyIndex) }
            if !isSolvable(c) {
                let idx = c.indices.filter { c[$0] != 0 }
                c.swapAt(idx[0], idx[1])
            }
            let b = PuzzleBoard(cells: c)
            if !b.isSolved { return b }
        }
    }

    static func shuffled(emptyIndex: Int? = nil) -> PuzzleBoard {
        var rng = SystemRandomNumberGenerator()
        return shuffled(emptyIndex: emptyIndex, using: &rng)
    }
}

/// Maps points to grid cells and walks segments through the grid.
enum GridTraversal {
    /// Cell containing the point, top-left origin. Shared edges belong to the right/lower cell.
    /// Points outside [0, size) on either axis give nil.
    static func cell(at p: CGPoint, cellSize: Double, grid: Int = PuzzleBoard.width) -> Cell? {
        guard cellSize > 0, p.x.isFinite, p.y.isFinite else { return nil }
        let c = Int((Double(p.x) / cellSize).rounded(.down))
        let r = Int((Double(p.y) / cellSize).rounded(.down))
        guard c >= 0, c < grid, r >= 0, r < grid else { return nil }
        return Cell(row: r, col: c)
    }

    /// Ordered cells touched by the segment from `from` to `to` (consecutive duplicates removed).
    /// If `from` is nil or outside the board, traversal starts where the segment enters the board.
    static func cells(from: CGPoint?, to: CGPoint, cellSize: Double, grid: Int = PuzzleBoard.width) -> [Cell] {
        guard cellSize > 0 else { return [] }
        let from = from ?? to
        let size = cellSize * Double(grid)
        let x0 = Double(from.x), y0 = Double(from.y)
        let dx = Double(to.x) - x0, dy = Double(to.y) - y0

        // Clip parameter range [t0, t1] to the board square [0, size].
        var t0 = 0.0, t1 = 1.0
        func clip(_ p: Double, _ q: Double) -> Bool {   // p*t <= q
            if p == 0 { return q >= 0 }
            let r = q / p
            if p < 0 { if r > t1 { return false }; t0 = max(t0, r) }
            else { if r < t0 { return false }; t1 = min(t1, r) }
            return true
        }
        // x >= 0, x <= size, y >= 0, y <= size
        guard clip(-dx, x0), clip(dx, size - x0), clip(-dy, y0), clip(dy, size - y0), t0 <= t1 else { return [] }

        func point(_ t: Double) -> CGPoint { CGPoint(x: x0 + dx * t, y: y0 + dy * t) }

        var ts: [Double] = [t0, t1]
        if dx != 0 {
            for k in 0...grid {
                let t = (Double(k) * cellSize - x0) / dx
                if t > t0 && t < t1 { ts.append(t) }
            }
        }
        if dy != 0 {
            for k in 0...grid {
                let t = (Double(k) * cellSize - y0) / dy
                if t > t0 && t < t1 { ts.append(t) }
            }
        }
        ts.sort()

        var out: [Cell] = []
        func add(_ c: Cell?) { if let c, out.last != c { out.append(c) } }
        // Start point (only inside if it genuinely is; clipped entry points on the near edge still resolve).
        add(cell(at: point(t0), cellSize: cellSize, grid: grid))
        for i in 0..<(ts.count - 1) where ts[i + 1] > ts[i] {
            add(cell(at: point((ts[i] + ts[i + 1]) / 2), cellSize: cellSize, grid: grid))
        }
        add(cell(at: point(t1), cellSize: cellSize, grid: grid))
        return out
    }
}
