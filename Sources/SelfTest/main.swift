import Foundation
import BlinkCore

@MainActor
struct SelfTest {
    static var failures: Int = 0
    static var passed: Int = 0

    static func check(_ condition: Bool, _ msg: String,
                      file: String = #file, line: Int = #line) {
        if condition {
            passed += 1
            print("  ✓ \(msg)")
        } else {
            failures += 1
            print("  ✗ \(msg)  [\(file):\(line)]")
        }
    }

    static func main() {
        print("Blink self-tests")
        testModels()
        testTimerInitialState()
        testTimerSkipTransition()
        testTimerStopReset()
        testStatsFlow()
        testAddRemoveTime()
        testSetCustomDuration()
        testParserDurations()
        testParserClockTarget()
        testParserAddRemove()
        testCountUpMode()
        do { try testCoderRoundTrip() } catch {
            failures += 1
            print("  ✗ Codable threw: \(error)")
        }
testRepeatConfig()
        testStreakStore()
        testStatsWithStreak()
testAlarmSoundEnum()
        testGazeDirection()
        testBreakExerciseModel()
        testStreakRewardCenter()
        testReminders()
        testAmbienceEnum()

        print("\nPassed: \(passed)  Failed: \(failures)")
        if failures > 0 {
            print("SELF-TEST FAILED")
            exit(1)
        }
        print("SELF-TEST PASSED")
    }

    // MARK: Models

    static func testModels() {
        print("• Pomodoro models")
        let s = PomodoroSettings()
        check(s.focusSeconds == 25 * 60, "focusSeconds default 25m")
        check(s.shortBreakSeconds == 5 * 60, "shortBreakSeconds default 5m")
        check(s.longBreakSeconds == 15 * 60, "longBreakSeconds default 15m")
        check(s.duration(for: .focus) == 25 * 60, "duration(.focus)")
        check(s.duration(for: .paused) == 0, "duration(.paused) == 0")
        check(PomodoroPhase.allCases.count == 4, "phase count == 4")
        check(TimerMode.allCases.count == 2, "mode count == 2")
        check(BlinkTheme.allCases.count == 5, "theme count == 5")
        check(PomodoroPhase.focus.gradient.count == 2, "focus gradient stack")
    }

    static func testTimerInitialState() {
        print("• PomodoroTimer initial state")
        let timer = PomodoroTimer()
        check(timer.phase == .focus, "starts in focus")
        check(timer.isRunning == false, "not running initially")
        check(abs(timer.remainingSeconds - timer.settings.focusSeconds) < 0.001,
              "remaining == focus duration")
        check(timer.totalSeconds == timer.settings.focusSeconds, "total == focus")
        check(timer.progress == 0, "progress starts at 0")
        check(timer.cyclesCompletedInRound == 0, "cycles start at 0")
        check(timer.elapsedSeconds == 0, "elapsed starts at 0")
    }

    static func testTimerSkipTransition() {
        print("• timer.skip() focus -> shortBreak")
        let timer = PomodoroTimer()
        timer.skip()
        check(timer.phase == .shortBreak, "phase becomes shortBreak")
        check(timer.isRunning == false, "not auto-run on skip()")
        check(timer.remainingSeconds == timer.settings.shortBreakSeconds,
              "remaining set to short break duration")

        timer.skip()
        check(timer.phase == .focus, "skip shortBreak -> focus")
        check(timer.remainingSeconds == timer.settings.focusSeconds,
              "remaining reset to focus duration")
    }

    static func testTimerStopReset() {
        print("• timer.stop()")
        let timer = PomodoroTimer()
        timer.skip()
        timer.stop()
        check(timer.phase == .focus, "stop resets phase to focus")
        check(timer.cyclesCompletedInRound == 0, "stop clears cycles")
        check(timer.remainingSeconds == timer.settings.focusSeconds,
              "stop resets remaining")
        check(timer.elapsedSeconds == 0, "stop clears elapsed")
        check(timer.isRunning == false, "stop halts running")
        check(timer.repeatIndex == 0, "stop clears repeatIndex")
    }

