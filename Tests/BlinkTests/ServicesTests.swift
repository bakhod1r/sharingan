import Testing
import Foundation
@testable import BlinkCore

@Suite("Natural language parser")
struct NaturalLanguageParserTests {

    @Test func parsesPlainMinutes() throws {
        let p = try #require(NaturalLanguageParser.parse("25"))
        guard case .setDuration(let d) = p.kind else {
            Issue.record("expected setDuration"); return
        }
        #expect(d == 25 * 60)
    }

    @Test func parsesHoursAndMinutes() throws {
        let p = try #require(NaturalLanguageParser.parse("2h 30m"))
        guard case .setDuration(let d) = p.kind else {
            Issue.record("expected setDuration"); return
        }
        #expect(d == (2 * 60 + 30) * 60)
    }

    @Test func parsesAddDelta() throws {
        let p = try #require(NaturalLanguageParser.parse("+5m"))
        guard case .addTime(let d) = p.kind else {
            Issue.record("expected addTime"); return
        }
        #expect(d == 5 * 60)
    }

    @Test func parsesRemoveDelta() throws {
        let p = try #require(NaturalLanguageParser.parse("-1h"))
        guard case .removeTime(let d) = p.kind else {
            Issue.record("expected removeTime"); return
        }
        #expect(d == 60 * 60)
    }

    @Test func parsesClockTarget() throws {
        // 09:00 base → "5pm" resolves to a future target the same day.
        var comps = DateComponents()
        comps.year = 2026; comps.month = 7; comps.day = 4
        comps.hour = 9; comps.minute = 0
        let base = try #require(Calendar.current.date(from: comps))
        let p = try #require(NaturalLanguageParser.parse("5pm", now: base))
        guard case .setTargetTime(let target) = p.kind else {
            Issue.record("expected setTargetTime"); return
        }
        #expect(target > base)
    }

    @Test func rejectsGarbage() {
        #expect(NaturalLanguageParser.parse("") == nil)
        #expect(NaturalLanguageParser.parse("   ") == nil)
    }
}

@Suite("Gaze direction")
struct GazeDirectionTests {

    @Test func magnitudes() {
        #expect(GazeDirection.center.magnitude == 0)
        #expect(GazeDirection.right.magnitude == 1)
    }

    @Test func clamping() {
        #expect(GazeDirection(dx: 1.2, dy: 1.5).dx == 1)
        #expect(GazeDirection(dx: -1.2, dy: 0).dx == -1)
    }

    @Test func matching() {
        #expect(GazeDirection.right.matches(.right))
        #expect(GazeDirection.right.matches(GazeDirection(dx: 0.85, dy: 0.1)))
        #expect(!GazeDirection.right.matches(.left))
        #expect(!GazeDirection.up.matches(.down))
    }

    @Test func labels() {
        #expect(GazeDirection.center.label == "center")
        #expect(GazeDirection.right.label == "right")
        #expect(GazeDirection.up.label == "up")
    }
}

@Suite("Break exercise model")
struct BreakExerciseTests {

    @Test func stepClampsHold() {
        #expect(BreakExerciseStep(direction: "down", holdSeconds: 0.1).holdSeconds == 0.5)
    }

    @Test func customInstructionKept() {
        let step = BreakExerciseStep(direction: "left", holdSeconds: 4, instruction: "Custom")
        #expect(step.instruction == "Custom")
    }

    @Test func targetGazeMapping() {
        #expect(BreakExerciseStep(direction: "up", holdSeconds: 1).targetGaze == .up)
        #expect(BreakExerciseStep(direction: "right", holdSeconds: 1).targetGaze == .right)
        #expect(BreakExerciseStep(direction: "unknown", holdSeconds: 1).targetGaze == .center)
    }

    @Test func libraryNonEmpty() {
        #expect(!BreakExercise.library().isEmpty)
        #expect(!BreakExercise.twentyRule.steps.isEmpty)
    }
}

@Suite("Streak store")
struct StreakStoreTests {

    @Test func freshIsZero() {
        let s = StreakStore()
        #expect(s.currentStreak == 0)
        #expect(s.longestStreak == 0)
        #expect(s.completedToday() == false)
    }

    @Test func consecutiveDaysBuildStreak() {
        let cal = Calendar.current
        let today = Date()
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        var s = StreakStore()
        s.registerFocus(on: yesterday, calendar: cal)
        s.registerFocus(on: today, calendar: cal)
        #expect(s.currentStreak == 2)
        #expect(s.longestStreak == 2)
    }

    @Test func gapResetsStreak() {
        let cal = Calendar.current
        let today = Date()
        let threeDaysAgo = cal.date(byAdding: .day, value: -3, to: today)!
        var s = StreakStore()
        s.registerFocus(on: threeDaysAgo, calendar: cal)
        s.registerFocus(on: today, calendar: cal)
        #expect(s.currentStreak == 1)
    }

    @Test func sameDayDoesNotDoubleCount() {
        let cal = Calendar.current
        let today = Date()
        var s = StreakStore()
        s.registerFocus(on: today, calendar: cal)
        s.registerFocus(on: today, calendar: cal)
        #expect(s.currentStreak == 1)
    }
}

@Suite("Shortcut binding")
struct ShortcutBindingTests {

    @Test func requiresModifier() {
        #expect(ShortcutBinding(keyCode: 49, modifiers: 0).isValid == false)
        #expect(GlobalShortcut.toggle.defaultBinding.isValid == true)
    }

    @Test func defaultTogglePrintsCommonCombo() {
        // ⌃⌥ + Space
        let display = GlobalShortcut.toggle.defaultBinding.displayString
        #expect(display.contains("⌃"))
        #expect(display.contains("⌥"))
        #expect(display.contains("Space"))
    }

