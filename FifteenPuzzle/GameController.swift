import Foundation
import QuartzCore

enum GamePhase { case idle, running, solved, reviewing }
enum Navigation { case back, forward, prevSibling, nextSibling, start, end }

struct PersonalBest: Equatable { var time: Double; var moves: Int }

enum AppTab { case play, history }

final class TabState: ObservableObject {
    @Published var tab: AppTab = ProcessInfo.processInfo.environment["FIFTEEN_START_TAB"] == "history" ? .history : .play
}

/// Game state shared by the board view (direct calls) and SwiftUI chrome (observes published values only).
final class GameController: ObservableObject {
    @Published private(set) var moves = 0
    @Published private(set) var phase: GamePhase = .idle
    @Published private(set) var best: PersonalBest?
    @Published private(set) var solutionLength: Int?
    @Published private(set) var awaitingSolution = false
    @Published private(set) var reviewPos = 0

    /// Called after the displayed board is replaced wholesale (restart, navigation, review).
    var onBoardReplaced: (() -> Void)?

    let tabs = TabState()
    let history = HistoryStore()

    private(set) var tree: MoveTree
    private var reviewBoards: [PuzzleBoard] = []
    private var solution: [Int]?
    private var solveTask: Task<Void, Never>?
    private var startTime: CFTimeInterval = 0
    private var finalTime: Double = 0

    private static let timeKey = "bestTime", movesKey = "bestMoves"

    var board: PuzzleBoard { phase == .reviewing ? reviewBoards[reviewPos] : tree.current.board }

    init() {
        tree = MoveTree(root: PuzzleBoard.shuffled())
        let d = UserDefaults.standard
        if d.object(forKey: Self.timeKey) != nil {
            best = PersonalBest(time: d.double(forKey: Self.timeKey), moves: d.integer(forKey: Self.movesKey))
        }
        startSolve()
        history.fillMissing()
    }

    func elapsed() -> Double {
        switch phase {
        case .idle: return 0
        case .running: return CACurrentMediaTime() - startTime
        case .solved, .reviewing: return finalTime
        }
    }

    /// Mouse path. Tries to slide the tile at `index`.
    func tryMove(at index: Int) -> Bool {
        if phase == .solved || phase == .reviewing { return false }
        guard tree.play(cellIndex: index) else { return false }
        let now = CACurrentMediaTime()
        if phase == .idle { startTime = now; phase = .running }
        moves += 1
        if tree.current.board.isSolved {
            finalTime = now - startTime
            phase = .solved
            history.append(SolveRecord(date: Date(), seconds: finalTime, moves: moves,
                                            scramble: tree.root.board.cells, optimalMoves: solutionLength))
            if best == nil || finalTime < best!.time {
                let pb = PersonalBest(time: finalTime, moves: moves)
                best = pb
                UserDefaults.standard.set(pb.time, forKey: Self.timeKey)
                UserDefaults.standard.set(pb.moves, forKey: Self.movesKey)
            }
        }
        return true
    }

    /// Arrow-key navigation. Never touches counters, timer or best.
    @discardableResult
    func navigate(_ n: Navigation) -> Bool {
        var changed = false
        if phase == .reviewing {
            let last = reviewBoards.count - 1
            var p = reviewPos
            switch n {
            case .back: p = max(0, p - 1)
            case .forward: p = min(last, p + 1)
            case .start, .prevSibling: p = 0
            case .end, .nextSibling: p = last
            }
            if p != reviewPos { reviewPos = p; changed = true }
        } else {
            switch n {
            case .back: changed = tree.back()
            case .forward: changed = tree.forward()
            case .prevSibling: changed = tree.sibling(-1)
            case .nextSibling: changed = tree.sibling(1)
            case .start, .end: break
            }
        }
        if changed { onBoardReplaced?() }
        return changed
    }

    func restart() {
        tree = MoveTree(root: PuzzleBoard.shuffled())
        moves = 0
        finalTime = 0
        reviewPos = 0
        reviewBoards = []
        awaitingSolution = false
        phase = .idle
        startSolve()
        onBoardReplaced?()
    }

    func resetBest() {
        best = nil
        UserDefaults.standard.removeObject(forKey: Self.timeKey)
        UserDefaults.standard.removeObject(forKey: Self.movesKey)
    }

    // MARK: Solver / review

    private func startSolve() {
        solveTask?.cancel()
        solution = nil
        solutionLength = nil
        let scramble = tree.root.board
        solveTask = Task.detached(priority: .utility) { [weak self] in
            let s = PuzzleSolver.solve(scramble, shouldCancel: { Task.isCancelled })
            guard let s, !Task.isCancelled else { return }
            DispatchQueue.main.async { self?.finishSolve(scramble, s) }
        }
    }

    private func finishSolve(_ scramble: PuzzleBoard, _ s: [Int]) {
        guard scramble == tree.root.board else { return }   // stale
        solution = s
        solutionLength = s.count
        history.setOptimal(scramble: scramble.cells, moves: s.count)
        if awaitingSolution { awaitingSolution = false; enterReview() }
    }

    func beginReview() {
        guard phase == .solved else { return }
        if solution != nil { enterReview() } else { awaitingSolution = true }
    }

    private func enterReview() {
        guard let sol = solution else { return }
        var b = tree.root.board
        var boards = [b]
        for i in sol { b.move(at: i); boards.append(b) }
        reviewBoards = boards
        reviewPos = 0
        phase = .reviewing
        onBoardReplaced?()
    }
}
