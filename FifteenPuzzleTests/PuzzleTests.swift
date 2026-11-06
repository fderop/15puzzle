import XCTest
import Foundation

struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

final class ModelTests: XCTestCase {
    func testSolvedIsSolvableAndSolved() {
        XCTAssertTrue(PuzzleBoard.isSolvable(PuzzleBoard.solvedCells))
        XCTAssertTrue(PuzzleBoard.solved.isSolved)
    }

    func testKnownUnsolvable() {
        // classic: 14 and 15 swapped
        var c = PuzzleBoard.solvedCells
        c.swapAt(13, 14)
        XCTAssertFalse(PuzzleBoard.isSolvable(c))
    }

    func testKnownSolvable() {
        // one move from solved
        var c = PuzzleBoard.solvedCells
        c.swapAt(14, 15)
        XCTAssertTrue(PuzzleBoard.isSolvable(c))
        // 80-move instance
        let hard: [UInt8] = [15, 14, 13, 12, 10, 11, 8, 9, 2, 6, 7, 5, 1, 3, 4, 0]
        XCTAssertTrue(PuzzleBoard.isSolvable(hard))
    }

    func testShuffleAlwaysSolvableNotSolved() {
        var rng = SeededRNG(seed: 42)
        var emptyPositions = Set<Int>()
        for _ in 0..<3000 {
            let b = PuzzleBoard.shuffled(using: &rng)
            XCTAssertTrue(PuzzleBoard.isSolvable(b.cells))
            XCTAssertFalse(b.isSolved)
            XCTAssertEqual(Set(b.cells), Set(0...15))
            emptyPositions.insert(b.emptyIndex)
        }
        XCTAssertEqual(emptyPositions.count, 16)
    }

    func testMoveLegality() {
        var b = PuzzleBoard.solved   // empty at 15
        XCTAssertFalse(b.move(at: 0))
        XCTAssertFalse(b.move(at: 15))
        XCTAssertFalse(b.move(at: 10))   // diagonal
        XCTAssertFalse(b.move(at: 16))
        XCTAssertTrue(b.move(at: 14))
        XCTAssertEqual(b.emptyIndex, 14)
        XCTAssertEqual(b.cells[15], 15)
        XCTAssertFalse(b.isSolved)
        XCTAssertTrue(b.move(at: 15))
        XCTAssertTrue(b.isSolved)
        // row wrap: index 3 and 4 are not adjacent
        let w = PuzzleBoard(cells: [1,2,3,0,4,5,6,7,8,9,10,11,12,13,14,15])
        XCTAssertFalse(w.isAdjacentToEmpty(4))
        XCTAssertTrue(w.isAdjacentToEmpty(7))
        XCTAssertTrue(w.isAdjacentToEmpty(2))
    }
}

final class TraversalTests: XCTestCase {
    let cs = 100.0
    func c(_ r: Int, _ col: Int) -> Cell { Cell(row: r, col: col) }

    func testBoundaryOwnership() {
        XCTAssertEqual(GridTraversal.cell(at: CGPoint(x: 100, y: 100), cellSize: cs), c(1, 1))
        XCTAssertEqual(GridTraversal.cell(at: CGPoint(x: 0, y: 0), cellSize: cs), c(0, 0))
        XCTAssertNil(GridTraversal.cell(at: CGPoint(x: 400, y: 10), cellSize: cs))
        XCTAssertNil(GridTraversal.cell(at: CGPoint(x: -0.001, y: 10), cellSize: cs))
        XCTAssertEqual(GridTraversal.cell(at: CGPoint(x: 399.99, y: 399.99), cellSize: cs), c(3, 3))
    }

    func testStraightHorizontal() {
        let r = GridTraversal.cells(from: CGPoint(x: 10, y: 50), to: CGPoint(x: 390, y: 50), cellSize: cs)
        XCTAssertEqual(r, [c(0, 0), c(0, 1), c(0, 2), c(0, 3)])
    }