    static func testStatsFlow() {
        print("• PomodoroStats flow")
        var stats = PomodoroStats()
        stats.registerFocusCompletion()
        stats.registerFocusCompletion()
        stats.registerFocusCompletion()
        check(stats.completedFocus == 3, "completedFocus accumulates")
        check(stats.completedToday == 3, "completedToday accumulates")
        stats.resetTodayIfNeeded()
        check(stats.completedToday == 0, "resetToday clears today")
        check(stats.completedFocus == 3, "global retained")
    }

    // MARK: New timer API

    static func testAddRemoveTime() {
        print("• add/remove time")
        let timer = PomodoroTimer()
        let start = timer.remainingSeconds
        timer.addTime(120)
        check(timer.remainingSeconds == start + 120, "addTime +120s")
        timer.removeTime(60)
        check(timer.remainingSeconds == start + 60, "removeTime -60s")
        timer.removeTime(3600)
        check(timer.remainingSeconds == 0, "removeTime floored at 0")
    }

    static func testSetCustomDuration() {
        print("• setCustomDuration / applyParsed")
        let timer = PomodoroTimer()
        timer.setCustomDuration(600)
        check(timer.remainingSeconds == 600, "setCustomDuration sets 600")
        check(timer.elapsedSeconds == 0, "elapsed reset after setCustom")
        check(timer.isRunning == false, "not running after setCustom")

        timer.applyParsed(.init(kind: .setDuration(1200)))
        check(timer.remainingSeconds == 1200, "applyParsed setDuration 1200")

        timer.applyParsed(.init(kind: .addTime(60)))
        check(timer.remainingSeconds == 1260, "applyParsed addTime")
        timer.applyParsed(.init(kind: .removeTime(120)))
        check(timer.remainingSeconds == 1140, "applyParsed removeTime")

        timer.applyParsed(.init(kind: .setDuration(0)))
        check(timer.cyclesCompletedInRound == 0, "setDuration(0) resets")
        check(timer.phase == .focus, "setDuration(0) phase focus")
    }

    // MARK: Parser

    static func testParserDurations() {
        print("• parser: durations")
        expectSetDuration("5 min", 300)
        expectSetDuration("5min", 300)
        expectSetDuration("20 minutes", 1200)
        expectSetDuration("2h 30m", 2 * 3600 + 30 * 60)
        expectSetDuration("2h30m", 2 * 3600 + 30 * 60)
        expectSetDuration("90 seconds", 90)
        expectSetDuration("25", 25 * 60)
        expectSetDuration("1h", 3600)
    }

    static func expectSetDuration(_ input: String, _ expected: TimeInterval,
                                  file: String = #file, line: Int = #line) {
        guard let p = NaturalLanguageParser.parse(input),
              case .setDuration(let d) = p.kind else {
            check(false, "parsed '\(input)'", file: file, line: line)
            return
        }
        check(abs(d - expected) < 0.001, "'\(input)' → \(d)s (expected \(expected)s)",
              file: file, line: line)
    }

    static func testParserClockTarget() {
        print("• parser: clock target")
        let now = Date()
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = 17
        comps.minute = 0
        comps.second = 0
        let expected5pm = cal.date(from: comps)!
        let shifted = expected5pm.addingTimeInterval(-3600)

        if let p = NaturalLanguageParser.parse("5pm", now: shifted),
           case .setTargetTime(let target) = p.kind {
            let delta = target.timeIntervalSince(shifted)
            check(abs(delta - 3600) < 5,
                  "'5pm' now+1h delta=\(delta)")
        } else {
            check(false, "'5pm' should parse to setTargetTime")
        }
    }

    static func testParserAddRemove() {
        print("• parser: add/remove")
        expectDelta("Add 5 min", 300)
        expectDelta("+5m", 300)
        expectDelta("Remove 1 hour", -3600)
        expectDelta("-1h", -3600)
    }

    static func expectDelta(_ input: String, _ expected: TimeInterval,
                            file: String = #file, line: Int = #line) {
        guard let p = NaturalLanguageParser.parse(input) else {
            check(false, "parsed '\(input)'", file: file, line: line)
            return
        }
        let actual: TimeInterval
        switch p.kind {
        case .addTime(let d):    actual = d
        case .removeTime(let d): actual = -d
        default:
            check(false, "'\(input)' expected add/remove", file: file, line: line)
            return
        }
        check(abs(actual - expected) < 0.001,
              "'\(input)' → \(actual)s (expected \(expected)s)",
              file: file, line: line)
    }

