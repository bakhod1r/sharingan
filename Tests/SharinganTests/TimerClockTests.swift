import Testing
import Foundation
import Combine
@testable import SharinganCore

/// The per-second countdown lives on `timer.clock`, not on the timer itself:
/// every view that observes `PomodoroTimer` (task list, settings, menu bar
/// popover…) used to re-render once a second for the whole session even
/// though only the countdown displays read the ticking values.
@MainActor
@Suite("Timer clock split")
struct TimerClockTests {

    @Test("a time change publishes on the clock, not on the timer")
    func tickDoesNotInvalidateTimerObservers() {
        let timer = PomodoroTimer()
        var timerFired = 0, clockFired = 0
        let a = timer.objectWillChange.sink { _ in timerFired += 1 }
        let b = timer.clock.objectWillChange.sink { _ in clockFired += 1 }
        timer.addTime(60)
        #expect(timerFired == 0)
        #expect(clockFired > 0)
        _ = (a, b)
    }

    @Test("the timer reads its time from the clock")
    func timerMirrorsClock() {
        let timer = PomodoroTimer()
        let before = timer.remainingSeconds
        timer.addTime(60)
        #expect(timer.remainingSeconds == before + 60)
        #expect(timer.clock.remainingSeconds == timer.remainingSeconds)
        #expect(timer.clock.elapsedSeconds == timer.elapsedSeconds)
    }

    @Test("state changes still publish on the timer")
    func stateChangesStillPublish() {
        let timer = PomodoroTimer()
        var timerFired = 0
        let a = timer.objectWillChange.sink { _ in timerFired += 1 }
        timer.start()
        #expect(timerFired > 0)
        timer.stop()
        _ = a
    }
}
