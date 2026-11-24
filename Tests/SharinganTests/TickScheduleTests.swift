import Testing
import Foundation
@testable import SharinganCore

/// The tick loop sleeps until the displayed second is about to flip instead
/// of polling every 200 ms — one wake-up per second instead of five.
@Suite("Tick schedule")
struct TickScheduleTests {

    @Test("countdown wakes just after the remaining time crosses a whole second")
    func countdownAlignsToSecond() {
        let d = PomodoroTimer.nextTickDelay(remaining: 10.3, elapsed: 4.7, mode: .countdown)
        #expect(d > 0.3 && d < 0.35)
    }

    @Test("count-up wakes just after the elapsed time crosses a whole second")
    func countUpAlignsToSecond() {
        let d = PomodoroTimer.nextTickDelay(remaining: 0, elapsed: 4.25, mode: .countUp)
        #expect(d > 0.75 && d < 0.8)
    }

    @Test("count-up on a whole second waits for the next one")
    func countUpOnBoundary() {
        let d = PomodoroTimer.nextTickDelay(remaining: 0, elapsed: 4, mode: .countUp)
        #expect(d > 1 && d < 1.05)
    }

    @Test("never busy-loops and never sleeps past a second")
    func clamped() {
        let onBoundary = PomodoroTimer.nextTickDelay(remaining: 10.0, elapsed: 0, mode: .countdown)
        #expect(onBoundary >= 0.05 && onBoundary <= 1.05)
        let tiny = PomodoroTimer.nextTickDelay(remaining: 10.001, elapsed: 0, mode: .countdown)
        #expect(tiny >= 0.05)
    }
}
