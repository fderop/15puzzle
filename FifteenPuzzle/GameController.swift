import Foundation
import QuartzCore

enum GamePhase { case idle, running, solved, reviewing }
enum Navigation { case back, forward, prevSibling, nextSibling, start, end }

struct OptimalMoveCounts {
    let original: Int
    let remaining: Int
    let deficit: Int
}

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

    @Published private(set) var displayedOptimalCounts: OptimalMoveCounts?
    @Published private(set) var remainingOptimalMoves: Int?
    @Published var ghostEnabled = false {
        didSet {
            if ghostEnabled { usedAssistance = true }
            onHintsChanged?()
        }
    }
    private var usedAssistance = false
    private(set) var ghostPath: [Int] = []
    var onHintsChanged: (() -> Void)?
    private var currentSolveTask: Task<Void, Never>?
    private var optimalPaths: [[UInt8]: [Int]] = [:]

    @Published private(set) var planning = false
    @Published private(set) var planStatus = ""
    @Published private(set) var planBusy = false
    private(set) var planTargets: [UInt8: Int] = [:]
    private(set) var planPath: [Int]?
    private var planTask: Task<Void, Never>?
    private var planGeneration = UUID()

    func beginPlan() {
        usedAssistance = true
        ghostEnabled = false
        cancelPlan()
        planning = true
        planStatus = "Drag tiles to their target positions."
        onBoardReplaced?()
    }

    func placeTarget(tile: UInt8, at index: Int) {
        if board.cells[index] == tile { planTargets.removeValue(forKey: tile) }
        else { planTargets[tile] = index }
        onHintsChanged?()
    }

    func cancelPlan() {
        planTask?.cancel()
        planGeneration = UUID()
        planning = false
        planBusy = false
        planTargets = [:]
        planPath = nil
        planStatus = ""
        onBoardReplaced?()
    }

    func solvePlan() {
        planning = false
        planBusy = true
        planPath = nil
        planStatus = "Finding a shortest path…"
        onBoardReplaced?()
        let position = board, goals = planTargets, generation = UUID()
        planGeneration = generation
        planTask?.cancel()
        planTask = Task.detached(priority: .userInitiated) { [weak self] in
            let path = ArrangementSolver.solve(position, goals: goals, shouldCancel: { Task.isCancelled })
            guard !Task.isCancelled else { return }
            DispatchQueue.main.async {
                guard let self, self.planGeneration == generation else { return }
                self.planBusy = false
                self.planPath = path
                self.planStatus = path.map { $0.isEmpty ? "Targets reached." : "Target path: \($0.count) moves" }
                    ?? "Impossible: these targets cannot share a legal board."
                self.onHintsChanged?()
            }
        }
    }

    /// Called after the displayed board is replaced wholesale (restart, navigation, review).
    var onBoardReplaced: (() -> Void)?

    var cursorCellIndex: (() -> Int?)?
    var onBackwardNavigation: (() -> Void)?

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
        updateHints()
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
        if planning || planBusy || phase == .reviewing { return false }
        if phase == .solved {
            if planPath?.isEmpty != false { return false }
            startTime = CACurrentMediaTime() - finalTime
            phase = .running
        }
        guard tree.play(cellIndex: index) else { return false }
        let now = CACurrentMediaTime()
        if phase == .idle { startTime = now; phase = .running }
        moves = tree.current.depth
        if tree.current.board.isSolved {
            finalTime = now - startTime
            phase = .solved
            if !usedAssistance {
                history.append(SolveRecord(date: Date(), seconds: finalTime, moves: moves,
                                          scramble: tree.root.board.cells, optimalMoves: solutionLength))
                if best == nil || finalTime < best!.time {
                    let pb = PersonalBest(time: finalTime, moves: moves)
                    best = pb
                    UserDefaults.standard.set(pb.time, forKey: Self.timeKey)
                    UserDefaults.standard.set(pb.moves, forKey: Self.movesKey)
                }
            }
        }
        if let path = planPath, !path.isEmpty {
            if path.first == index {
                planPath = Array(path.dropFirst())
                planStatus = planPath!.isEmpty ? "Targets reached." : "Target path: \(planPath!.count) moves"
            } else { solvePlan() }
        }
        updateHints()
        return true
    }

    /// Arrow-key navigation updates the move count to the current history depth.
    @discardableResult
    func navigate(_ n: Navigation) -> Bool {
        if planning || planBusy { return false }
        if planPath != nil || !planStatus.isEmpty { cancelPlan() }
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
        if changed {
            if phase != .reviewing { moves = tree.current.depth }
            updateHints()
            onBoardReplaced?()
            if n == .back { onBackwardNavigation?() }
        }
        return changed
    }

    func restart() {
        cancelPlan()
        usedAssistance = ghostEnabled
        tree = MoveTree(root: PuzzleBoard.shuffled(emptyIndex: cursorCellIndex?()))
        moves = 0
        finalTime = 0
        reviewPos = 0
        reviewBoards = []
        awaitingSolution = false
        phase = .idle
        optimalPaths = [:]
        startSolve()
        updateHints()
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
        cachePath(s, from: scramble)
        updateHints()
        history.setOptimal(scramble: scramble.cells, moves: s.count)
        if awaitingSolution { awaitingSolution = false; enterReview() }
    }

    private func cachePath(_ path: [Int], from start: PuzzleBoard) {
        var b = start
        for step in 0...path.count {
            optimalPaths[b.cells] = Array(path.dropFirst(step))
            if step < path.count { b.move(at: path[step]) }
        }
    }

    private func updateHints() {
        currentSolveTask?.cancel()
        let position = board
        if let path = optimalPaths[position.cells] {
            showHints(path)
            return
        }
        if position.isSolved {
            showHints([])
            return
        }
        remainingOptimalMoves = nil
        ghostPath = []
        onHintsChanged?()
        // The root solver already owns this position.
        if position == tree.root.board { return }
        // Walk back to a cached ancestor to obtain a legal upper bound.
        // After one move from a known optimum, only the shorter alternative needs a search.
        var node = tree.current
        var route: [Int] = []
        var upperBound: [Int]?
        while let parent = node.parent {
            route.append(parent.board.emptyIndex)
            if let cached = optimalPaths[parent.board.cells] {
                upperBound = route + cached
                break
            }
            node = parent
        }
        let knownRoute = upperBound
        currentSolveTask = Task.detached(priority: .utility) { [weak self] in
            let path = PuzzleSolver.solve(position, upperBound: knownRoute, shouldCancel: { Task.isCancelled })
            guard let path, !Task.isCancelled else { return }
            DispatchQueue.main.async {
                guard let self, self.board == position else { return }
                self.cachePath(path, from: position)
                self.showHints(path)
            }
        }
    }

    private func showHints(_ path: [Int]) {
        remainingOptimalMoves = path.count
        if let original = solutionLength {
            let count = phase == .reviewing ? reviewPos : moves
            displayedOptimalCounts = OptimalMoveCounts(original: original, remaining: path.count,
                                                       deficit: count + path.count - original)
        }
        ghostPath = path.isEmpty ? [] : [board.emptyIndex] + Array(path.prefix(5))
        onHintsChanged?()
    }

    func beginReview() {
        cancelPlan()
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
        updateHints()
        onBoardReplaced?()
    }
}
