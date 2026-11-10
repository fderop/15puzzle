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
    static func solve(_ board: PuzzleBoard, upperBound: [Int]? = nil,
                      shouldCancel: @escaping () -> Bool = { false }) -> [Int]? {
        guard PuzzleBoard.isSolvable(board.cells) else { return nil }
        if board.isSolved { return [] }
        var s = Search(board, shouldCancel: shouldCancel)
        defer { s.release() }
        return s.run(upperBound: upperBound)
    }

    private struct Candidate {
        let index: Int
        let row: Int
        let col: Int
        let md: Int
        let h: Int
    }

    private struct Search {
        let tiles = UnsafeMutablePointer<UInt8>.allocate(capacity: 16)
        let mdT = UnsafeMutablePointer<Int8>.allocate(capacity: 16 * 16)
        let path = UnsafeMutablePointer<Int8>.allocate(capacity: 256)
        let tableKeys = UnsafeMutablePointer<UInt64>.allocate(capacity: 1 << 20)
        let tableDepths = UnsafeMutablePointer<UInt8>.allocate(capacity: 1 << 20)
        let wdv: UnsafeMutablePointer<UInt8>
        let wdn: UnsafeMutablePointer<Int32>
        let initialBlank: Int
        let initialRow: Int
        let initialCol: Int
        let initialMD: Int
        let initialKey: UInt64
        var threshold = 0
        var nodes = 0
        var cancelled = false
        let shouldCancel: () -> Bool

        init(_ board: PuzzleBoard, shouldCancel: @escaping () -> Bool) {
            self.shouldCancel = shouldCancel
            let wd = WalkingDistance.shared
            wdv = wd.value; wdn = wd.next
            var key: UInt64 = 0
            for i in 0..<16 {
                tiles[i] = board.cells[i]
                key |= UInt64(board.cells[i]) << (i * 4)
            }
            for t in 1...15 { for p in 0..<16 {
                let goal = t - 1
                mdT[t * 16 + p] = Int8(abs((p >> 2) - (goal >> 2)) + abs((p & 3) - (goal & 3)))
            } }
            for p in 0..<16 { mdT[p] = 0 }
            initialBlank = board.emptyIndex
            let ids = wd.ids(for: board.cells)
            initialRow = ids.row; initialCol = ids.col
            var distance = 0
            for index in 0..<16 { distance += Int(mdT[Int(board.cells[index]) * 16 + index]) }
            initialMD = distance
            initialKey = key
        }

        func release() {
            tiles.deallocate(); mdT.deallocate(); path.deallocate()
            tableKeys.deallocate(); tableDepths.deallocate()
        }

        mutating func run(upperBound: [Int]?) -> [Int]? {
            threshold = max(initialMD, Int(wdv[initialRow]) + Int(wdv[initialCol]))
            while true {
                if shouldCancel() { return nil }
                // A known legal route is optimal once all shorter bounds are exhausted.
                if let upperBound, threshold >= upperBound.count { return upperBound }
                tableKeys.initialize(repeating: 0, count: 1 << 20)
                let result = dfs(0, initialBlank, -1, initialRow, initialCol, initialMD, initialKey)
                if cancelled { return nil }
                if result == -1 { return (0..<threshold).map { Int(path[$0]) } }
                threshold = result
            }
        }

        mutating func dfs(_ depth: Int, _ blank: Int, _ previous: Int,
                          _ row: Int, _ col: Int, _ md: Int, _ key: UInt64) -> Int {
            nodes &+= 1
            if nodes & 0xFFF == 0, shouldCancel() { cancelled = true; return Int.max }
            if md == 0 { threshold = depth; return -1 }
            let slot = Int(((key ^ (key >> 32)) &* 0x9E3779B97F4A7C15) >> 44)
            if tableKeys[slot] == key, Int(tableDepths[slot]) <= depth { return Int.max }
            tableKeys[slot] = key; tableDepths[slot] = UInt8(depth)
            return withUnsafeTemporaryAllocation(of: Candidate.self, capacity: 4) { candidates in
                var count = 0
                var nextBound = Int.max
                for direction in 0..<4 {
                    let index: Int
                    switch direction {
                    case 0: if blank < 4 { continue }; index = blank - 4
                    case 1: if blank >= 12 { continue }; index = blank + 4
                    case 2: if blank & 3 == 0 { continue }; index = blank - 1
                    default: if blank & 3 == 3 { continue }; index = blank + 1
                    }
                    if index == previous { continue }
                    let tile = Int(tiles[index]), goal = tile - 1
                    let nextMD = md + Int(mdT[tile * 16 + blank]) - Int(mdT[tile * 16 + index])
                    let nextRow = direction < 2
                        ? Int(wdn[row * 8 + (direction == 1 ? 4 : 0) + (goal >> 2)]) : row
                    let nextCol = direction >= 2
                        ? Int(wdn[col * 8 + (direction == 3 ? 4 : 0) + (goal & 3)]) : col
                    let h = max(nextMD, Int(wdv[nextRow]) + Int(wdv[nextCol]))
                    let f = depth + 1 + h
                    if f > threshold { nextBound = min(nextBound, f); continue }
                    let candidate = Candidate(index: index, row: nextRow, col: nextCol, md: nextMD, h: h)
                    var insertion = count
                    while insertion > 0 && candidates[insertion - 1].h > h {
                        candidates[insertion] = candidates[insertion - 1]
                        insertion -= 1
                    }
                    candidates[insertion] = candidate
                    count += 1
                }
                for i in 0..<count {
                    let candidate = candidates[i], index = candidate.index
                    let tile = tiles[index]
                    tiles[blank] = tile; tiles[index] = 0
                    path[depth] = Int8(index)
                    let nextKey = key ^ (UInt64(tile) << (blank * 4)) ^ (UInt64(tile) << (index * 4))
                    let result = dfs(depth + 1, index, blank, candidate.row, candidate.col, candidate.md, nextKey)
                    if result == -1 { return -1 }
                    tiles[index] = tile; tiles[blank] = 0
                    if cancelled { return Int.max }
                    nextBound = min(nextBound, result)
                }
                return nextBound
            }
        }
    }
}

