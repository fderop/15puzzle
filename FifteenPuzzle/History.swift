import Foundation

struct SolveRecord: Codable, Equatable {
    var date: Date
    var seconds: Double
    var moves: Int
    var scramble: [UInt8]? = nil      // start board; nil in records saved before this field existed
    var optimalMoves: Int? = nil      // nil until the solver has finished for this scramble
    var tps: Double { seconds > 0 ? Double(moves) / seconds : 0 }
}

/// Persisted solve history (JSON in Application Support). Appends are cheap; writes happen off the main thread.
final class HistoryStore: ObservableObject {
    @Published private(set) var records: [SolveRecord] = []
    private let url: URL
    private let queue = DispatchQueue(label: "history.write", qos: .utility)

    init(url: URL? = nil) {
        let override = ProcessInfo.processInfo.environment["FIFTEEN_HISTORY_PATH"].map { URL(fileURLWithPath: $0) }
        self.url = url ?? override ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FifteenPuzzle/history.json")
        if let data = try? Data(contentsOf: self.url) {
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            records = (try? dec.decode([SolveRecord].self, from: data)) ?? []
        }
    }

    func append(_ r: SolveRecord) {
        records.append(r)
        let snapshot = records, url = url
        save(snapshot)
    }

    /// Fills in the optimal length for every record with this scramble that lacks one.
    func setOptimal(scramble: [UInt8], moves n: Int) {
        var changed = false
        for i in records.indices where records[i].scramble == scramble && records[i].optimalMoves == nil {
            records[i].optimalMoves = n; changed = true
        }
        if changed { save(records) }
    }

    private var attempted = Set<[UInt8]>()

    /// Solves records still missing an optimal length, one at a time at low priority.
    func fillMissing() {
        guard let r = records.first(where: { $0.optimalMoves == nil && $0.scramble != nil && !attempted.contains($0.scramble!) }),
              let sc = r.scramble, sc.count == PuzzleBoard.count else { return }
        attempted.insert(sc)
        Task.detached(priority: .background) { [weak self] in
            let sol = PuzzleSolver.solve(PuzzleBoard(cells: sc))
            DispatchQueue.main.async {
                if let sol { self?.setOptimal(scramble: sc, moves: sol.count) }
                self?.fillMissing()
            }
        }
    }

    private func save(_ snapshot: [SolveRecord]) {
        let url = url
        queue.async {
            let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted]
            guard let data = try? enc.encode(snapshot) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}
