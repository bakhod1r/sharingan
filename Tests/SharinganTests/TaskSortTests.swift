import Testing
import Foundation
@testable import SharinganCore

/// The view-bar sort menu: every mode reorders rows inside a category group,
/// keeps open tasks above done ones, and breaks ties with the manual order.
@MainActor
@Suite("Task sorting")
struct TaskSortTests {
    private func tempStore() -> TaskStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("blink-sort-\(UUID().uuidString).sqlite")
        return TaskStore(fileURL: url)
    }

    /// One category, all-open titles in the given mode's order.
    private func titles(_ s: TaskStore, _ sort: TaskSortMode,
                        filter: TaskFilter = .all) -> [String] {
        s.grouped(filter: filter, sort: sort).flatMap { $0.items.map(\.title) }
    }

    @Test func manualIsTheDefaultInsertionOrder() {
        let s = tempStore()
        s.add(title: "First"); s.add(title: "Second"); s.add(title: "Third")
        #expect(titles(s, .manual) == ["First", "Second", "Third"])
    }

    @Test func prioritySortsMostUrgentFirst() {
        let s = tempStore()
        s.add(title: "None")                            // P4
        s.add(title: "Low", priority: .low)             // P3
        s.add(title: "Urgent", priority: .high)         // P1
        s.add(title: "Medium", priority: .medium)       // P2
        s.add(title: "Custom", priority: .init(rawValue: 5))  // above P1
        #expect(titles(s, .priority) == ["Custom", "Urgent", "Medium", "Low", "None"])
    }

    @Test func dueDateSortsEarliestFirstDatelessLast() {
        let s = tempStore()
        let now = Date()
        s.add(title: "Someday")
        s.add(title: "Next week", dueDate: now.addingTimeInterval(7 * 86400))
        s.add(title: "Tomorrow", dueDate: now.addingTimeInterval(86400))
        #expect(titles(s, .dueDate) == ["Tomorrow", "Next week", "Someday"])
    }

    @Test func titleSortsCaseInsensitively() {
        let s = tempStore()
        s.add(title: "banana"); s.add(title: "Cherry"); s.add(title: "apple")
        #expect(titles(s, .title) == ["apple", "banana", "Cherry"])
    }

    @Test func newestSortsRecentCreationFirst() {
        let s = tempStore()
        s.add(title: "Old"); s.add(title: "New")
        var old = s.tasks.first { $0.title == "Old" }!
        old.createdAt = Date().addingTimeInterval(-3600)
        s.update(old)
        #expect(titles(s, .newest) == ["New", "Old"])
    }

    @Test func everyModeKeepsOpenTasksAboveDone() {
        let s = tempStore()
        s.add(title: "AAA done", dueDate: Date().addingTimeInterval(60),
              priority: .high)
        s.add(title: "ZZZ open")
        s.toggleDone(s.tasks.first { $0.title == "AAA done" }!.id)
        let done = s.tasks.first { $0.title == "AAA done" }!
        let open = s.tasks.first { $0.title == "ZZZ open" }!
        // The done task wins on every sort key (flag, date, title, age) but
        // must still sink below the open one in every mode.
        for mode in TaskSortMode.allCases {
            #expect(mode.inOrder(open, done))
            #expect(!mode.inOrder(done, open))
        }
    }

    @Test func equalKeysFallBackToManualOrder() {
        let s = tempStore()
        s.add(title: "A", priority: .high)
        s.add(title: "B", priority: .high)
        s.add(title: "C", priority: .high)
        #expect(titles(s, .priority) == ["A", "B", "C"])
    }
}

/// Step ordering for the expanded panels and the picker's step rows.
@Suite("Subtask sorting & filtering")
struct SubtaskSortTests {
    private func steps() -> [Subtask] {
        [Subtask(title: "banana", estimatedPomodoros: 2, priority: .low),
         Subtask(title: "apple", isDone: true, priority: .high),
         Subtask(title: "Cherry", estimatedPomodoros: 5),
         Subtask(title: "date", priority: .high)]
    }

    @Test func manualKeepsArrayOrder() {
        #expect(SubtaskSortMode.manual.apply(steps()).map(\.title)
                == ["banana", "apple", "Cherry", "date"])
    }

    @Test func prioritySinksDoneAndRanksUrgentFirst() {
        // "apple" is P1 but done — it still lands last.
        #expect(SubtaskSortMode.priority.apply(steps()).map(\.title)
                == ["date", "banana", "Cherry", "apple"])
    }

    @Test func titleSortsCaseInsensitivelyDoneLast() {
        #expect(SubtaskSortMode.title.apply(steps()).map(\.title)
                == ["banana", "Cherry", "date", "apple"])
    }

    @Test func estimateSortsBiggestFirstUnestimatedLast() {
        #expect(SubtaskSortMode.estimate.apply(steps()).map(\.title)
                == ["Cherry", "banana", "date", "apple"])
    }

    @Test func equalKeysKeepManualOrder() {
        let same = [Subtask(title: "a", priority: .high),
                    Subtask(title: "b", priority: .high),
                    Subtask(title: "c", priority: .high)]
        #expect(SubtaskSortMode.priority.apply(same).map(\.title) == ["a", "b", "c"])
    }

    @Test func statusAndPriorityNarrowing() {
        let s = steps()
        #expect(s.narrowed(status: .open, priority: nil).map(\.title)
                == ["banana", "Cherry", "date"])
        #expect(s.narrowed(status: .done, priority: nil).map(\.title) == ["apple"])
        #expect(s.narrowed(status: .all, priority: .high).map(\.title)
                == ["apple", "date"])
        #expect(s.narrowed(status: .open, priority: .high).map(\.title) == ["date"])
    }
}

/// Report row ordering — time stays the canonical order; other keys re-rank
/// with the time order as tiebreak.
@Suite("Report sorting")
struct ReportSortTests {
    private func row(_ title: String, count: Int, seconds: TimeInterval) -> FocusReportRow {
        FocusReportRow(entry: FocusLogEntry(day: Calendar.current.startOfDay(for: Date()),
                                            taskID: UUID(), subtaskID: nil, title: title,
                                            count: count, seconds: seconds),
                       subrows: [], isDone: false, isDeleted: false, category: nil)
    }

    @Test func timeKeepsGivenOrder() {
        let rows = [row("b", count: 1, seconds: 900), row("a", count: 4, seconds: 300)]
        #expect(ReportSortMode.time.apply(rows).map(\.entry.title) == ["b", "a"])
    }

    @Test func pomodorosRanksByCount() {
        let rows = [row("b", count: 1, seconds: 900), row("a", count: 4, seconds: 300),
                    row("c", count: 4, seconds: 100)]
        // a and c tie on count — time order (a before c) breaks it.
        #expect(ReportSortMode.pomodoros.apply(rows).map(\.entry.title) == ["a", "c", "b"])
    }

    @Test func titleSortsCaseInsensitively() {
        let rows = [row("beta", count: 1, seconds: 900), row("Alpha", count: 2, seconds: 300)]
        #expect(ReportSortMode.title.apply(rows).map(\.entry.title) == ["Alpha", "beta"])
    }
}
