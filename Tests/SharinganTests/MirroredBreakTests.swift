import Foundation
import Testing
@testable import SharinganCore

/// Records presenter calls so tests can assert the overlay came up/down.
@MainActor
private final class SpyPresenter: BreakPresenter {
    var presented = 0
    var dismissed = 0
    func presentBreak(timer: PomodoroTimer, onTapSkip: @escaping () -> Void) { presented += 1 }
    func dismissAll() { dismissed += 1 }
}

/// Mirrored sessions: a break synced in from another Mac must block this
/// screen too, must never auto-start the next pomodoro here (the owner Mac
/// decides), and must never clobber a session this Mac is running itself.
@MainActor
@Suite("Mirrored session — break overlay and ownership")
struct MirroredBreakTests {

    private func makeCoordinator() -> (SharinganCoordinator, SpyPresenter, cleanup: () -> Void) {
        let name = "blink-mirror-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let coordinator = SharinganCoordinator(timer: PomodoroTimer(),
                                               focusQueue: FocusQueue(defaults: defaults))
        let spy = SpyPresenter()
        coordinator.breakPresenter = spy
        return (coordinator, spy, { defaults.removePersistentDomain(forName: name) })
    }

    private func remoteState(phase: String, endsIn: TimeInterval?,
                             isPaused: Bool = false, now: Date = Date()) -> ActiveTimerState {
        ActiveTimerState(deviceID: "other-mac", deviceName: "Other",
                         phase: phase,
                         startedAt: now.addingTimeInterval(-60),
                         endsAt: endsIn.map { now.addingTimeInterval($0) },
                         isPaused: isPaused, taskTitle: nil, updatedAt: now)
    }

    @Test func mirroredBreakPresentsOverlay() {
        let (c, spy, cleanup) = makeCoordinator()
        defer { cleanup() }
        c.timer.settings.blockScreenDuringBreak = true

        c.applyRemoteTimer(remoteState(phase: PomodoroPhase.shortBreak.rawValue, endsIn: 120))

        #expect(c.timer.isMirroredSession)
        #expect(c.timer.phase == .shortBreak)
        #expect(spy.presented == 1)
    }

    @Test func mirroredBreakEndingRemotelyDismissesOverlay() {
        let (c, spy, cleanup) = makeCoordinator()
        defer { cleanup() }
        c.timer.settings.blockScreenDuringBreak = true

        c.applyRemoteTimer(remoteState(phase: PomodoroPhase.shortBreak.rawValue, endsIn: 120))
        #expect(spy.presented == 1)

        // Owner skipped the break → its record flips to focus.
        c.applyRemoteTimer(remoteState(phase: PomodoroPhase.focus.rawValue, endsIn: 1500))
        #expect(spy.dismissed >= 1)
        #expect(c.timer.phase == .focus)
    }

    @Test func remoteRecordNeverClobbersLocalSession() {
        let (c, _, cleanup) = makeCoordinator()
        defer { cleanup() }
        c.timer.setCustomDuration(600)          // the local 10-minute session
        c.timer.start()

        c.applyRemoteTimer(remoteState(phase: PomodoroPhase.focus.rawValue, endsIn: 1500))

        #expect(!c.timer.isMirroredSession)
        #expect(c.timer.isRunning)
        // Still the local 10-minute session, not the remote 25-minute one.
        #expect(c.timer.totalSeconds == 600)
    }

    @Test func remoteIdleDoesNotStopLocalSession() {
        let (c, _, cleanup) = makeCoordinator()
        defer { cleanup() }
        c.timer.start()

        c.applyRemoteTimer(remoteState(phase: ActiveTimerState.idlePhase, endsIn: nil))

        #expect(c.timer.isRunning)
    }

    @Test func mirroredPhaseCompletionDoesNotAutoStartNextPhase() async {
        let timer = PomodoroTimer()
        timer.settings.autoStartFocus = true
        timer.settings.autoStartBreak = true
        let now = Date()
        // A mirrored break that is effectively over: the first tick completes it.
        timer.applyMirroredSession(phase: .shortBreak, isPaused: false,
                                   startedAt: now.addingTimeInterval(-300),
                                   endsAt: now.addingTimeInterval(0.05),
                                   asOf: now, now: now)
        #expect(timer.isMirroredSession)

        // Poll — tick cadence is 200 ms, and a loaded main actor (full test
        // suite) can delay it well past a fixed sleep.
        for _ in 0..<40 where timer.phase != .focus {
            try? await Task.sleep(for: .milliseconds(100))
        }

        // The phase rolled over to focus but did NOT auto-start — the owner
        // Mac's next record decides.
        #expect(timer.phase == .focus)
        #expect(!timer.isRunning)
    }

    @Test func localControlTakesOwnershipBack() {
        let timer = PomodoroTimer()
        let now = Date()
        timer.applyMirroredSession(phase: .focus, isPaused: false,
                                   startedAt: now, endsAt: now.addingTimeInterval(1500),
                                   asOf: now, now: now)
        #expect(timer.isMirroredSession)
        timer.stop()
        #expect(!timer.isMirroredSession)
    }
}
