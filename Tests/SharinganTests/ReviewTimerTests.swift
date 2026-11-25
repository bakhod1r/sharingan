import Testing
import Foundation
@testable import SharinganCore

/// REVIEW 1.1 / 2.9 / 3.1 / 3.3 — timer display, CLI snapshot, CLI adjust,
/// clock-vs-mm:ss parsing, blink rate, TTS lead-in.
@MainActor
@Suite("Review — timer, CLI, parser")
struct ReviewTimerTests {

    // MARK: 1.1 displaySeconds

    @Test func displaySecondsStaticPicksByMode() {
        #expect(PomodoroTimer.displaySeconds(countUp: true, elapsed: 42, remaining: 100) == 42)
        #expect(PomodoroTimer.displaySeconds(countUp: false, elapsed: 42, remaining: 100) == 100)
    }

    @Test func displaySecondsOnTimerFollowsMode() {
        var s = PomodoroSettings()
        s.timerMode = .countUp
        let up = PomodoroTimer(settings: s)
        #expect(up.isCountUpMode)
        #expect(up.displaySeconds == up.elapsedSeconds)

        s.timerMode = .countdown
        let down = PomodoroTimer(settings: s)
        #expect(!down.isCountUpMode)
        #expect(down.displaySeconds == down.remainingSeconds)
    }

    // MARK: 1.1 StateSnapshot

    @Test func snapshotDecodesLegacyJSONWithoutCountUpFields() throws {
        let json = """
        {"phase":"focus","remainingSeconds":600,"totalSeconds":1500,
         "isRunning":true,"cyclesCompletedToday":2,"streak":3}
        """
        let snap = try JSONDecoder().decode(CLIBridge.StateSnapshot.self, from: Data(json.utf8))
        #expect(snap.remainingSeconds == 600)
        #expect(snap.isCountUp == nil)
        #expect(snap.elapsedSeconds == nil)
    }

    @Test func snapshotRoundTripKeepsCountUpFields() throws {
        let snap = CLIBridge.StateSnapshot(phase: .focus, remainingSeconds: 100,
                                           totalSeconds: 1500, isRunning: true,
                                           cyclesCompletedToday: 1, streak: 1,
                                           updatedAt: Date(timeIntervalSince1970: 1000),
                                           isCountUp: true, elapsedSeconds: 1400)
        let data = try JSONEncoder().encode(snap)
        let back = try JSONDecoder().decode(CLIBridge.StateSnapshot.self, from: data)
        #expect(back == snap)
        #expect(back.isCountUp == true)
        #expect(back.elapsedSeconds == 1400)
    }

    // MARK: CLI start — target time must run, add/remove must not

    @Test func cliStartRunsForSetDurationAndTargetTime() {
        #expect(SharinganCoordinator.cliStartShouldRun(.setDuration(600)))
        #expect(SharinganCoordinator.cliStartShouldRun(.setTargetTime(Date().addingTimeInterval(3600))))
        #expect(!SharinganCoordinator.cliStartShouldRun(.addTime(60)))
        #expect(!SharinganCoordinator.cliStartShouldRun(.removeTime(60)))
    }

    // MARK: 2.9 CLI adjust

    @Test func cliAddUnsignedDurationAdds() {
        #expect(SharinganCoordinator.cliAdjustment(payload: "5m", negative: false) == 300)
    }

    @Test func cliRemoveUnsignedDurationSubtracts() {
        #expect(SharinganCoordinator.cliAdjustment(payload: "10m", negative: true) == -600)
    }

    @Test func cliAdjustSignedPayloadsStillWork() {
        #expect(SharinganCoordinator.cliAdjustment(payload: "+5m", negative: false) == 300)
        #expect(SharinganCoordinator.cliAdjustment(payload: "garbage", negative: false) == nil)
    }

    // MARK: 2.9 parser