/// Shortest path to a partial arrangement. Other tiles can finish anywhere.
enum ArrangementSolver {
    static func solve(_ board: PuzzleBoard, goals: [UInt8: Int],
                      shouldCancel: @escaping () -> Bool) -> [Int]? {
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
        var search = Search(board, goals: goals, shouldCancel: shouldCancel)
        defer { search.release() }
        return search.run()
    }

    private struct Candidate {
        let index: Int
        let distance: Int
    }

    private struct Search {
        let cells = UnsafeMutablePointer<UInt8>.allocate(capacity: 16)
        let distances = UnsafeMutablePointer<Int8>.allocate(capacity: 16 * 16)
        let shifts = UnsafeMutablePointer<Int>.allocate(capacity: 16)
        let path = UnsafeMutablePointer<Int8>.allocate(capacity: 256)
        let initialBlank: Int
        let initialKey: UInt64
        let initialDistance: Int
        let shouldCancel: () -> Bool
        var visited: [UInt64: Int] = [:]
        var nodes = 0
        var cancelled = false
        var bound = 0

        init(_ board: PuzzleBoard, goals: [UInt8: Int], shouldCancel: @escaping () -> Bool) {
            self.shouldCancel = shouldCancel
            initialBlank = board.emptyIndex
            distances.initialize(repeating: 0, count: 16 * 16)
            shifts.initialize(repeating: 0, count: 16)
            for (slot, tile) in goals.keys.sorted().enumerated() {
                shifts[Int(tile)] = (slot + 1) * 4
                let target = goals[tile]!
                for index in 0..<16 {
                    distances[Int(tile) * 16 + index] = Int8(abs(index / 4 - target / 4) + abs(index % 4 - target % 4))
                }
            }
            var key = UInt64(board.emptyIndex), distance = 0
            for index in 0..<16 {
                let tile = goals[board.cells[index]] == nil ? 0 : board.cells[index]
                cells[index] = tile
                if tile != 0 { key |= UInt64(index) << shifts[Int(tile)] }
                distance += Int(distances[Int(tile) * 16 + index])
            }
            initialKey = key
            initialDistance = distance
        }

        func release() {
            cells.deallocate(); distances.deallocate(); shifts.deallocate(); path.deallocate()
        }

        mutating func run() -> [Int]? {
            bound = initialDistance
            while true {
                if shouldCancel() { return nil }
                visited.removeAll(keepingCapacity: true)
                let result = dfs(initialBlank, -1, 0, initialDistance, initialKey)
                if cancelled || result == Int.max { return nil }
                if result == -1 { return (0..<bound).map { Int(path[$0]) } }
                bound = result
            }
        }

        mutating func dfs(_ blank: Int, _ previous: Int, _ depth: Int, _ distance: Int, _ key: UInt64) -> Int {
            nodes &+= 1
            if nodes & 0xFFF == 0, shouldCancel() { cancelled = true; return Int.max }
            if distance == 0 { bound = depth; return -1 }
            // Unselected tiles are interchangeable. Only the blank and selected positions matter.
            if let seen = visited[key], seen <= depth { return Int.max }
            visited[key] = depth
            return withUnsafeTemporaryAllocation(of: Candidate.self, capacity: 4) { candidates in
                var count = 0, nextBound = Int.max
                for direction in 0..<4 {
                    let index: Int
                    switch direction {
                    case 0: if blank < 4 { continue }; index = blank - 4
                    case 1: if blank >= 12 { continue }; index = blank + 4
                    case 2: if blank & 3 == 0 { continue }; index = blank - 1
                    default: if blank & 3 == 3 { continue }; index = blank + 1
                    }
                    if index == previous { continue }
                    let tile = Int(cells[index])
                    let h = distance + Int(distances[tile * 16 + blank]) - Int(distances[tile * 16 + index])
                    let f = depth + 1 + h
                    if f > bound { nextBound = min(nextBound, f); continue }
                    let candidate = Candidate(index: index, distance: h)
                    var insertion = count
                    while insertion > 0 && candidates[insertion - 1].distance > h {
                        candidates[insertion] = candidates[insertion - 1]
                        insertion -= 1
                    }
                    candidates[insertion] = candidate
                    count += 1
                }
                for i in 0..<count {
                    let candidate = candidates[i], index = candidate.index
                    let tile = cells[index]
                    var nextKey = key ^ UInt64(blank ^ index)
                    if tile != 0 { nextKey ^= UInt64(blank ^ index) << shifts[Int(tile)] }
                    cells[blank] = tile; cells[index] = 0
                    path[depth] = Int8(index)
                    let result = dfs(index, blank, depth + 1, candidate.distance, nextKey)
                    if result == -1 { return -1 }
                    cells[index] = tile; cells[blank] = 0
                    if cancelled { return Int.max }
                    nextBound = min(nextBound, result)
                }
                return nextBound
            }
        }
    }
}