    func testStraightVerticalReverse() {
        let r = GridTraversal.cells(from: CGPoint(x: 50, y: 390), to: CGPoint(x: 50, y: 10), cellSize: cs)
        XCTAssertEqual(r, [c(3, 0), c(2, 0), c(1, 0), c(0, 0)])
    }

    func testDiagonalOrderedStaircase() {
        // shallow slope: crosses x-lines before y-lines
        let r = GridTraversal.cells(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 290, y: 150), cellSize: cs)
        XCTAssertEqual(r, [c(0, 0), c(0, 1), c(1, 1), c(1, 2)])
    }

    func testExactDiagonalThroughCorners() {
        let r = GridTraversal.cells(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 350, y: 350), cellSize: cs)
        XCTAssertEqual(r, [c(0, 0), c(1, 1), c(2, 2), c(3, 3)])
    }

    func testEntersFromOutside() {
        let r = GridTraversal.cells(from: CGPoint(x: -200, y: 150), to: CGPoint(x: 250, y: 150), cellSize: cs)
        XCTAssertEqual(r, [c(1, 0), c(1, 1), c(1, 2)])
        XCTAssertEqual(GridTraversal.cells(from: nil, to: CGPoint(x: 150, y: 50), cellSize: cs), [c(0, 1)])
    }

    func testMissesBoardAndEndsOnEdge() {
        XCTAssertEqual(GridTraversal.cells(from: CGPoint(x: -50, y: -50), to: CGPoint(x: -10, y: 500), cellSize: cs), [])
        // ends exactly on shared edge: belongs to right cell
        let r = GridTraversal.cells(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 100, y: 50), cellSize: cs)
        XCTAssertEqual(r, [c(0, 0), c(0, 1)])
    }

    func testLeavesBoard() {
        let r = GridTraversal.cells(from: CGPoint(x: 350, y: 50), to: CGPoint(x: 900, y: 50), cellSize: cs)
        XCTAssertEqual(r, [c(0, 3)])
    }
}

final class MoveTreeTests: XCTestCase {
    func board() -> PuzzleBoard { PuzzleBoard(cells: [1,2,3,4,5,6,7,8,9,10,11,12,13,14,0,15]) } // empty at 14

    func testUndoRedoRoundTrip() {
        let t = MoveTree(root: board())
        XCTAssertTrue(t.play(cellIndex: 15))
        XCTAssertTrue(t.current.board.isSolved)
        XCTAssertTrue(t.back())
        XCTAssertTrue(t.current === t.root)
        XCTAssertFalse(t.back())
        XCTAssertTrue(t.forward())
        XCTAssertTrue(t.current.board.isSolved)
        XCTAssertFalse(t.forward())
    }

    func testBranchingAfterUndo() {
        let t = MoveTree(root: board())
        t.play(cellIndex: 15)
        t.back()
        XCTAssertTrue(t.play(cellIndex: 13))      // different tile
        XCTAssertEqual(t.root.children.count, 2)
        XCTAssertEqual(t.nodeCount, 3)
    }

    func testSameMoveReusesChild() {
        let t = MoveTree(root: board())
        t.play(cellIndex: 15); let first = t.current
        t.back()
        t.play(cellIndex: 15)
        XCTAssertTrue(t.current === first)
        XCTAssertEqual(t.root.children.count, 1)
    }

    func testSiblingSwitching() {
        let t = MoveTree(root: board())
        t.play(cellIndex: 15); let a = t.current
        t.back(); t.play(cellIndex: 13); let b = t.current
        XCTAssertFalse(t.sibling(1))
        XCTAssertTrue(t.sibling(-1)); XCTAssertTrue(t.current === a)
        XCTAssertFalse(t.sibling(-1))
        XCTAssertTrue(t.sibling(1)); XCTAssertTrue(t.current === b)
        // preferred child follows most recent visit
        t.back(); XCTAssertTrue(t.forward()); XCTAssertTrue(t.current === b)
    }