    // MARK: Count-up mode

    static func testCountUpMode() {
        print("• count-up mode")
        var settings = PomodoroSettings()
        settings.timerMode = .countUp
        let timer = PomodoroTimer()
        timer.settings = settings
        timer.setCustomDuration(60)
        check(timer.isCountUpMode == true, "countUp mode set")
        check(timer.isCountUpMode == true, "isCountUpMode true")
        check(timer.remainingSeconds == 60, "countUp remaining = 60")
        check(timer.elapsedSeconds == 0, "countUp elapsed starts 0")
        check(timer.progress == 0, "countUp starts at progress 0")
    }

    // MARK: Repeat

    static func testRepeatConfig() {
        print("• repeatConfig")
        let rep = RepeatConfig(enabled: true, count: 5, delaySeconds: 120)
        check(rep.enabled == true, "repeat enabled")
        check(rep.count == 5, "repeat count == 5")
        check(rep.delaySeconds == 120, "delay 120s")
        check(rep.delaysTotal == 4 * 120, "delaysTotal = (count-1)*delay")
        check(RepeatConfig().delaysTotal == 0, "default delaysTotal == 0")
        check(RepeatConfig(enabled: true, count: -3).count == 1,
              "negative count floored to 1")
        check(RepeatConfig(enabled: true, delaySeconds: -5).delaySeconds == 0,
              "negative delay floored to 0")
    }

    // MARK: Coder

    static func testCoderRoundTrip() throws {
        print("• Codable round-trip")
        var s = PomodoroSettings()
        s.focusMinutes = 45
        s.shortBreakMinutes = 10
        s.longBreakMinutes = 30
        s.longBreakEvery = 6
        s.ttsRate = 0.62
        s.ttsPitch = 1.2
        s.timerMode = .countUp
        s.theme = .neon
        s.repeatConfig = RepeatConfig(enabled: true, count: 3, delaySeconds: 90)
        s.flashAtFiveSecLeft = true
        s.floatingTimerEnabled = false
        s.globalShortcutsEnabled = false
        s.breakMessage = "Test message."

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(PomodoroSettings.self, from: data)

        check(decoded == s, "settings encode/decode equal")
        check(decoded.focusMinutes == 45, "decoded focusMinutes")
        check(decoded.timerMode == .countUp, "decoded timerMode")
        check(decoded.theme == .neon, "decoded theme")
        check(decoded.repeatConfig == s.repeatConfig, "decoded repeatConfig")
        check(decoded.floatingTimerEnabled == false, "decoded floating flag")
        check(abs(decoded.ttsRate - 0.62) < 0.0001, "decoded ttsRate")

        var stats = PomodoroStats()
        for _ in 0..<7 { stats.registerFocusCompletion() }
        let sdata = try JSONEncoder().encode(stats)
        let sdecoded = try JSONDecoder().decode(PomodoroStats.self, from: sdata)
        check(sdecoded == stats, "stats encode/decode equal")
        check(sdecoded.completedFocus == 7, "decoded stats count")
    }

    // MARK: Streak

    static func testStreakStore() {
        print("• StreakStore")
        var streak = StreakStore()
        check(streak.currentStreak == 0, "fresh streak 0")
        check(streak.longestStreak == 0, "fresh longest 0")
        check(streak.completedToday() == false, "nothing completed today")

        let cal = Calendar.current
        let today = Date()
        streak.registerFocus(on: today, calendar: cal)
        check(streak.currentStreak == 1, "first completion → streak 1")
        check(streak.longestStreak == 1, "longest updated to 1")
        check(streak.completedToday(on: today, calendar: cal) == true,
              "completedToday true after first")

        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        var s2 = StreakStore()
        s2.registerFocus(on: yesterday, calendar: cal)
        s2.registerFocus(on: today, calendar: cal)
        check(s2.currentStreak == 2, "consecutive days → streak 2")
        check(s2.longestStreak == 2, "longest = 2")

        // Gap of 3 days resets streak to 1
        let threeDaysAgo = cal.date(byAdding: .day, value: -3, to: today)!
        var s3 = StreakStore()
        s3.registerFocus(on: threeDaysAgo, calendar: cal)
        check(s3.currentStreak == 1, "streak 1 after first day")
        s3.registerFocus(on: today, calendar: cal)
        check(s3.currentStreak == 1, "gap resets streak to 1 (not continued)")
        check(s3.longestStreak == 1, "longest stays 1 after gap reset")

        // Same-day re-registration does not increase streak
        var s4 = StreakStore()
        s4.registerFocus(on: today, calendar: cal)
        s4.registerFocus(on: today, calendar: cal)
        check(s4.currentStreak == 1, "same-day re-register keeps streak 1")
    }

