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
}
Task { @MainActor in
    SelfTest.main()
}

// Keep the process alive until the main-actor task completes.
import Foundation
RunLoop.main.run(until: Date().addingTimeInterval(60))
