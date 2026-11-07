import Foundation

/// Walking Distance tables (Takahashi). One table serves rows and (transposed) columns.
/// State = 4x4 counts [row][goalRow] of non-blank tiles plus blank row.
final class WalkingDistance {
    static let shared = WalkingDistance()

    private(set) var stateCount = 0
    let value: UnsafeMutablePointer<UInt8>      // WD per state id
    let next: UnsafeMutablePointer<Int32>       // id*8 + dir*4 + goalLine -> id or -1
    private var keyToId: [UInt64: Int32] = [:]

    private static func encode(_ c: [UInt8], _ blank: Int) -> UInt64 {
        var k = UInt64(blank) << 48
        for i in 0..<16 { k |= UInt64(c[i]) << UInt64(i * 3) }
        return k
    }

    private init() {
        var keys: [UInt64] = []
        var depths: [UInt8] = []
        var nexts: [Int32] = []

        var goal = [UInt8](repeating: 0, count: 16)
        for r in 0..<4 { goal[r * 4 + r] = 4 }
        goal[15] = 3
        let k0 = Self.encode(goal, 3)
        keyToId[k0] = 0; keys.append(k0); depths.append(0)

        var head = 0
        while head < keys.count {
            let key = keys[head]
            var c = [UInt8](repeating: 0, count: 16)
            for i in 0..<16 { c[i] = UInt8((key >> UInt64(i * 3)) & 7) }
            let b = Int((key >> 48) & 3)
            nexts.append(contentsOf: [Int32](repeating: -1, count: 8))
            for dir in 0..<2 {
                let nb = b + (dir == 0 ? -1 : 1)
                guard nb >= 0, nb < 4 else { continue }
                for g in 0..<4 where c[nb * 4 + g] > 0 {
                    var d = c
                    d[nb * 4 + g] -= 1
                    d[b * 4 + g] += 1
                    let nk = Self.encode(d, nb)
                    let id: Int32
                    if let e = keyToId[nk] { id = e } else {
                        id = Int32(keys.count)
                        keyToId[nk] = id; keys.append(nk); depths.append(depths[head] + 1)
                    }
                    nexts[head * 8 + dir * 4 + g] = id
                }
            }
            head += 1
        }
        stateCount = keys.count
        value = .allocate(capacity: stateCount)
        next = .allocate(capacity: stateCount * 8)
        for i in 0..<stateCount { value[i] = depths[i] }
        for i in 0..<(stateCount * 8) { next[i] = nexts[i] }
    }

    /// Table ids for a board: (rows, columns).
    func ids(for cells: [UInt8]) -> (row: Int, col: Int) {
        var rc = [UInt8](repeating: 0, count: 16), cc = [UInt8](repeating: 0, count: 16)
        var br = 3, bc = 3
        for i in 0..<16 {
            let t = Int(cells[i])
            if t == 0 { br = i >> 2; bc = i & 3; continue }
            rc[(i >> 2) * 4 + (t - 1) >> 2] += 1
            cc[(i & 3) * 4 + (t - 1) & 3] += 1
        }
        return (Int(keyToId[Self.encode(rc, br)]!), Int(keyToId[Self.encode(cc, bc)]!))
    }

    func distance(for cells: [UInt8]) -> Int {
        let (r, c) = ids(for: cells)
        return Int(value[r]) + Int(value[c])
    }
}

enum PuzzleSolver {
    /// Optimal solution as a list of cell indices; each step slides the tile at that index into the blank
    /// (valid input for `PuzzleBoard.move(at:)`). Nil if unsolvable or cancelled.
    static func solve(_ board: PuzzleBoard, shouldCancel: @escaping () -> Bool = { false }) -> [Int]? {
        guard PuzzleBoard.isSolvable(board.cells) else { return nil }
        if board.isSolved { return [] }
        let s = Search(board, shouldCancel: shouldCancel)
        return s.run()
    }

    private final class Search {
        let wd = WalkingDistance.shared
        let tiles = UnsafeMutablePointer<UInt8>.allocate(capacity: 16)
        let mdT = UnsafeMutablePointer<Int8>.allocate(capacity: 16 * 16)
        let path = UnsafeMutablePointer<Int8>.allocate(capacity: 256)
        let wdv: UnsafeMutablePointer<UInt8>
        let wdn: UnsafeMutablePointer<Int32>
        var blank = 0, rowId = 0, colId = 0, md = 0
        var threshold = 0
        var nodes = 0
        var cancelled = false
        let shouldCancel: () -> Bool

        init(_ board: PuzzleBoard, shouldCancel: @escaping () -> Bool) {
            self.shouldCancel = shouldCancel
            wdv = wd.value; wdn = wd.next
            for i in 0..<16 { tiles[i] = board.cells[i] }
            for t in 1...15 { for p in 0..<16 {
                let g = t - 1
                mdT[t * 16 + p] = Int8(abs((p >> 2) - (g >> 2)) + abs((p & 3) - (g & 3)))
            } }
            for p in 0..<16 { mdT[p] = 0 }
            blank = board.emptyIndex
            let ids = wd.ids(for: board.cells)
            rowId = ids.row; colId = ids.col
            for i in 0..<16 where tiles[i] != 0 { md += Int(mdT[Int(tiles[i]) * 16 + i]) }
        }
        deinit { tiles.deallocate(); mdT.deallocate(); path.deallocate() }

