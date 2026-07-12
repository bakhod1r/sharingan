import Foundation
import Testing
@testable import SharinganCore

/// Records presenter calls so tests can assert the overlay was torn down.
@MainActor
private final class SpyBreakPresenter: BreakPresenter {
    var presented = 0
    var dismissed = 0
    func presentBreak(timer: PomodoroTimer, onTapSkip: @escaping () -> Void) { presented += 1 }
    func dismissAll() { dismissed += 1 }
}

@MainActor
@Suite("Break overlay teardown")
struct BreakTeardownTests {
    /// Coordinator wired to a spy presenter and throwaway queue defaults.
    private func makeCoordinator() -> (SharinganCoordinator, SpyBreakPresenter, cleanup: () -> Void) {
        let name = "blink-break-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let coordinator = SharinganCoordinator(timer: PomodoroTimer(),
                                               focusQueue: FocusQueue(defaults: defaults))
        let spy = SpyBreakPresenter()
        coordinator.breakPresenter = spy
        return (coordinator, spy, { defaults.removePersistentDomain(forName: name) })
    }

    /// The coordinator's sinks deliver via `DispatchQueue.main` — let the queue
    /// turn over so scheduled work lands before asserting.
    private func drainMainQueue() async {
        await withCheckedContinuation { cont in
            DispatchQueue.main.async { cont.resume() }
        }
    }

    @Test func skipDuringBreakDismissesOverlay() async {
        let (c, spy, cleanup) = makeCoordinator()
        defer { cleanup() }
        c.timer.skip()                       // focus → break (overlay would be up)
        #expect(c.timer.phase.isBreak)
        await drainMainQueue()
        let before = spy.dismissed

        c.timer.skip()                       // break → focus with NO .phaseDidComplete
        await drainMainQueue()

        #expect(c.timer.phase == .focus)
        #expect(spy.dismissed > before)
    }

    @Test func stopDuringBreakDismissesOverlay() async {
        let (c, spy, cleanup) = makeCoordinator()
        defer { cleanup() }
        c.timer.skip()                       // focus → break
        #expect(c.timer.phase.isBreak)
        await drainMainQueue()
        let before = spy.dismissed

        c.timer.stop()                       // resets straight to focus, no notification
        await drainMainQueue()

        #expect(c.timer.phase == .focus)
        #expect(spy.dismissed > before)
    }

    @Test func pauseDuringBreakKeepsOverlay() async {
        let (c, spy, cleanup) = makeCoordinator()
        defer { cleanup() }
        c.timer.skip()                       // focus → break
        c.timer.start()
        await drainMainQueue()
        let before = spy.dismissed

        c.timer.pause()                      // break merely paused — still on break
        await drainMainQueue()

        #expect(spy.dismissed == before)
    }

    /// A 30+ s tick gap means the machine slept. Sleep must not credit focus
    /// time, but it DOES rest the eyes — so during a break the gap counts,
    /// letting the break complete (and the overlay come down) on wake instead
    /// of freezing mid-countdown.
    @Test func sleepGapCountsTowardBreakOnly() {
        #expect(PomodoroTimer.effectiveTickDelta(120, phase: .shortBreak) == 120)
        #expect(PomodoroTimer.effectiveTickDelta(3600, phase: .longBreak) == 3600)
        #expect(PomodoroTimer.effectiveTickDelta(120, phase: .focus) == 0.2)
        #expect(PomodoroTimer.effectiveTickDelta(5, phase: .focus) == 5)
        #expect(PomodoroTimer.effectiveTickDelta(5, phase: .shortBreak) == 5)
    }
}
