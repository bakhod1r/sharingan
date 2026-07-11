import Foundation
import Testing
@testable import BlinkCore

@MainActor
@Suite("Task snooze & overdue")
struct TaskSnoozeTests {
    private func tempStore() -> TaskStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("blink-snooze-\(UUID().uuidString).sqlite")
        return TaskStore(fileURL: url)
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int,
                      _ h: Int = 0, _ mi: Int = 0) -> Date {
        Calendar.current.date(
            from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    @Test func snoozeKeepsTimeOfDay() throws {
        let s = tempStore()
        s.add(title: "Report", dueDate: date(2026, 7, 10, 15, 30))
        let id = s.tasks[0].id

        // Target passed mid-morning — only its day should matter.
        s.snooze(id, to: date(2026, 7, 13, 8, 11))

        let due = try #require(s.tasks.first { $0.id == id }?.dueDate)
        #expect(due == date(2026, 7, 13, 15, 30))
    }

    @Test func snoozeWithoutDueDateDefaultsToNine() throws {
        let s = tempStore()
        s.add(title: "Someday")
        let id = s.tasks[0].id

        s.snooze(id, to: date(2026, 7, 20, 22, 45))

        let due = try #require(s.tasks.first { $0.id == id }?.dueDate)
        #expect(due == date(2026, 7, 20, 9, 0))
    }

    @Test func snoozeMovesPlannedDateWhenSet() throws {
        let s = tempStore()
        s.add(title: "Planned", dueDate: date(2026, 7, 10, 15, 30))
        let id = s.tasks[0].id
        s.setPlannedDate(id, date(2026, 7, 10))

        s.snooze(id, to: date(2026, 7, 13, 8, 11))

        let task = try #require(s.tasks.first { $0.id == id })
        #expect(task.plannedDate == Calendar.current.startOfDay(for: date(2026, 7, 13)))
    }

    @Test func snoozeLeavesNilPlannedDateAlone() throws {
        let s = tempStore()
        s.add(title: "Unplanned", dueDate: date(2026, 7, 10, 15, 30))
        let id = s.tasks[0].id

        s.snooze(id, to: date(2026, 7, 13))

        let task = try #require(s.tasks.first { $0.id == id })
        #expect(task.plannedDate == nil)
    }

    @Test func snoozeTomorrowLandsOnNextDay() throws {
        let s = tempStore()
        s.add(title: "Tomorrow", dueDate: date(2026, 7, 10, 15, 30))
        let id = s.tasks[0].id

        s.snoozeTomorrow(id, now: date(2026, 7, 10, 12, 0))

        let due = try #require(s.tasks.first { $0.id == id }?.dueDate)
        #expect(due == date(2026, 7, 11, 15, 30))
    }

    @Test func snoozeNextWeekLandsSevenDaysOut() throws {
        let s = tempStore()
        s.add(title: "Next week", dueDate: date(2026, 7, 10, 15, 30))
        let id = s.tasks[0].id

        s.snoozeNextWeek(id, now: date(2026, 7, 10, 12, 0))

        let due = try #require(s.tasks.first { $0.id == id }?.dueDate)
        #expect(due == date(2026, 7, 17, 15, 30))
    }

    @Test func snoozeOnDoneTaskIsNoOp() throws {
        let s = tempStore()
        s.add(title: "Done deal", dueDate: date(2026, 7, 10, 15, 30))
        let id = s.tasks[0].id
        s.toggleDone(id)

        s.snooze(id, to: date(2026, 7, 13))

        let task = try #require(s.tasks.first { $0.id == id })
        #expect(task.dueDate == date(2026, 7, 10, 15, 30))
        #expect(task.isDone)
    }

    @Test func snoozeUnknownIDIsNoOp() {
        let s = tempStore()
        s.add(title: "Bystander", dueDate: date(2026, 7, 10, 15, 30))

        s.snooze(UUID(), to: date(2026, 7, 13))

        #expect(s.tasks[0].dueDate == date(2026, 7, 10, 15, 30))
    }

    @Test func overdueCountCountsOnlyOpenPastDueTasks() {
        let s = tempStore()
        let now = date(2026, 7, 12, 12, 0)
        s.add(title: "Overdue A", dueDate: date(2026, 7, 10, 15, 30))
        s.add(title: "Overdue B", dueDate: date(2026, 7, 12, 9, 0))
        s.add(title: "Future", dueDate: date(2026, 7, 14, 9, 0))
        s.add(title: "No deadline")
        s.add(title: "Done & past", dueDate: date(2026, 7, 9, 9, 0))
        s.toggleDone(s.tasks.first { $0.title == "Done & past" }!.id)

        #expect(s.overdueCount(now: now) == 2)
    }

    @Test func overdueCountZeroWhenNothingIsLate() {
        let s = tempStore()
        s.add(title: "Future", dueDate: date(2026, 7, 14, 9, 0))
        s.add(title: "No deadline")

        #expect(s.overdueCount(now: date(2026, 7, 12)) == 0)
    }
}
