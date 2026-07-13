import Testing
import Foundation
@testable import SharinganCore

@Suite("Notch HUD state")
struct NotchHUDStateTests {

    @Test("an idle, enabled HUD shows the bare island")
    func idleByDefault() {
        #expect(NotchHUDState().size == .idle)
    }

    @Test("disabling hides it in every other condition")
    func disabledWins() {
        var s = NotchHUDState()
        s.enabled = false
        s.hovering = true
        s.engaged = true
        s.activity = .sessionDone
        #expect(s.size == .hidden)
    }

    @Test("a running session shows the live ears")
    func engagedIsLive() {
        var s = NotchHUDState()
        s.engaged = true
        #expect(s.size == .live)
    }

    @Test("hover expands, from idle and from live alike")
    func hoverExpands() {
        var s = NotchHUDState()
        s.hovering = true
        #expect(s.size == .expanded)
        s.engaged = true
        #expect(s.size == .expanded)
    }

    @Test("an activity announcement preempts idle and live but not hover")
    func activityPreempts() {
        var s = NotchHUDState()
        s.activity = .breakStarted
        #expect(s.size == .activity)
        s.engaged = true
        #expect(s.size == .activity)
        s.hovering = true
        #expect(s.size == .expanded)
    }

    @Test("activities are suppressed when the user turned them off")
    func activityCanBeDisabled() {
        var s = NotchHUDState()
        s.liveActivityEnabled = false
        s.activity = .sessionDone
        #expect(s.size == .idle)
        s.engaged = true
        #expect(s.size == .live)
    }

    @Test("the break overlay hides the HUD entirely")
    func breakOverlayHides() {
        var s = NotchHUDState()
        s.engaged = true
        s.breakOverlayUp = true
        #expect(s.size == .hidden)
        s.hovering = true
        #expect(s.size == .hidden)
    }

    @Test("activity messages carry the task title")
    func activityMessages() {
        #expect(NotchActivity.taskDone("Ship it").message.contains("Ship it"))
        #expect(!NotchActivity.sessionDone.message.isEmpty)
        #expect(!NotchActivity.breakStarted.systemImage.isEmpty)
    }

    // MARK: - What the island may announce
    //
    // Two rules, two signals. `forPhaseChange` is fed by the manager's sink on
    // `timer.$phase`, which sees every *write* to the phase — pauses, resumes,
    // resets and skips included — so it may only claim that a break started.
    // `forCompletedPhase` is fed by `.phaseDidComplete`, which `PomodoroTimer`
    // posts from `phaseComplete()` alone, so it is the only thing entitled to
    // say something finished.

    @Test("a break starting announces it — the countdown ran out, or Skip did it")
    func breakStartAnnounces() {
        #expect(NotchActivity.forPhaseChange(from: .focus, to: .shortBreak) == .breakStarted)
        #expect(NotchActivity.forPhaseChange(from: .focus, to: .longBreak) == .breakStarted)
    }

    @Test("a break that ran to zero announces the session is complete")
    func completedBreakAnnounces() {
        #expect(NotchActivity.forCompletedPhase(.shortBreak) == .sessionDone)
        #expect(NotchActivity.forCompletedPhase(.longBreak) == .sessionDone)
    }

    /// The completed focus rolls straight into the break, which announces
    /// itself; the island has one 2-second slot and "Break time" is the line
    /// worth spending it on.
    @Test("a completed focus phase leaves the announcement to the break it starts")
    func completedFocusDefersToTheBreak() {
        #expect(NotchActivity.forCompletedPhase(.focus) == nil)
        #expect(NotchActivity.forCompletedPhase(.paused) == nil)
    }

    /// The regression that started all this: `pause()` writes `phase = .paused`,
    /// so mid-break the phase sink used to read `.shortBreak → .paused` as
    /// leaving a break and announce "Session complete" for a break still sitting
    /// there half-finished — then "Break time" all over again on resume.
    @Test("pausing and resuming during a break says nothing")
    func pauseAndResumeDuringABreakAreSilent() {
        for brk in [PomodoroPhase.shortBreak, .longBreak] {
            #expect(NotchActivity.forPhaseChange(from: brk, to: .paused) == nil)
            #expect(NotchActivity.forPhaseChange(from: .paused, to: brk) == nil)
        }
        #expect(NotchActivity.forPhaseChange(from: .focus, to: .paused) == nil)
        #expect(NotchActivity.forPhaseChange(from: .paused, to: .focus) == nil)
    }

