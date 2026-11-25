import Foundation
import Testing
@testable import SharinganCore

@MainActor
private func makeValidator(forced: Bool = true, exercises: Int = 2) -> ExerciseValidator {
    let v = ExerciseValidator()
    v.exercises = (0..<exercises).map { i in
        BreakExercise(name: "e\(i)", steps: [.init(direction: "left", holdSeconds: 1)])
    }
    v.strictValidation = true
    v.forcedMode = forced
    v.start()
    return v
}

@Suite("Forced break — validator") @MainActor
struct ForcedBreakValidatorTests {
    @Test func wrongMoveResetsHoldProgress() {
        let v = makeValidator(); defer { v.stop() }
        v.ingest(gaze: .left, isBlinking: false)
        v.tick(0.8)
        #expect(v.heldSeconds > 0.7)
        v.ingest(gaze: .right, isBlinking: false)      // wrong move
        #expect(v.needsRetry)
        #expect(v.heldSeconds == 0)
        // Must be redone fully: 0.5 s more of a correct hold is not enough.
        v.ingest(gaze: .left, isBlinking: false)
        v.tick(0.5)
        #expect(v.exercisesCompleted == 0)
        v.tick(0.6)
        #expect(v.exercisesCompleted == 1)
    }

    @Test func nonForcedWrongMoveKeepsProgress() {
        let v = makeValidator(forced: false); defer { v.stop() }
        v.tick(0.8)
        v.ingest(gaze: .right, isBlinking: false)
        #expect(v.needsRetry)
        #expect(v.heldSeconds >= 0.8)
    }

    @Test func forcedUnmatchedStepNeverAutoAdvances() {
        let v = makeValidator(); defer { v.stop() }
        for _ in 0..<100 {
            v.ingest(gaze: .right, isBlinking: false)
            v.tick(0.2)
        }
        #expect(v.exercisesCompleted == 0)
    }

    @Test func sequenceCompletionAndRemaining() {
        let v = makeValidator(exercises: 2); defer { v.stop() }
        #expect(v.remainingExercises == 2)
        #expect(!v.isSequenceComplete)
        v.ingest(gaze: .left, isBlinking: false); v.tick(1.1)
        #expect(v.remainingExercises == 1)
        #expect(!v.isSequenceComplete)
        v.ingest(gaze: .left, isBlinking: false); v.tick(1.1)
        #expect(v.remainingExercises == 0)
        #expect(v.isSequenceComplete)
    }

    @Test func completionCallbackFiresOnce() {
        let v = makeValidator(exercises: 1); defer { v.stop() }
        var fired = 0
        v.onSequenceComplete = { fired += 1 }
        v.ingest(gaze: .left, isBlinking: false); v.tick(1.1)
        // Library loops; extra completions must not re-fire.
        v.ingest(gaze: .left, isBlinking: false); v.tick(1.1)
        #expect(fired == 1)
    }

    @Test func emptySequenceIsComplete() {
        let v = ExerciseValidator()
        v.exercises = []
        #expect(v.isSequenceComplete)
        #expect(v.remainingExercises == 0)
    }
}

@Suite("Forced break — gate") @MainActor
struct ForcedBreakGateTests {
    private final class Clock { var now = Date(timeIntervalSince1970: 1_000) }

    private func make(_ clock: Clock, _ v: ExerciseValidator) -> ForcedBreakGate {
        ForcedBreakGate(validator: v, now: { clock.now })
    }

    @Test func openWhileCameraPendingOrUnavailable() {
        let v = makeValidator(); defer { v.stop() }
        let g = make(Clock(), v)
        #expect(g.isOpen)                       // pending
        g.setCamera(.unavailable)
        #expect(g.isOpen)
        #expect(g.showsSuspendedNotice)
    }

    @Test func closedUntilSequenceDone() {
        let v = makeValidator(exercises: 1); defer { v.stop() }
        let g = make(Clock(), v)
        g.setCamera(.usable)
        #expect(!g.isOpen)
        #expect(g.isEngaged)
        v.ingest(gaze: .left, isBlinking: false); v.tick(1.1)
        #expect(g.isOpen)
    }

    @Test func faceLostForThirtySecondsOpensGate() {
        let c = Clock()
        let v = makeValidator(); defer { v.stop() }
        let g = make(c, v)
        g.setCamera(.usable)
        g.noteFace(true)
        c.now += 29
        #expect(!g.isOpen)
        c.now += 2
        #expect(g.isOpen)
        #expect(g.showsSuspendedNotice)
        g.noteFace(true)                        // user is back
        #expect(!g.isOpen)
        #expect(!g.showsSuspendedNotice)
    }
}

@Suite("Forced break — settings") @MainActor
struct ForcedBreakSettingsTests {
    @Test func defaultsOffAndDecodesWhenMissing() throws {
        #expect(PomodoroSettings().forcedBreakEnabled == false)
        let data = try JSONEncoder().encode(PomodoroSettings())
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj.removeValue(forKey: "forcedBreakEnabled")
        let stripped = try JSONSerialization.data(withJSONObject: obj)
        let s = try JSONDecoder().decode(PomodoroSettings.self, from: stripped)
        #expect(s.forcedBreakEnabled == false)
        var on = PomodoroSettings(); on.forcedBreakEnabled = true
        let back = try JSONDecoder().decode(PomodoroSettings.self,
                                            from: JSONEncoder().encode(on))
        #expect(back.forcedBreakEnabled)
    }
}

