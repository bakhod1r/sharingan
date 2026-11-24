import SwiftUI
import SharinganCore

/// Re-renders `content` on every countdown tick. The per-second values live
/// on `PomodoroTimer.clock` (not on the timer) so the big views observing the
/// timer — task list, settings, menu bar popover — don't rebuild once a
/// second; wrap just the bits that *show* the time in this.
struct TimerTicking<Content: View>: View {
    @ObservedObject private var clock: TimerClock
    private let content: () -> Content

    init(_ clock: TimerClock, @ViewBuilder content: @escaping () -> Content) {
        self.clock = clock
        self.content = content
    }

    var body: some View { content() }
}