    func testNavigationDoesNotAffectCountersOrTimer() {
        let g = GameController()
        // find a legal move and play it, then navigate
        let idx = (0..<16).first { g.board.isAdjacentToEmpty($0) }!
        XCTAssertTrue(g.tryMove(at: idx))
        let moves = g.moves, phase = g.phase, best = g.best
        g.navigate(.back); g.navigate(.forward); g.navigate(.prevSibling); g.navigate(.nextSibling)
        XCTAssertEqual(g.moves, moves)
        XCTAssertEqual(g.phase, phase)
        XCTAssertEqual(g.best, best)
    }

    func testIdleNavigationDoesNotStartTimer() {
        let g = GameController()
        g.navigate(.back); g.navigate(.forward)
        XCTAssertEqual(g.phase, .idle)
        XCTAssertEqual(g.moves, 0)
    }
}

final class SolverTests: XCTestCase {
    func apply(_ b: PuzzleBoard, _ sol: [Int]) -> PuzzleBoard? {
        var b = b
        for i in sol { if !b.move(at: i) { return nil } }
        return b
    }

    func testWalkingDistanceTable() {
        XCTAssertEqual(WalkingDistance.shared.stateCount, 24964)
        XCTAssertEqual(WalkingDistance.shared.distance(for: PuzzleBoard.solvedCells), 0)
    }

    func testHeuristicAdmissibleOnShortScrambles() {
        var rng = SeededRNG(seed: 7)
        for _ in 0..<300 {
            var b = PuzzleBoard.solved
            let n = Int.random(in: 1...14, using: &rng)
            var applied = 0
            while applied < n {
                let i = Int.random(in: 0..<16, using: &rng)
                if b.move(at: i) { applied += 1 }
            }
            let h = WalkingDistance.shared.distance(for: b.cells)
            XCTAssertLessThanOrEqual(h, n)
            let opt = PuzzleSolver.solve(b)!.count
            XCTAssertLessThanOrEqual(h, opt)
            XCTAssertLessThanOrEqual(opt, n)
            XCTAssertEqual((opt - n) % 2, 0)
        }
    }

    func testKnownOptimalLengths() {
        var c = PuzzleBoard.solvedCells
        c.swapAt(14, 15)
        XCTAssertEqual(PuzzleSolver.solve(PuzzleBoard(cells: c))?.count, 1)
        var b = PuzzleBoard.solved
        b.move(at: 14); b.move(at: 10)
        XCTAssertEqual(PuzzleSolver.solve(b)?.count, 2)
        var five = PuzzleBoard.solved
        for i in [14, 13, 9, 10, 11] { XCTAssertTrue(five.move(at: i)) }   // path with no backtracking
        XCTAssertEqual(PuzzleSolver.solve(five)?.count, 5)
        XCTAssertEqual(PuzzleSolver.solve(.solved)?.count, 0)
    }

    func testUnsolvableReturnsNil() {
        var c = PuzzleBoard.solvedCells
        c.swapAt(13, 14)
        XCTAssertNil(PuzzleSolver.solve(PuzzleBoard(cells: c)))
    }

    func testSolutionValidityOnRandomScrambles() {
        var rng = SeededRNG(seed: 2024)
        var times: [Double] = []
        for _ in 0..<20 {
            let b = PuzzleBoard.shuffled(using: &rng)
            let t0 = CFAbsoluteTimeGetCurrent()
            let sol = PuzzleSolver.solve(b)
            times.append(CFAbsoluteTimeGetCurrent() - t0)
            XCTAssertNotNil(sol)
            XCTAssertEqual(apply(b, sol ?? [])?.isSolved, true)
        }
        times.sort()
        print("SOLVER TIMES min=\(times.first!) median=\(times[times.count / 2]) max=\(times.last!)")
    }
}
