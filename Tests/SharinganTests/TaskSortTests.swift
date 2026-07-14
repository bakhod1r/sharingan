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