@Suite("Forced break — timer gate") @MainActor
struct ForcedBreakTimerTests {
    private func breakTimer(_ seconds: TimeInterval) -> PomodoroTimer {
        let t = PomodoroTimer()
        t.skip()                                // focus -> short break
        t.setCustomDuration(seconds)
        return t
    }

    private func wait(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }

    @Test func holdsAtZeroAndCountsOvertime() async {
        let t = breakTimer(0.3)
        var open = false
        t.breakCompletionGate = { open }
        t.start()
        // Poll (the suite shares a loaded machine): overtime must start and grow.
        for _ in 0..<100 where t.clock.overtimeSeconds < 0.5 { await wait(100) }
        #expect(t.phase.isBreak)
        #expect(t.isRunning)
        #expect(t.isOvertime)
        #expect(t.clock.overtimeSeconds >= 0.5)
        t.stop()
        _ = open; open = true
    }

    @Test func completesWhenGateOpens() async {
        let t = breakTimer(0.3)
        var open = false
        t.breakCompletionGate = { open }
        t.start()
        await wait(800)
        #expect(t.phase.isBreak)
        open = true
        await wait(1500)                        // loop re-check
        #expect(t.phase == .focus)
        #expect(!t.isOvertime)
        #expect(t.clock.overtimeSeconds == 0)
    }

    @Test func releaseCompletesImmediately() async {
        let t = breakTimer(0.3)
        var open = false
        t.breakCompletionGate = { open }
        t.start()
        await wait(800)
        open = true
        t.releaseBreakGate()
        #expect(t.phase == .focus)
        #expect(!t.isOvertime)
    }

    @Test func releaseWhileGateStillClosedDoesNothing() async {
        let t = breakTimer(0.3)
        t.breakCompletionGate = { false }
        t.start()
        await wait(800)
        t.releaseBreakGate()
        #expect(t.phase.isBreak)
        #expect(t.isOvertime)
        t.stop()
    }

    @Test func gateOpenAtZeroCompletesNormally() async {
        let t = breakTimer(0.3)
        t.breakCompletionGate = { true }
        t.start()
        await wait(1500)
        #expect(t.phase == .focus)
        #expect(!t.isOvertime)
    }

    @Test func focusPhaseIgnoresGate() async {
        let t = PomodoroTimer()
        t.setCustomDuration(0.3)
        t.breakCompletionGate = { false }
        t.start()
        await wait(1500)
        #expect(t.phase.isBreak)                // focus completed -> break, not held
    }

    @Test func skipAndStopEscapeOvertime() async {
        let t = breakTimer(0.3)
        t.breakCompletionGate = { false }
        t.start()
        await wait(800)
        #expect(t.isOvertime)
        t.skip()
        #expect(t.phase == .focus)
        #expect(!t.isOvertime)

        let u = breakTimer(0.3)
        u.breakCompletionGate = { false }
        u.start()
        await wait(800)
        u.stop()
        #expect(u.phase == .focus)
        #expect(!u.isOvertime)
        #expect(u.clock.overtimeSeconds == 0)
    }

    @Test func gateClosedReflectsState() async {
        let t = breakTimer(30)
        #expect(!t.isBreakGateClosed)           // no gate
        t.breakCompletionGate = { false }
        #expect(t.isBreakGateClosed)
        t.breakCompletionGate = { true }
        #expect(!t.isBreakGateClosed)
        let f = PomodoroTimer()
        f.breakCompletionGate = { false }
        #expect(!f.isBreakGateClosed)           // focus phase
    }
}

@Suite("Forced break — coordinator skip") @MainActor
struct ForcedBreakCoordinatorTests {
    private func make() -> (SharinganCoordinator, cleanup: () -> Void) {
        let name = "blink-forced-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let c = SharinganCoordinator(timer: PomodoroTimer(),
                                     focusQueue: FocusQueue(defaults: defaults))
        return (c, { defaults.removePersistentDomain(forName: name) })
    }

    @Test func externalSkipIgnoredWhileGateClosed() {
        let (c, cleanup) = make(); defer { cleanup() }
        c.timer.skip()                          // -> break
        c.timer.breakCompletionGate = { false }
        c.handle(.skip)
        #expect(c.timer.phase.isBreak)
        c.requestSkip()
        #expect(c.timer.phase.isBreak)
        c.timer.breakCompletionGate = { true }
        c.handle(.skip)
        #expect(c.timer.phase == .focus)
    }

    @Test func resetStillWorks() {
        let (c, cleanup) = make(); defer { cleanup() }
        c.timer.skip()
        c.timer.breakCompletionGate = { false }
        c.handle(.reset)
        #expect(c.timer.phase == .focus)
    }
}
