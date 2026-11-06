import SwiftUI
import Charts

struct HistoryPoint {
    var x: Double
    var moves: Double
    var seconds: Double
    var tps: Double
    var optimal: Double?
    var deficit: Double?
    var tip: [String]
}

enum HistoryMode: String { case sequential, day }

struct HistoryView: View {
    @ObservedObject var history: HistoryStore
    let best: PersonalBest?
    let s: CGFloat
    @State private var hover: HoverInfo?
    @AppStorage("historyMode") private var modeRaw = HistoryMode.sequential.rawValue

    private var mode: HistoryMode { HistoryMode(rawValue: modeRaw) ?? .sequential }

    static func points(_ recs: [SolveRecord], mode: HistoryMode) -> [HistoryPoint] {
        switch mode {
        case .sequential:
            return recs.sorted { $0.date < $1.date }.map { r in
                var tip = [r.date.formatted(date: .abbreviated, time: .shortened),
                           String(format: "Time: %.3f s", r.seconds), "Moves: \(r.moves)"]
                if let o = r.optimalMoves {
                    tip.append(String(format: "optimal: %d moves (%.2f\u{00D7})", o, Double(r.moves) / Double(max(o, 1))))
                    tip.append("deficit: \(r.moves - o) moves")
                } else if r.scramble != nil {
                    tip.append("optimal: \u{2026}")
                }
                tip.append(String(format: "TPS: %.3f", r.tps))
                return HistoryPoint(x: r.date.timeIntervalSinceReferenceDate, moves: Double(r.moves), seconds: r.seconds, tps: r.tps,
                                    optimal: r.optimalMoves.map(Double.init),
                                    deficit: r.optimalMoves.map { Double(r.moves - $0) }, tip: tip)
            }
        case .day:
            return HistoryStore.dailyAverages(recs).map { d in
                var tip = [d.day.formatted(date: .abbreviated, time: .omitted),
                           "\(d.count) solve\(d.count == 1 ? "" : "s")",
                           String(format: "avg %.1f moves", d.moves),
                           String(format: "avg %.3f s", d.seconds),
                           String(format: "avg %.2f TPS", d.tps)]
                if let o = d.optimalMoves { tip.append(String(format: "avg optimal %.1f", o)) }
                if let f = d.deficit { tip.append(String(format: "avg deficit %.1f", f)) }
                return HistoryPoint(x: d.day.timeIntervalSinceReferenceDate, moves: d.moves, seconds: d.seconds,
                                    tps: d.tps, optimal: d.optimalMoves, deficit: d.deficit, tip: tip)
            }
        }
    }

