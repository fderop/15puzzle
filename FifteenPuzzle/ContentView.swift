import SwiftUI

private extension Color {
    init(_ c: NSColor) { self.init(nsColor: c) }
}

struct ContentView: View {
    let controller: GameController   // not observed: moves never re-evaluate this view

    var body: some View {
        TabbedContent(controller: controller, tabs: controller.tabs)
    }
}

private struct TabbedContent: View {
    let controller: GameController
    @ObservedObject var tabs: TabState

    var body: some View {
        GeometryReader { geo in
            let s = max(0.5, min(geo.size.width / 480, geo.size.height / 630))
            ZStack {
                Color(Palette.background)
                PlayView(controller: controller, s: s)
                    .opacity(tabs.tab == .play ? 1 : 0)
                    .allowsHitTesting(tabs.tab == .play)
                if tabs.tab == .history {
                    HistoryView(history: controller.history, best: controller.best, s: s)
                        .padding(.top, 36 * s)
                }
                Picker("", selection: $tabs.tab) {
                    Text("Play").tag(AppTab.play)
                    Text("History").tag(AppTab.history)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .focusable(false)
                .frame(width: 150 * s)
                .padding(.top, 6 * s)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}

private struct PlayView: View {
    let controller: GameController
    let s: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            StatsView(controller: controller, s: s)
                .frame(width: 440 * s)
            Spacer().frame(height: 12 * s)
            BoardRepresentable(controller: controller)
                .frame(width: 440 * s, height: 440 * s)
            Spacer().frame(height: 14 * s)
            ButtonsRow(controller: controller, s: s)
            OptimalCounts(controller: controller, s: s)
            ReviewLine(controller: controller, s: s)
        }
        .padding(.top, 36 * s)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct StatsView: View {
    @ObservedObject var controller: GameController
    let s: CGFloat

    var body: some View {
        TimelineView(.animation(paused: controller.phase != .running)) { _ in
            let t = controller.elapsed()
            let tps = String(format: "%.3f", t > 0 ? Double(controller.moves) / t : 0)
            HStack(spacing: 0) {
                (Text(String(format: "%.3f", t)).foregroundColor(Color(Palette.gold))
                    + Text("s").foregroundColor(.white))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(controller.moves)").foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text(tps).foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: 20 * s, weight: .regular).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }
}

struct ReviewLine: View {
    @ObservedObject var controller: GameController
    let s: CGFloat

    var body: some View {
        Text(reviewLine)
            .font(.system(size: 12 * s, weight: .regular).monospacedDigit())
            .foregroundColor(.white)
            .frame(height: 16 * s)
            .padding(.top, 4 * s)
    }

    private var reviewLine: String {
        if controller.awaitingSolution { return "solving\u{2026}" }
        guard let n = controller.solutionLength,
              controller.phase == .solved || controller.phase == .reviewing else { return " " }
        if controller.phase == .reviewing {
            return "optimal: \(n) moves   \(controller.reviewPos) / \(n)   you: \(controller.moves)"
        }
        return "optimal: \(n) moves   you: \(controller.moves)"
    }
}

struct GrayButtonStyle: ButtonStyle {
    let s: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15 * s, weight: .regular))
            .foregroundColor(.white)
            .frame(width: 100 * s, height: 30 * s)
            .background(Color(Palette.button))
            .clipShape(RoundedRectangle(cornerRadius: 6 * s))
    }
}

struct ButtonsRow: View {
    @ObservedObject var controller: GameController
    let s: CGFloat

    var body: some View {
        HStack(spacing: 12 * s) {
            Button(controller.ghostEnabled ? "Ghost: on" : "Ghost: off") {
                controller.ghostEnabled.toggle()
            }
            .accessibilityLabel("Ghost")
            .accessibilityValue(controller.ghostEnabled ? "On" : "Off")
            if controller.phase == .solved || controller.phase == .reviewing {
                Button("Review") { controller.beginReview() }
                    .disabled(controller.phase == .reviewing || controller.awaitingSolution)
            }
        }
        .buttonStyle(GrayButtonStyle(s: s))
        .focusable(false)
        .frame(height: 30 * s)
    }
}


struct OptimalCounts: View {
    @ObservedObject var controller: GameController
    let s: CGFloat

    var body: some View {
        HStack(spacing: 24 * s) {
            Text("Original optimal: \(controller.solutionLength.map(String.init) ?? "…")")
            Text("Remaining optimal: \(controller.remainingOptimalMoves.map(String.init) ?? "…")")
        }
        .font(.system(size: 13 * s).monospacedDigit())
        .foregroundColor(.white)
        .padding(.top, 6 * s)
    }
}
