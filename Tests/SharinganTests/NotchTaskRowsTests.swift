import Testing
import Foundation
@testable import SharinganCore

@Suite("Notch task rows")
struct NotchTaskRowsTests {

    private func task(_ title: String) -> TaskItem { TaskItem(title: title) }

    @Test("queued tasks come first, in queue order")
    func queueFirst() {
        let a = task("a"), b = task("b"), c = task("c")
        let rows = NotchTaskRows.rows(today: [a, b, c], queue: [c.id, a.id])
        #expect(rows.map(\.title) == ["c", "a", "b"])
    }

    @Test("today's tasks keep their own order behind the queue")
    func todayOrderPreserved() {
        let a = task("a"), b = task("b")
        let rows = NotchTaskRows.rows(today: [a, b], queue: [])
        #expect(rows.map(\.title) == ["a", "b"])
    }

    @Test("a queued id that isn't in today's list is dropped, not crashed on")
    func staleQueueIDsIgnored() {
        let a = task("a")
        let rows = NotchTaskRows.rows(today: [a], queue: [UUID(), a.id])
        #expect(rows.map(\.title) == ["a"])
    }

    @Test("no task appears twice")
    func noDuplicates() {
        let a = task("a"), b = task("b")
        let rows = NotchTaskRows.rows(today: [a, b], queue: [a.id, a.id])
        #expect(rows.count == 2)
    }

    @Test("the list is capped at the limit")
    func capped() {
        let all = (1...12).map { task("t\($0)") }
        #expect(NotchTaskRows.rows(today: all, queue: []).count == 5)
        #expect(NotchTaskRows.rows(today: all, queue: [], limit: 3).count == 3)
    }

    @Test("an empty day yields no rows")
    func emptyDay() {
        #expect(NotchTaskRows.rows(today: [], queue: [UUID()]).isEmpty)
    }

    @Test("the cap counts queued and unqueued rows together")
    func capSpansBothSources() {
        let all = (1...8).map { task("t\($0)") }
        let rows = NotchTaskRows.rows(today: all, queue: [all[7].id, all[6].id], limit: 4)
        #expect(rows.map(\.title) == ["t8", "t7", "t1", "t2"])
    }
}
