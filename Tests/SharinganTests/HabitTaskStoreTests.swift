import Testing
import Foundation
@testable import SharinganCore

// Swift Testing (not XCTest) on purpose: TaskStore.add touches
// NotificationService, which crashes inside an XCTest host bundle.
@MainActor
@Suite("Habit task store")
struct HabitTaskStoreTests {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; c.firstWeekday = 2; return c
    }
    private func store(_ url: URL? = nil) -> TaskStore {
        TaskStore(fileURL: url ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("habit-\(UUID().uuidString).sqlite"))
    }
    private func day(_ d: Int) -> Date { cal.date(from: DateComponents(year: 2024, month: 1, day: d))! }

    @Test func setHabitAndHabitTasks() {
        let s = store()
        s.add(title: "Run"); s.add(title: "Other")
        let id = s.tasks.first { $0.title == "Run" }!.id
        #expect(s.habitTasks.isEmpty)
        s.setHabit(TaskHabit(schedule: .daily, mode: .manual, startDay: day(1)), for: id)
        #expect(s.habitTasks.map(\.title) == ["Run"])
        s.setHabit(nil, for: id)
        #expect(s.habitTasks.isEmpty)
    }

    @Test func toggleCheckPersistsForAnyModeButNeedsHabit() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("habit-\(UUID().uuidString).sqlite")
        let s = store(url)
        s.add(title: "Read"); s.add(title: "Focus")
        let manual = s.tasks.first { $0.title == "Read" }!.id
        let pomo = s.tasks.first { $0.title == "Focus" }!.id
        s.setHabit(TaskHabit(schedule: .daily, mode: .manual, startDay: day(1)), for: manual)
        s.setHabit(TaskHabit(schedule: .daily, mode: .pomodoro(target: 2), startDay: day(1)), for: pomo)
        s.toggleHabitCheck(taskID: manual, day: day(5), calendar: cal)
        s.toggleHabitCheck(taskID: pomo, day: day(5), calendar: cal)
        #expect(Set(s.habitChecks) == [HabitCheck(day: day(5), taskID: manual), HabitCheck(day: day(5), taskID: pomo)])
        #expect(store(url).habitChecks.count == 2)
        #expect(store(url).tasks.first { $0.id == manual }?.habit != nil)
        s.toggleHabitCheck(taskID: manual, day: day(5), calendar: cal)
        s.toggleHabitCheck(taskID: pomo, day: day(5), calendar: cal)
        #expect(s.habitChecks.isEmpty)
        s.add(title: "Plain")
        let plain = s.tasks.first { $0.title == "Plain" }!.id
        s.toggleHabitCheck(taskID: plain, day: day(5), calendar: cal)
        #expect(s.habitChecks.isEmpty)
    }

    @Test func reportAndPendingCountUseStoreData() {
        let s = store()
        s.add(title: "Read")
        let id = s.tasks[0].id
        s.setHabit(TaskHabit(schedule: .daily, mode: .manual, startDay: day(1)), for: id)
        for d in [8, 9] { s.toggleHabitCheck(taskID: id, day: day(d), calendar: cal) }
        #expect(s.pendingHabitCount(today: day(10), calendar: cal) == 1)
        s.toggleHabitCheck(taskID: id, day: day(10), calendar: cal)
        let r = s.habitReport(days: 7, today: day(10), calendar: cal)
        #expect(r.bestCurrentStreak == 3)
        #expect(r.rows.first?.title == "Read")
        #expect(s.pendingHabitCount(today: day(10), calendar: cal) == 0)
    }

    @Test func recurringCompletionDoesNotCloneHabit() {
        let s = store()
        s.add(title: "Water")
        let id = s.tasks[0].id
        s.setHabit(TaskHabit(schedule: .daily, mode: .manual, startDay: day(1)), for: id)
        #expect(s.tasks.filter { $0.habit != nil }.count == 1)
    }
}