    @Test func codableRoundTrip() throws {
        let b = ShortcutBinding(keyCode: 3, modifiers: 0x0100)
        let data = try JSONEncoder().encode(b)
        let decoded = try JSONDecoder().decode(ShortcutBinding.self, from: data)
        #expect(decoded == b)
    }

    @Test func allShortcutsHaveDistinctDefaults() {
        let combos = GlobalShortcut.allCases.map {
            "\($0.defaultKeyCode)-\($0.defaultModifiers)"
        }
        #expect(Set(combos).count == GlobalShortcut.allCases.count)
    }
}

@MainActor
@Suite("Tasks")
struct TaskTests {
    private func tempStore() -> TaskStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("blink-test-\(UUID().uuidString).json")
        return TaskStore(fileURL: url)
    }

    @Test func addAndCountPomodoros() {
        let s = tempStore()
        s.add(title: "Write report", category: "Work", tags: ["a", "b"])
        #expect(s.tasks.count == 1)
        let id = s.tasks[0].id
        s.incrementPomodoro(id)
        s.incrementPomodoro(id)
        #expect(s.tasks[0].pomodorosDone == 2)
        #expect(s.tasks[0].tags == ["a", "b"])
    }

    @Test func overdueLogic() {
        let past = TaskItem(title: "x", dueDate: Date().addingTimeInterval(-100))
        let future = TaskItem(title: "y", dueDate: Date().addingTimeInterval(100))
        #expect(past.isOverdue())
        #expect(!future.isOverdue())
        var done = past; done.isDone = true
        #expect(!done.isOverdue())
    }

    @Test func csvHasHeaderAndEscapesCommas() {
        let s = tempStore()
        s.add(title: "Task, with comma", category: "Study")
        let csv = s.csv()
        #expect(csv.contains("title,category,tags,done,pomodoros,due,created"))
        #expect(csv.contains("\"Task, with comma\""))
    }

    @Test func persistsAcrossInstances() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("blink-persist-\(UUID().uuidString).json")
        let a = TaskStore(fileURL: url)
        a.add(title: "Persisted")
        let b = TaskStore(fileURL: url)
        #expect(b.tasks.contains { $0.title == "Persisted" })
    }

    @Test func categoryColorsResolve() {
        #expect(TaskCategory.color(for: "Work") == "#4F8DFD")
        #expect(TaskCategory.color(for: "Nonexistent") == "#9AA3AF")
    }

    @Test func smartViewFiltering() {
        let s = tempStore()
        let cal = Calendar.current
        s.add(title: "Due today", category: "Work",
              dueDate: cal.date(bySettingHour: 8, minute: 0, second: 0, of: Date()))
        s.add(title: "Later", category: "Work",
              dueDate: cal.date(byAdding: .day, value: 3, to: Date()))
        s.add(title: "Someday", category: "Work")
        s.add(title: "Finished", category: "Work")
        let doneID = s.tasks.first { $0.title == "Finished" }!.id
        s.toggleDone(doneID)

        // All = open tasks only; Done = completed only.
        #expect(s.count(.all) == 3)
        #expect(s.count(.completed) == 1)
        // Today includes the task due today; not the +3d one.
        let todayTitles = s.grouped(filter: .today).flatMap { $0.items.map(\.title) }
        #expect(todayTitles.contains("Due today"))
        #expect(!todayTitles.contains("Later"))
        // Upcoming is the future-dated task only.
        let upcoming = s.grouped(filter: .upcoming).flatMap { $0.items.map(\.title) }
        #expect(upcoming == ["Later"])
        // Search narrows within a view.
        #expect(s.grouped(filter: .all, search: "some").flatMap { $0.items }.count == 1)
    }

    @Test func clearCompletedRemovesOnlyDone() {
        let s = tempStore()
        s.add(title: "Keep")
        s.add(title: "Remove me")
        let id = s.tasks.first { $0.title == "Remove me" }!.id
        s.toggleDone(id)
        s.clearCompleted()
        #expect(s.tasks.count == 1)
        #expect(s.tasks.first?.title == "Keep")
    }
}

@Suite("Settings extras")
struct SettingsExtrasTests {

    @Test func newFlagDefaults() {
        let s = PomodoroSettings()
        #expect(s.alarmSoundEnabled == true)
        #expect(s.launchAtLogin == false)
        #expect(s.shortcutBindings.isEmpty)
    }

    @Test func customBindingSurvivesRoundTrip() throws {
        var s = PomodoroSettings()
        s.shortcutBindings["toggle"] = ShortcutBinding(keyCode: 3, modifiers: 0x0900)
        s.launchAtLogin = true
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(PomodoroSettings.self, from: data)
        #expect(decoded == s)
        #expect(decoded.shortcutBindings["toggle"]?.keyCode == 3)
        #expect(decoded.launchAtLogin == true)
    }

    @Test func alarmAndAmbienceEnumsCoverRawValues() {
        #expect(AlarmSoundService.Sound(rawValue: "glass") == .glass)
        #expect(BreakAmbienceService.Ambience(rawValue: "rain") == .rain)
    }

    @Test func timeFormatStrings() {
        #expect(TimeDisplayFormat.minutesSeconds.string(1500) == "25:00")
        #expect(TimeDisplayFormat.hoursMinutesSeconds.string(1500) == "0:25:00")
        #expect(TimeDisplayFormat.compact.string(1500) == "25:00")
        #expect(TimeDisplayFormat.compact.string(3661) == "1:01:01")
    }
}
