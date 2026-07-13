import Testing
import Foundation
@testable import SharinganCore

@Suite("Pomodoro models")
struct PomodoroModelsTests {

    @Test func phaseDurations() {
        let s = PomodoroSettings()
        #expect(s.focusSeconds == 25 * 60)
        #expect(s.shortBreakSeconds == 5 * 60)
        #expect(s.longBreakSeconds == 15 * 60)
        #expect(s.duration(for: .focus) == 25 * 60)
        #expect(s.duration(for: .shortBreak) == 5 * 60)
        #expect(s.duration(for: .longBreak) == 15 * 60)
    }

    @Test func settingsCodableRoundTrip() throws {
        var s = PomodoroSettings()
        s.focusMinutes = 40
        s.shortBreakMinutes = 10
        s.ttsRate = 0.7

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(PomodoroSettings.self, from: data)

        #expect(decoded == s)
        #expect(decoded.focusMinutes == 40)
        #expect(decoded.shortBreakMinutes == 10)
        #expect(decoded.ttsRate == 0.7)
    }

    @Test func statsRegistration() {
        var stats = PomodoroStats()
        stats.registerFocusCompletion()
        stats.registerFocusCompletion()
        #expect(stats.completedFocus == 2)
        #expect(stats.completedToday == 2)
        // Same-day call is a no-op — a legitimate running count is never wiped.
        stats.resetTodayIfNeeded()
        #expect(stats.completedToday == 2)
        // The counter rolls to zero only once the stored day is in the past.
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        stats.resetTodayIfNeeded(now: tomorrow)
        #expect(stats.completedToday == 0)
        #expect(stats.completedFocus == 2)
    }

    @Test func phaseMetadata() {
        #expect(!PomodoroPhase.focus.label.isEmpty)
        #expect(!PomodoroPhase.focus.systemImage.isEmpty)
        #expect(PomodoroPhase.allCases.count == 4)
        #expect(PomodoroPhase.focus.gradient.count == 2)
    }

    @Test func durationForPausedPhase() {
        let s = PomodoroSettings()
        #expect(s.duration(for: .paused) == 0)
    }

    @Test("cyclic gradient matches expected color stacks")
    func phaseGradientColors() {
        #expect(PomodoroPhase.focus.gradient == [.paletteFocusStart, .paletteFocusEnd])
        #expect(PomodoroPhase.shortBreak.gradient == [.paletteBreakStart, .paletteBreakEnd])
        #expect(PomodoroPhase.longBreak.gradient == [.paletteLongStart, .paletteLongEnd])
        #expect(PomodoroPhase.paused.gradient == [.paletteMutedStart, .paletteMutedEnd])
    }

    @Test("old subtask JSON without pomodoro keys still decodes")
    func subtaskDecodeDrift() throws {
        let old = #"{"id":"00000000-0000-0000-0000-000000000001","title":"step","isDone":false}"#
        let sub = try JSONDecoder().decode(Subtask.self, from: Data(old.utf8))
        #expect(sub.title == "step")
        #expect(sub.estimatedPomodoros == nil)
        #expect(sub.pomodorosDone == 0)
    }

    @Test("displayEstimate: subtask sum wins, else task estimate, else nil")
    func displayEstimatePrecedence() {
        var t = TaskItem(title: "t", estimatedPomodoros: 5)
        #expect(t.displayEstimate == 5)
        t.subtasks = [Subtask(title: "a", estimatedPomodoros: 2),
                      Subtask(title: "b", estimatedPomodoros: 3),
                      Subtask(title: "c")]                    // no estimate — excluded
        #expect(t.subtaskEstimateTotal == 5)
        #expect(t.displayEstimate == 5)
        t.subtasks[0].estimatedPomodoros = 4
        #expect(t.displayEstimate == 7)                       // sum overrides task's own
        t.subtasks = [Subtask(title: "a")]
        t.estimatedPomodoros = nil
        #expect(t.displayEstimate == nil)
    }

    @Test("settings blob missing the planning keys decodes to defaults")
    func planningSettingsDecodeDrift() throws {
        let decoded = try JSONDecoder().decode(PomodoroSettings.self,
                                               from: Data("{}".utf8))
        #expect(decoded.weekStartsOnMonday == true)
        #expect(decoded.defaultSubtaskEstimate == 0)
        #expect(decoded.showPomodoroBadges == true)
    }

    @Test("weekStart anchors on Monday or Sunday and shifts by whole weeks")
    func weekStartMath() {
        let cal = Calendar.current
        // A known Thursday: 2026-07-09.
        var comps = DateComponents(); comps.year = 2026; comps.month = 7; comps.day = 9
        let thursday = cal.date(from: comps)!

        var s = PomodoroSettings()
        s.weekStartsOnMonday = true
        let mon = s.weekStart(offset: 0, now: thursday, calendar: cal)
        #expect(cal.component(.weekday, from: mon) == 2)      // Monday
        #expect(cal.component(.day, from: mon) == 6)          // Jul 6

        s.weekStartsOnMonday = false
        let sun = s.weekStart(offset: 0, now: thursday, calendar: cal)
        #expect(cal.component(.weekday, from: sun) == 1)      // Sunday
        #expect(cal.component(.day, from: sun) == 5)          // Jul 5

        let nextSun = s.weekStart(offset: 1, now: thursday, calendar: cal)
        #expect(cal.dateComponents([.day], from: sun, to: nextSun).day == 7)

        // A week-start day maps onto itself.
        s.weekStartsOnMonday = true
        let selfStart = s.weekStart(offset: 0, now: mon, calendar: cal)
        #expect(cal.isDate(selfStart, inSameDayAs: mon))
    }
}
@Suite("Menu bar countdown setting")
struct MenuBarCountdownSettingTests {
    @Test func defaultsToOn() {
        #expect(PomodoroSettings().showMenuBarCountdown == true)
    }

    @Test func decodingOldBlobWithoutKeyFallsBackToDefault() throws {
        let old = try JSONSerialization.data(withJSONObject: ["focusMinutes": 30])
        let s = try JSONDecoder().decode(PomodoroSettings.self, from: old)
        #expect(s.showMenuBarCountdown == true)
        #expect(s.focusMinutes == 30)
    }

    @Test func roundTripsWhenOff() throws {
        var s = PomodoroSettings()
        s.showMenuBarCountdown = false
        let back = try JSONDecoder().decode(PomodoroSettings.self,
                                            from: JSONEncoder().encode(s))
        #expect(back.showMenuBarCountdown == false)
    }
}

@Suite("Per-kind long break")
struct PerKindLongBreakTests {
    @Test("override wins over the global value")
    func overrideWins() {
        var s = PomodoroSettings()
        s.activeKind = .big
        s.setConfig(.init(focusMinutes: 90, breakMinutes: 15, longBreakMinutes: 30),
                    for: .big)
        #expect(s.longBreakSeconds == 30 * 60)
    }

    @Test("no override falls back to the global value")
    func fallback() {
        var s = PomodoroSettings()
        s.activeKind = .small
        s.longBreakMinutes = 21
        #expect(s.longBreakSeconds == 21 * 60)
    }

    @Test("pre-per-size config JSON decodes with a nil override")
    func legacyConfigDecodes() throws {
        let json = Data(#"{"focusMinutes":25,"breakMinutes":5}"#.utf8)
        let c = try JSONDecoder().decode(PomodoroKindConfig.self, from: json)
        #expect(c.longBreakMinutes == nil)
    }
}