        func run() -> [Int]? {
            threshold = max(md, Int(wdv[rowId]) + Int(wdv[colId]))
            while true {
                let r = dfs(0, -1)
                if cancelled { return nil }
                if r == -1 { break }
                threshold = r
            }
            // path holds blank destinations; the tile index moved is that destination.
            var out: [Int] = []
            for i in 0..<threshold { out.append(Int(path[i])) }
            return out
        }

        // Returns -1 if solved, else minimal f above threshold.
        func dfs(_ g: Int, _ prev: Int) -> Int {
            nodes &+= 1
            if nodes & 0xFFFF == 0, shouldCancel() { cancelled = true; return Int.max }
            let h = max(md, Int(wdv[rowId]) + Int(wdv[colId]))
            let f = g + h
            if f > threshold { return f }
            if md == 0 { threshold = g; return -1 }

            let b = blank
            let row = b >> 2, col = b & 3
            var best = Int.max
            for dir in 0..<4 {
                let n: Int
                switch dir {
                case 0: if row == 0 { continue }; n = b - 4
                case 1: if row == 3 { continue }; n = b + 4
                case 2: if col == 0 { continue }; n = b - 1
                default: if col == 3 { continue }; n = b + 1
                }
                if n == prev { continue }
                let t = Int(tiles[n])
                let oldRow = rowId, oldCol = colId, oldMd = md
                tiles[b] = UInt8(t); tiles[n] = 0
                md += Int(mdT[t * 16 + b]) - Int(mdT[t * 16 + n])
                let goal = t - 1
                if dir < 2 {
                    rowId = Int(wdn[rowId * 8 + (dir == 1 ? 4 : 0) + (goal >> 2)])
                } else {
                    colId = Int(wdn[colId * 8 + (dir == 3 ? 4 : 0) + (goal & 3)])
                }
                blank = n
                path[g] = Int8(n)
                let r = dfs(g + 1, b)
                if r == -1 { return -1 }
                blank = b; tiles[n] = UInt8(t); tiles[b] = 0
                rowId = oldRow; colId = oldCol; md = oldMd
                if r < best { best = r }
                if cancelled { return Int.max }
            }
            return best
        }
    }
}

/// Shortest path to a partial arrangement. Other tiles can finish anywhere.
enum ArrangementSolver {
    static func solve(_ board: PuzzleBoard, goals: [UInt8: Int],
                      shouldCancel: () -> Bool) -> [Int]? {
        if Set(goals.values).count != goals.count { return nil }
        // With at most one unspecified tile, the goals determine a complete board.
        if goals.count >= 14 {
            var cells = [UInt8](repeating: 0, count: 16)
            for (tile, index) in goals { cells[index] = tile }
            let free = cells.indices.filter { cells[$0] == 0 }
            let missing = (UInt8(1)...UInt8(15)).filter { goals[$0] == nil }
            let reachable = free.contains { blank in
                var candidate = cells
                let slots = free.filter { $0 != blank }
                for (index, tile) in zip(slots, missing) { candidate[index] = tile }
                return PuzzleBoard.isSolvable(candidate)
            }
            if !reachable { return nil }
        }
        var targets = [Int](repeating: -1, count: 16)
        for (tile, index) in goals { targets[Int(tile)] = index }
        var cells = board.cells
        var path: [Int] = []
        var visited: [UInt64: Int] = [:]
        var cancelled = false
        func heuristic() -> Int {
            var total = 0
            for index in 0..<16 {
                let target = targets[Int(cells[index])]
                if target >= 0 { total += abs(index / 4 - target / 4) + abs(index % 4 - target % 4) }
            }
            return total
        }
        func search(_ blank: Int, _ previous: Int, _ depth: Int, _ bound: Int) -> Int {
            if shouldCancel() { cancelled = true; return Int.max }
            let h = heuristic()
            if depth + h > bound { return depth + h }
            if h == 0 { return -1 }
            var key: UInt64 = 0
            for index in 0..<16 { key |= UInt64(cells[index]) << (index * 4) }
            if let seen = visited[key], seen <= depth { return Int.max }
            visited[key] = depth
            var nextBound = Int.max
            let neighbors = [blank - 4, blank + 4, blank - 1, blank + 1].filter {
                $0 >= 0 && $0 < 16 && $0 != previous && abs($0 / 4 - blank / 4) + abs($0 % 4 - blank % 4) == 1
            }.sorted { a, b in
                func change(_ index: Int) -> Int {
                    let target = targets[Int(cells[index])]
                    if target < 0 { return 0 }
                    return abs(blank / 4 - target / 4) + abs(blank % 4 - target % 4)
                        - abs(index / 4 - target / 4) - abs(index % 4 - target % 4)
                }
                return change(a) < change(b)
            }
            for index in neighbors {
                cells.swapAt(blank, index)
                path.append(index)
                let result = search(index, blank, depth + 1, bound)
                if result == -1 { return -1 }
                path.removeLast()
                cells.swapAt(blank, index)
                if cancelled { return Int.max }
                nextBound = min(nextBound, result)
            }
            return nextBound
        }
        var bound = heuristic()
        while true {
            visited.removeAll(keepingCapacity: true)
            let result = search(board.emptyIndex, -1, 0, bound)
            if cancelled || result == Int.max { return nil }
            if result == -1 { return path }
            bound = result
        }
    }
}
