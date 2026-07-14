import Foundation
import Testing
@testable import SharinganCore

@MainActor
@Suite("Skip during a running phase")
struct TimerSkipRaceTests {
    /// Skipping a RUNNING break must land on a clean focus countdown. The tick
    /// loop sleeps 200 ms between ticks; a skip that leaves the loop alive lets
    /// the in-flight tick wake up and write the dead break's remaining time
    /// over the fresh focus duration.
    @Test func skipDuringRunningBreakKeepsFocusDuration() async throws {
        let timer = PomodoroTimer(settings: .init())
        let focusDuration = timer.settings.duration(for: .focus)

        timer.skip()                    // focus → shortBreak
        #expect(timer.phase == .shortBreak)
        timer.start()                   // break counting down, loop alive
        try await Task.sleep(for: .milliseconds(500))

        timer.skip()                    // break → focus, idle
        #expect(timer.phase == .focus)
        #expect(!timer.isRunning)
        #expect(timer.remainingSeconds == focusDuration)

        // Let any in-flight tick land — the display must still show focus time.
        try await Task.sleep(for: .milliseconds(500))
        #expect(timer.phase == .focus)
        #expect(timer.remainingSeconds == focusDuration)
    }

    /// Same race in the other direction: skipping a running focus session must
    /// show the break's full duration, not focus leftovers.
    @Test func skipDuringRunningFocusKeepsBreakDuration() async throws {
        let timer = PomodoroTimer(settings: .init())

        timer.start()                   // focus running
        try await Task.sleep(for: .milliseconds(500))

        timer.skip()                    // focus → shortBreak, idle
        #expect(timer.phase == .shortBreak)
        let breakDuration = timer.settings.duration(for: .shortBreak)
        #expect(timer.remainingSeconds == breakDuration)

        try await Task.sleep(for: .milliseconds(500))
        #expect(timer.phase == .shortBreak)
        #expect(timer.remainingSeconds == breakDuration)
    }
}