    var body: some View {
        let pts = Self.points(history.records, mode: mode)
        VStack(spacing: 8 * s) {
            HStack(spacing: 8 * s) {
                bestLine
                Spacer(minLength: 0)
                Picker("", selection: $modeRaw) {
                    Text("Day").tag(HistoryMode.day.rawValue)
                    Text("Sequential").tag(HistoryMode.sequential.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .focusable(false)
                .font(.system(size: 12 * s))
                .frame(width: 170 * s)
            }
            if pts.isEmpty {
                Text("No solves yet")
                    .font(.system(size: 15 * s, weight: .regular))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let lo = pts.map(\.x).min()!, hi = pts.map(\.x).max()!
                let pad = hi - lo < 1 ? (mode == .day ? 43200 : 3600) : (hi - lo) * 0.03
                let domain = (lo - pad)...(hi + pad)
                VStack(spacing: 4 * s) {
                    HistoryChart(pts: pts, title: "Moves", color: Color(white: 0.9), domain: domain, s: s, showX: false, hover: $hover, value: \.moves)
                    HistoryChart(pts: pts, title: "Time (s)", color: Color(nsColor: Palette.gold), domain: domain, s: s, showX: false, hover: $hover, value: \.seconds)
                    HistoryChart(pts: pts, title: "TPS", color: Color(nsColor: Palette.rgb(0x75FFDC)), domain: domain, s: s, showX: true, hover: $hover, value: \.tps)
                }
                .coordinateSpace(name: "hist")
                .overlay { tooltip(pts) }
            }
        }
        .padding(.horizontal, 20 * s)
        .padding(.top, 16 * s)
        .padding(.bottom, 16 * s)
        .onChange(of: modeRaw) { hover = nil }
    }

    private var bestLine: some View {
        let text = best.map { String(format: "Best %.3fs \u{00B7} %d moves", $0.time, $0.moves) }
            ?? "Best \u{2014}"
        return Text(text)
            .font(.system(size: 15 * s, weight: .regular).monospacedDigit())
            .foregroundColor(.white)
    }
}

struct HoverInfo: Equatable { var index: Int; var point: CGPoint }

extension HistoryView {
    @ViewBuilder fileprivate func tooltip(_ pts: [HistoryPoint]) -> some View {
        if let h = hover, pts.indices.contains(h.index) {
            VStack(alignment: .leading, spacing: 2 * s) {
                ForEach(Array(pts[h.index].tip.enumerated()), id: \.offset) { _, l in Text(l) }
            }
            .font(.system(size: 12 * s, weight: .regular).monospacedDigit())
            .foregroundColor(.white)
            .padding(6 * s)
            .background(Color(nsColor: Palette.rgb(0x1E1E1E)))
            .clipShape(RoundedRectangle(cornerRadius: 4 * s))
            .fixedSize()
            .position(x: min(max(h.point.x + 70 * s, 80 * s), 400 * s), y: max(h.point.y - 40 * s, 50 * s))
            .allowsHitTesting(false)
        }
    }
}

private struct HistoryChart: View {
    let pts: [HistoryPoint]
    let title: String
    let color: Color
    let domain: ClosedRange<Double>
    let s: CGFloat
    let showX: Bool
    @Binding var hover: HoverInfo?
    let value: KeyPath<HistoryPoint, Double>
    static let coral = Color(nsColor: Palette.rgb(0xFF6464))

    var body: some View {
        let grid = Color(nsColor: Palette.button).opacity(0.25)
        let axisFont = Font.system(size: 12 * s, weight: .regular)
        Chart {
            if let h = hover, pts.indices.contains(h.index) {
                RuleMark(x: .value("Date", pts[h.index].x))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.white.opacity(0.4))
                PointMark(x: .value("Date", pts[h.index].x), y: .value(title, pts[h.index][keyPath: value]))
                    .symbolSize(70)
                    .foregroundStyle(color)
                if title == "Moves", let f = pts[h.index].deficit {
                    PointMark(x: .value("Date", pts[h.index].x), y: .value("Deficit", f))
                        .symbolSize(50)
                        .foregroundStyle(Self.coral)
                }
            }
            if title == "Moves" {
                ForEach(Array(pts.enumerated()), id: \.offset) { _, r in
                    if let f = r.deficit {
                        LineMark(x: .value("Date", r.x), y: .value("Deficit", f), series: .value("Series", "deficit"))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                            .foregroundStyle(Self.coral)
                        PointMark(x: .value("Date", r.x), y: .value("Deficit", f))
                            .symbolSize(8)
                            .foregroundStyle(Self.coral)
                    }
                }
                ForEach(Array(pts.enumerated()), id: \.offset) { _, r in
                    if let o = r.optimal {
                        LineMark(x: .value("Date", r.x), y: .value("Optimal", o), series: .value("Series", "optimal"))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .foregroundStyle(Color(nsColor: Palette.button))
                        PointMark(x: .value("Date", r.x), y: .value("Optimal", o))
                            .symbolSize(10)
                            .foregroundStyle(Color(nsColor: Palette.button))
                    }
                }
            }
            ForEach(Array(pts.enumerated()), id: \.offset) { _, r in
                LineMark(x: .value("Date", r.x), y: .value(title, r[keyPath: value]), series: .value("Series", "player"))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .foregroundStyle(color)
                PointMark(x: .value("Date", r.x), y: .value(title, r[keyPath: value]))
                    .symbolSize(14)
                    .foregroundStyle(color)
            }
        }
        .chartXScale(domain: domain)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let loc):
                            guard let pf = proxy.plotFrame,
                                  let d: Double = proxy.value(atX: loc.x - geo[pf].origin.x) else { return }
                            let i = pts.indices.min { abs(pts[$0].x - d) < abs(pts[$1].x - d) }
                            let o = geo.frame(in: .named("hist")).origin
                            hover = i.map { HoverInfo(index: $0, point: CGPoint(x: loc.x + o.x, y: loc.y + o.y)) }
                        case .ended:
                            hover = nil
                        }
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { v in
                AxisGridLine().foregroundStyle(grid)
                if showX {
                    AxisValueLabel {
                        if let d = v.as(Double.self) {
                            Text(Date(timeIntervalSinceReferenceDate: d).formatted(.dateTime.month(.defaultDigits).day()))
                                .font(axisFont).foregroundColor(.white)
                        }
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(grid)
                AxisValueLabel {
                    if let d = v.as(Double.self) {
                        Text(d.formatted(.number.precision(.fractionLength(0...1))))
                            .font(axisFont).foregroundColor(.white)
                            .frame(width: 34 * s, alignment: .trailing)
                    }
                }
            }
        }
        .chartYAxisLabel(position: .leading) {
            Text(title).font(axisFont).foregroundColor(.white)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .padding(.vertical, 8 * s)
    }
}
