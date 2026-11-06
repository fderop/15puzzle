import SwiftUI
import Charts

struct HistoryView: View {
    @ObservedObject var history: HistoryStore
    let best: PersonalBest?
    let s: CGFloat
    @State private var hover: HoverInfo?

    var body: some View {
        let recs = history.records
        VStack(spacing: 8 * s) {
            bestLine
            if recs.isEmpty {
                Text("No solves yet")
                    .font(.system(size: 15 * s, weight: .regular))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let lo = recs.map(\.date).min()!, hi = recs.map(\.date).max()!
                let pad: TimeInterval = hi.timeIntervalSince(lo) < 1 ? 3600 : hi.timeIntervalSince(lo) * 0.03
                let domain = lo.addingTimeInterval(-pad)...hi.addingTimeInterval(pad)
                VStack(spacing: 4 * s) {
                    HistoryChart(recs: recs, title: "Moves", color: Color(white: 0.9), domain: domain, s: s, showX: false, hover: $hover) { Double($0.moves) }
                    HistoryChart(recs: recs, title: "Time (s)", color: Color(nsColor: Palette.gold), domain: domain, s: s, showX: false, hover: $hover) { $0.seconds }
                    HistoryChart(recs: recs, title: "TPS", color: Color(nsColor: Palette.rgb(0x75FFDC)), domain: domain, s: s, showX: true, hover: $hover) { $0.tps }
                }
                .coordinateSpace(name: "hist")
                .overlay { tooltip(recs) }
            }
        }
        .padding(.horizontal, 20 * s)
        .padding(.top, 16 * s)
        .padding(.bottom, 16 * s)
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
    @ViewBuilder fileprivate func tooltip(_ recs: [SolveRecord]) -> some View {
        if let h = hover, recs.indices.contains(h.index) {
            let r = recs[h.index]
            VStack(alignment: .leading, spacing: 2 * s) {
                Text(r.date.formatted(date: .abbreviated, time: .shortened))
                Text(String(format: "Time: %.3f s", r.seconds))
                Text("Moves: \(r.moves)")
                if let o = r.optimalMoves {
                    Text(String(format: "optimal: %d moves (%.2f\u{00D7})", o, Double(r.moves) / Double(max(o, 1))))
                } else if r.scramble != nil {
                    Text("optimal: \u{2026}")
                }
                Text(String(format: "TPS: %.3f", r.tps))
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
    let recs: [SolveRecord]
    let title: String
    let color: Color
    let domain: ClosedRange<Date>
    let s: CGFloat
    let showX: Bool
    @Binding var hover: HoverInfo?
    let value: (SolveRecord) -> Double

    var body: some View {
        let grid = Color(nsColor: Palette.button).opacity(0.25)
        let axisFont = Font.system(size: 12 * s, weight: .regular)
        Chart {
            if let h = hover, recs.indices.contains(h.index) {
                RuleMark(x: .value("Date", recs[h.index].date))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.white.opacity(0.4))
                PointMark(x: .value("Date", recs[h.index].date), y: .value(title, value(recs[h.index])))
                    .symbolSize(70)
                    .foregroundStyle(color)
            }
            if title == "Moves" {
                ForEach(Array(recs.enumerated()), id: \.offset) { _, r in
                    if let o = r.optimalMoves {
                        LineMark(x: .value("Date", r.date), y: .value("Optimal", o), series: .value("Series", "optimal"))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .foregroundStyle(Color(nsColor: Palette.button))
                        PointMark(x: .value("Date", r.date), y: .value("Optimal", o))
                            .symbolSize(10)
                            .foregroundStyle(Color(nsColor: Palette.button))
                    }
                }
            }
            ForEach(Array(recs.enumerated()), id: \.offset) { _, r in
                LineMark(x: .value("Date", r.date), y: .value(title, value(r)), series: .value("Series", "player"))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .foregroundStyle(color)
                PointMark(x: .value("Date", r.date), y: .value(title, value(r)))
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
                                  let d: Date = proxy.value(atX: loc.x - geo[pf].origin.x) else { return }
                            let i = recs.indices.min { abs(recs[$0].date.timeIntervalSince(d)) < abs(recs[$1].date.timeIntervalSince(d)) }
                            let o = geo.frame(in: .named("hist")).origin
                            hover = i.map { HoverInfo(index: $0, point: CGPoint(x: loc.x + o.x, y: loc.y + o.y)) }
                        case .ended:
                            hover = nil
                        }
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(grid)
                if showX {
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                        .font(axisFont).foregroundStyle(.white)
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