    /// Reset (`stop()`) — and every task row's play button, which calls it —
    /// writes `phase = .focus`. Leaving a break is not a break completing.
    @Test("resetting out of a break says nothing")
    func resetDuringABreakIsSilent() {
        #expect(NotchActivity.forPhaseChange(from: .shortBreak, to: .focus) == nil)
        #expect(NotchActivity.forPhaseChange(from: .longBreak, to: .focus) == nil)
        // …and no completion was posted for it, so nothing announces it there either.
    }

    /// `skip()` posts no `.phaseDidComplete`, so there is no full-screen break
    /// overlay for a skip: the island's announcement is the only signal the
    /// break began.
    @Test("skipping into a break announces it; skipping out of one is silent")
    func skipping() {
        #expect(NotchActivity.forPhaseChange(from: .focus, to: .shortBreak) == .breakStarted)
        #expect(NotchActivity.forPhaseChange(from: .shortBreak, to: .focus) == nil)
        // A skip while paused restores the real phase first (PomodoroTimer.skip),
        // so the sink never sees `.paused` as the source of a real move.
        #expect(NotchActivity.forPhaseChange(from: .paused, to: .shortBreak) == nil)
    }

    @Test("a natural focus → break completion announces the break, once")
    func naturalFocusCompletion() {
        // phaseComplete(.focus) → transitionToNext → .shortBreak
        #expect(NotchActivity.forCompletedPhase(.focus) == nil)
        #expect(NotchActivity.forPhaseChange(from: .focus, to: .shortBreak) == .breakStarted)
    }

    @Test("a natural break → focus completion announces the session, once")
    func naturalBreakCompletion() {
        // phaseComplete(.shortBreak) → transitionToNext → .focus
        #expect(NotchActivity.forCompletedPhase(.shortBreak) == .sessionDone)
        #expect(NotchActivity.forPhaseChange(from: .shortBreak, to: .focus) == nil)
    }

    /// App launch restores whatever phase the timer was already in. The manager
    /// holds `lastPhase == nil` until its first tick so nothing is announced for
    /// a phase it never saw *change*; the rule agrees for the degenerate case it
    /// can see — a phase that is its own predecessor.
    @Test("no change, no announcement")
    func launchAndIdleTicksAreSilent() {
        for phase in PomodoroPhase.allCases {
            #expect(NotchActivity.forPhaseChange(from: phase, to: phase) == nil)
        }
    }

    // MARK: - Suspension

    /// **The bug this exists to prevent.** The break overlay is a
    /// `.screenSaver`-level window: it lands on top of the notch panel, so a
    /// pointer sitting on the island when the break starts may never produce a
    /// `mouseExited`. If the state is carried through the suspension untouched,
    /// `hovering` is still set when the overlay drops — the island returns
    /// `.expanded`, its full hit-test mask goes live over the menu bar with the
    /// pointer nowhere near it, and nothing closes it, because `mouseMoved` only
    /// fires *inside* the island. Clearing the interaction on the way down is
    /// what makes the island come back the size the situation actually calls for.
    @Test("a HUD suspended mid-hover does not come back expanded")
    func suspensionForgetsTheHover() {
        var s = NotchHUDState()
        s.engaged = true
        s.hovering = true
        s.activity = .breakStarted
        #expect(s.size == .expanded)

        // The break overlay goes up: the island stands down, and forgets.
        s.breakOverlayUp = true
        s.clearTransientInteraction()
        #expect(s.size == .hidden)

        // The overlay drops. The session is still running, so the island is back
        // — but as the live ears, not as the full expanded panel.
        s.breakOverlayUp = false
        #expect(s.size == .live)
        #expect(!s.hovering)
        #expect(s.activity == nil)
    }

    /// The same reset, from an idle HUD switched off mid-hover and back on: it
    /// returns to the bare island, not to a 340×290 mask over the menu bar.
    @Test("a disabled-then-re-enabled HUD returns idle, not expanded")
    func teardownForgetsTheHover() {
        var s = NotchHUDState()
        s.hovering = true

        s.enabled = false
        s.clearTransientInteraction()
        #expect(s.size == .hidden)

        s.enabled = true
        #expect(s.size == .idle)
    }

    /// `engaged` is *not* transient: a session that was running is still running
    /// through a break overlay, and clearing it would flick the island back to
    /// idle for a frame when the overlay drops.
    @Test("a running session survives the suspension")
    func suspensionKeepsTheSession() {
        var s = NotchHUDState()
        s.engaged = true
        s.hovering = true
        s.clearTransientInteraction()
        #expect(s.engaged)
        #expect(s.size == .live)
    }
}
