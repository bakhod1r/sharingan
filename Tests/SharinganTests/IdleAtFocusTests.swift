import Testing
@testable import SharinganCore

/// Visibility rule for the main window's in-ring size picker: it shows only
/// while nothing is in flight and the pending phase is a focus.
@Suite("Idle-at-focus (in-ring picker visibility)")
struct IdleAtFocusTests {

    @MainActor private func makeTimer(autoStartBreak: Bool = true) -> PomodoroTimer {
        let t = PomodoroTimer()
        var s = PomodoroSettings()
        s.autoStartBreak = autoStartBreak
        t.settings = s
        t.stop()
        return t
    }

    @MainActor @Test func freshTimerIsIdle() {
        let t = makeTimer()
        #expect(t.isIdleAtFocus)
    }

    @MainActor @Test func runningFocusIsNotIdle() {
        let t = makeTimer()
        t.start()
        #expect(!t.isIdleAtFocus)
        t.stop()
    }

    @MainActor @Test func pausedIsNotIdle() {
        let t = makeTimer()
        t.start()
        t.pause()
        #expect(!t.isIdleAtFocus)
        t.stop()
    }

    @MainActor @Test func pendingBreakIsNotIdle() {
        let t = makeTimer(autoStartBreak: false)
        t.start()
        t.skip()
        #expect(t.phase == .shortBreak)
        #expect(!t.isRunning)
        #expect(!t.isIdleAtFocus) // waiting at a break ≠ idle at focus
        t.stop()
    }

    @MainActor @Test func stopReturnsToIdle() {
        let t = makeTimer()
        t.start()
        t.pause()
        t.stop()
        #expect(t.isIdleAtFocus)
    }
}
