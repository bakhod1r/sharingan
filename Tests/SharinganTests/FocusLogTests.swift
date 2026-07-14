import Testing
import Foundation
@testable import SharinganCore

@Suite("Focus log model")
struct FocusLogModelTests {
    private let day = Calendar.current.startOfDay(for: Date())

    @Test func reportRowsGroupSubrowsUnderTheirTask() {
        let t1 = UUID(), t2 = UUID(), sub = UUID()
        let entries = [
            FocusLogEntry(day: day, taskID: t1, subtaskID: nil, title: "A", count: 1, seconds: 600),
            FocusLogEntry(day: day, taskID: t2, subtaskID: nil, title: "B", count: 3, seconds: 4500),
            FocusLogEntry(day: day, taskID: t2, subtaskID: sub, title: "B.1", count: 1, seconds: 1500),
        ]
        let tasks = [TaskItem(title: "B live", category: "Work")].map { t -> TaskItem in
            var t = t; t.id = t2; t.isDone = true; return t
        }
        let rows = FocusReport.rows(entries: entries, tasks: tasks)
        #expect(rows.count == 2)
        // Sorted by seconds desc: B first.
        #expect(rows[0].entry.taskID == t2)
        #expect(rows[0].subrows.map(\.title) == ["B.1"])
        #expect(rows[0].isDone)
        #expect(!rows[0].isDeleted)
        #expect(rows[0].category == "Work")
        // A has no live task: deleted, keeps snapshot title.
        #expect(rows[1].isDeleted)
        #expect(rows[1].entry.title == "A")
        #expect(rows[1].category == nil)
    }

    @Test func durationLabelFormatsMinutesAndHours() {
        #expect(FocusReport.durationLabel(0) == "0m")
        #expect(FocusReport.durationLabel(90) == "2m")      // rounds
        #expect(FocusReport.durationLabel(59 * 60) == "59m")
        #expect(FocusReport.durationLabel(75 * 60) == "1h 15m")
        #expect(FocusReport.durationLabel(120 * 60) == "2h")
    }
}