    @Test func colonFormValidClockIsTargetTime() {
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 8; c.hour = 10; c.minute = 0
        let now = Calendar.current.date(from: c)!
        guard case .setTargetTime(let t)? = NaturalLanguageParser.parse("17:00", now: now)?.kind else {
            Issue.record("17:00 should be a clock target"); return
        }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: t)
        #expect(comps.hour == 17 && comps.minute == 0)
    }

    @Test func colonFormInvalidClockIsMinutesSeconds() {
        guard case .setDuration(let d)? = NaturalLanguageParser.parse("25:00")?.kind else {
            Issue.record("25:00 should be mm:ss"); return
        }
        #expect(d == 25 * 60)
    }

    // MARK: 3.1 blink rate

    @Test func eyeStateBlinkRate() {
        let s = EyeState(left: 1, right: 1, blinking: false, total: 5, blinkRate: 12)
        #expect(s.blinkRatePerMinute == 12)
        let d = EyeState(left: 1, right: 1, blinking: false, total: 0)
        #expect(d.blinkRatePerMinute == 0)
    }

    // MARK: 3.3 TTS lead-in

    @Test func speechDelayClampsAtZero() {
        let now = Date()
        #expect(TTSKalibrator.speechDelay(now: now, notBefore: now.addingTimeInterval(2)) == 2)
        #expect(TTSKalibrator.speechDelay(now: now, notBefore: now.addingTimeInterval(-5)) == 0)
        #expect(TTSKalibrator.leadInSeconds > 0)
    }
}

// MARK: - 1.1 widget snapshot (count-up) and 2.4 start guard

@Suite("Review — widget snapshot & start guard")
struct ReviewWidgetStartTests {
    @Test func legacyWidgetSnapshotDecodesAsCountdown() throws {
        let snap = WidgetSnapshot.sample()
        var obj = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(snap)) as! [String: Any]
        obj.removeValue(forKey: "isCountUp")
        obj.removeValue(forKey: "elapsedSeconds")
        let data = try JSONSerialization.data(withJSONObject: obj)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .deferredToDate
        let back = try dec.decode(WidgetSnapshot.self, from: data)
        #expect(back.isCountUp == nil)
        #expect(back.staticDisplaySeconds == back.remainingSeconds)
    }

    @Test func countUpWidgetSnapshotShowsElapsed() {
        let s = WidgetSnapshot(phase: .paused, isRunning: false,
                               remainingSeconds: 1000, totalSeconds: 1500,
                               updatedAt: Date(), isCountUp: true, elapsedSeconds: 500)
        #expect(s.staticDisplaySeconds == 500)
        #expect(s.idled().staticDisplaySeconds == 0)
    }

    @Test func floatingStartDecisionHandlesBreak() {
        #expect(FloatingWidgetStartAction.decide(isPaused: false, todayTaskCount: 3) == .showPicker)
        #expect(FloatingWidgetStartAction.decide(isPaused: false, todayTaskCount: 3, isBreak: true) == .startImmediately)
        #expect(FloatingWidgetStartAction.decide(isPaused: true, todayTaskCount: 3, isBreak: true) == .startImmediately)
    }

    @Test func focusStartBlockedOnlyForFreshFocusWithoutTask() {
        typealias C = SharinganCoordinator
        #expect(C.focusStartBlocked(isRunning: false, phase: .focus, requireTask: true, hasActiveTask: false))
        #expect(!C.focusStartBlocked(isRunning: false, phase: .focus, requireTask: false, hasActiveTask: false))
        #expect(!C.focusStartBlocked(isRunning: false, phase: .focus, requireTask: true, hasActiveTask: true))
        #expect(!C.focusStartBlocked(isRunning: false, phase: .shortBreak, requireTask: true, hasActiveTask: false))
        #expect(!C.focusStartBlocked(isRunning: false, phase: .paused, requireTask: true, hasActiveTask: false))
        #expect(!C.focusStartBlocked(isRunning: true, phase: .focus, requireTask: true, hasActiveTask: false))
    }
}
