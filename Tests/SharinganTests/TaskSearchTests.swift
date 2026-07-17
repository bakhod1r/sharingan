import XCTest
@testable import SharinganCore

final class TaskSearchTests: XCTestCase {
    private func task(_ title: String = "Redesign the notch panel") -> TaskItem {
        TaskItem(title: title,
                 category: "Work",
                 tags: ["ui", "polish"],
                 notes: "Ship before the demo",
                 subtasks: [Subtask(title: "Measure the ears")],
                 recurrence: .weekly,
                 project: "Sharingan",
                 priority: .high,
                 pomodoroKind: .big,
                 number: 42)
    }

    func testMatchesCode() {
        let t = task()
        XCTAssertTrue(t.matchesSearch("T-42"))
        XCTAssertTrue(t.matchesSearch("t-42"))
        XCTAssertTrue(t.matchesSearch("42"))
        XCTAssertFalse(t.matchesSearch("T-43"))
    }

    func testMatchesEveryTextField() {
        let t = task()
        for q in ["redesign", "work", "polish", "sharingan", "demo", "ears"] {
            XCTAssertTrue(t.matchesSearch(q), "expected a hit for \(q)")
        }
    }

    func testMatchesChipsUserCanSee() {
        let t = task()
        XCTAssertTrue(t.matchesSearch("p1"))
        XCTAssertTrue(t.matchesSearch("urgent"))
        XCTAssertTrue(t.matchesSearch("weekly"))
        XCTAssertTrue(t.matchesSearch("big"))
        XCTAssertTrue(t.matchesSearch("open"))
    }

    func testUnflaggedTaskDoesNotMatchPriorityWords() {
        let plain = TaskItem(title: "Plain", number: 7)
        XCTAssertFalse(plain.matchesSearch("p1"))
        XCTAssertFalse(plain.matchesSearch("weekly"))
    }

    func testMatchesDueDate() {
        var t = task()
        t.dueDate = Date()
        XCTAssertTrue(t.matchesSearch("today"))
        XCTAssertTrue(t.matchesSearch("due"))

        var dated = task()
        dated.dueDate = DateComponents(calendar: .current, year: 2026, month: 3, day: 9).date!
        XCTAssertTrue(dated.matchesSearch("2026-03-09"))
        XCTAssertTrue(dated.matchesSearch("mar"))
        XCTAssertTrue(dated.matchesSearch("monday"))
    }

    func testOverdueAndDoneWords() {
        var overdue = task()
        overdue.dueDate = Date().addingTimeInterval(-86_400 * 2)
        XCTAssertTrue(overdue.matchesSearch("overdue"))

        var done = task()
        done.isDone = true
        XCTAssertTrue(done.matchesSearch("done"))
        XCTAssertFalse(done.matchesSearch("overdue"))
    }

    func testAllWordsMustMatchInAnyOrder() {
        let t = task()
        XCTAssertTrue(t.matchesSearch("urgent notch"))
        XCTAssertTrue(t.matchesSearch("notch urgent"))
        XCTAssertFalse(t.matchesSearch("urgent kitchen"))
    }

    func testEmptyQueryMatchesEverything() {
        XCTAssertTrue(task().matchesSearch(""))
        XCTAssertTrue(task().matchesSearch("   "))
    }
}