    static func testStatsWithStreak() {
        print("• PomodoroStats with streak")
        var stats = PomodoroStats()
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: Date())!
        stats.registerFocusCompletion(on: yesterday)
        stats.registerFocusCompletion(on: Date())
        check(stats.streak.currentStreak == 2, "stats streak 2 via registerFocusCompletion")
        check(stats.streakDays == 2, "streakDays mirrors currentStreak")
        check(stats.completedFocus == 2, "completedFocus increments")
    }

    static func testAlarmSoundEnum() {
        print("• AlarmSoundService.Sound")
        check(AlarmSoundService.Sound.allCases.count == 4, "4 sound cases")
        check(AlarmSoundService.Sound(rawValue: "glass") == .glass, "rawValue glass")
        check(AlarmSoundService.Sound(rawValue: "softBell") == .softBell, "rawValue softBell")
        check(AlarmSoundService.Sound(rawValue: "silent") == .silent, "rawValue silent")
        check(AlarmSoundService.Sound(rawValue: "invalid") == nil, "invalid rawValue → nil")
        check(AlarmSoundService.Sound.silent.label == "Silent", "silent label")
    }

    static func testGazeDirection() {
        print("• GazeDirection")
        check(GazeDirection.center.magnitude == 0, "center magnitude 0")
        check(GazeDirection.right.magnitude == 1, "right magnitude 1")
        check(GazeDirection.upLeft.magnitude - 0.9899 < 0.01, "upLeft ~0.99")
        check(GazeDirection.center.matches(.center), "center matches itself")
        check(GazeDirection.right.matches(.right), "right matches itself")
        check(GazeDirection.right.matches(GazeDirection(dx: 0.85, dy: 0.1)),
              "right matches near-right")
        check(!GazeDirection.right.matches(.left), "right does not match left")
        check(!GazeDirection.up.matches(.down), "up does not match down")
        check(GazeDirection(dx: 0, dy: 0).matches(.center, tolerance: 0.1),
              "near-center matches center")
        check(GazeDirection(dx: 1.2, dy: 1.5).dx == 1, "dx clamped to 1")
        check(GazeDirection(dx: -1.2, dy: 0).dx == -1, "dx clamped to -1")
        check(GazeDirection.center.label == "center", "center label")
        check(GazeDirection.right.label == "right", "right label")
        check(GazeDirection.up.label == "up", "up label")
    }

    static func testBreakExerciseModel() {
        print("• BreakExercise model")
        check(BreakExerciseStep(direction: "up", holdSeconds: 3).instruction.contains("up"),
              "auto instruction contains 'up'")
        check(BreakExerciseStep(direction: "down", holdSeconds: 0.1).holdSeconds == 0.5,
              "holdSeconds floor 0.5")
        check(BreakExerciseStep(direction: "left", holdSeconds: 4,
                                instruction: "Custom").instruction == "Custom",
              "custom instruktsiya saqlanadi")
        check(BreakExerciseStep(direction: "up", holdSeconds: 1).targetGaze == .up,
              "up → .up gaze")
        check(BreakExerciseStep(direction: "right", holdSeconds: 1).targetGaze == .right,
              "right → .right gaze")
        check(BreakExerciseStep(direction: "center", holdSeconds: 1).targetGaze == .center,
              "center → .center gaze")
        check(BreakExerciseStep(direction: "unknown", holdSeconds: 1).targetGaze == .center,
              "unknown → .center fallback")
        check(BreakExercise.twentyRule.steps.count == 2, "20-20-20 has 2 steps")
        check(BreakExercise.gaze.steps.count == 12, "gaze has 12 steps")
        check(BreakExercise.blink.steps.count == 2, "blink has 2 steps")
        check(BreakExercise.library().count == 3, "library has 3 exercises")
        check(BreakExercise.library() == [.twentyRule, .gaze, .blink],
              "library ordering")
    }

    static func testStreakRewardCenter() {
        print("• StreakRewardCenter")
        let center = StreakRewardCenter.shared
        center.resetForTesting()

        center.evaluate(streak: 0)
        check(center.pendingReward == nil, "no reward at streak 0")
        check(center.unlockedBadges.isEmpty, "no unlocked at streak 0")

        center.evaluate(streak: 1)
        check(center.pendingReward != nil, "reward at streak 1")
        check(center.pendingReward?.badge.id == "first", "first badge id")
        check(center.unlockedBadges.count == 1, "1 unlocked after streak 1")

        center.dismiss()
        check(center.pendingReward == nil, "dismissed clears pending")

        // Re-evaluating same streak should not re-fire.
        center.evaluate(streak: 1)
        check(center.pendingReward == nil, "no re-fire on same streak")

        // Jump to 7 → week badge unlocked.
        center.evaluate(streak: 7)
        check(center.pendingReward != nil, "reward at streak 7")
        check(center.pendingReward?.badge.id == "week", "week badge id")
        check(center.unlockedBadges.count == 2, "2 unlocked after streak 7")

        center.dismiss()

        // Jump to 30 → month badge unlocked, skipping 14 is fine but only
        // the highest newly-unlocked milestone shows.
        center.evaluate(streak: 30)
        check(center.pendingReward != nil, "reward at streak 30")
        check(center.pendingReward?.badge.id == "month", "month badge id")

        // Verify all milestones earned for streak 30.
        let earned30 = StreakBadge.earned(forStreak: 30)
        check(earned30.map { $0.id } == ["first", "week", "fortnight", "month"],
              "30-day earns 4 badges")

        // Next milestone after 30 is quarter (90).
        check(StreakBadge.next(forStreak: 30)?.id == "quarter",
              "next after 30 is quarter")

        // Next milestone after 0 is first (1).
        check(StreakBadge.next(forStreak: 0)?.id == "first",
              "next after 0 is first")

        // No next after 365.
        check(StreakBadge.next(forStreak: 400) == nil,
              "no next after 365+")

        center.resetForTesting()
        check(center.unlockedBadges.isEmpty, "reset clears unlocked")
    }

    static func testReminders() {
        print("• Reminders")
        let posture = ReminderItem(kind: .posture, intervalMinutes: 15)
        check(posture.kind == .posture, "posture kind")
        check(posture.intervalMinutes == 15, "interval 15")
        check(posture.intervalSeconds == 900, "intervalSeconds 900")
        check(posture.enabled == true, "enabled by default")
        check(posture.resolvedMessage.contains("straight"), "posture default msg")
        let water = ReminderItem(kind: .water, intervalMinutes: 10,
                                  message: "Drink water please")
        check(water.resolvedMessage == "Drink water please",
              "custom message overrides default")
        let custom = ReminderItem(kind: .custom, intervalMinutes: 0)
        check(custom.intervalMinutes == 1, "0 floored to 1")

        var s = ReminderSettings()
        check(s.enabled == true, "settings enabled default")
        check(s.duringFocusOnly == true, "focus-only default")
        check(s.reminders.count == 2, "2 default reminders")
        check(s.reminders[0].kind == .posture, "first is posture")
        check(s.reminders[1].kind == .water, "second is water")
        s.reminders.append(.init(kind: .custom, intervalMinutes: 30,
                                   message: "Stretch"))
        check(s.reminders.count == 3, "added custom reminder")
    }

    static func testAmbienceEnum() {
        print("• Ambience enum")
        check(BreakAmbienceService.Ambience.allCases.count == 5, "5 ambience cases")
        check(BreakAmbienceService.Ambience(rawValue: "rain") == .rain, "rain rawValue")
        check(BreakAmbienceService.Ambience(rawValue: "whiteNoise") == .whiteNoise, "whiteNoise")
        check(BreakAmbienceService.Ambience.silent.label == "Silent", "silent label")
        check(BreakAmbienceService.Ambience.rain.label == "Rain", "rain label")
        check(BreakAmbienceService.Ambience.lofi.label.contains("Lo-fi"), "lofi label")
    }
}
Task { @MainActor in
    SelfTest.main()
}

// Keep the process alive until the main-actor task completes.
import Foundation
RunLoop.main.run(until: Date().addingTimeInterval(60))
