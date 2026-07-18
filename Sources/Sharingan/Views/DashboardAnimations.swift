import SwiftUI

/// Premium entrance/number animations for the Dashboard. Kept in one place so
/// every card animates with the same hand; all honour Reduce Motion.

/// A number that counts up from zero to its value when it first appears (and
/// re-counts when the value changes). Uses `.numericText` content transitions
/// for the rolling-digit feel. `format` renders the interpolated Double.
struct AnimatedNumber: View {
    let value: Double
    var duration: Double = 0.9
    var format: (Double) -> String

    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(format(reduceMotion ? value : shown))
            .contentTransition(.numericText(value: reduceMotion ? value : shown))
            .onAppear { animate(to: value) }
            .onChange(of: value) { _, new in animate(to: new) }
    }

    private func animate(to target: Double) {
        guard !reduceMotion else { shown = target; return }
        shown = 0
        withAnimation(.easeOut(duration: duration)) { shown = target }
    }
}

/// Fades + lifts a view into place, staggered by `index` so a row/grid of cards
/// cascades in. No-op under Reduce Motion.
private struct StaggeredAppear: ViewModifier {
    let index: Int
    var y: CGFloat = 14
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : y)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(DS.Motion.standard.delay(Double(index) * 0.06)) {
                    shown = true
                }
            }
    }
}

extension View {
    /// Cascade this card in, `index`-th in its group.
    func staggeredAppear(_ index: Int, y: CGFloat = 14) -> some View {
        modifier(StaggeredAppear(index: index, y: y))
    }
}
