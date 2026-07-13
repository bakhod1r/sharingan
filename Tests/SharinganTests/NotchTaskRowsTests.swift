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

    // MARK: - Fallback tier (the actual bug)

    @Test("an undated open task with no queue and empty today-set still appears")
    func undatedFallbackTaskAppears() {
        // The bug: a task with no due date and not planned for today is invisible
        // to the `.today` filter, so `today` is empty — yet the user has open work.
        let a = task("write report")
        let rows = NotchTaskRows.rows(today: [], queue: [], fallback: [a])
        #expect(rows.map(\.title) == ["write report"])
    }

    @Test("today leads the fallback, and neither repeats a task")
    func todayAheadOfFallbackNoDupes() {
        let dated = task("due today"), undated = task("someday")
        // `fallback` is the whole open list, so it also contains today's task.
        let rows = NotchTaskRows.rows(today: [dated], queue: [],
                                      fallback: [dated, undated])
        #expect(rows.map(\.title) == ["due today", "someday"])
    }

    @Test("the fallback keeps the order it was handed")
    func fallbackOrderPreserved() {
        let a = task("a"), b = task("b"), c = task("c")
        let rows = NotchTaskRows.rows(today: [], queue: [], fallback: [c, a, b])
        #expect(rows.map(\.title) == ["c", "a", "b"])
    }

    // MARK: - Active tier

    @Test("the active task leads")
    func activeLeads() {
        let a = task("a"), b = task("b")
        let rows = NotchTaskRows.rows(today: [a, b], queue: [], active: b.id)
        #expect(rows.map(\.title) == ["b", "a"])
    }

    @Test("the active task leads even when it is also queued and on today — once")
    func activeLeadsWithoutDuplicating() {
        let a = task("a"), b = task("b"), c = task("c")
        let rows = NotchTaskRows.rows(today: [a, b, c], queue: [c.id, b.id],
                                      active: c.id, fallback: [a, b, c])
        // c: active (tier 1). b: queued (tier 2). a: today (tier 3). No repeats.
        #expect(rows.map(\.title) == ["c", "b", "a"])
    }

    @Test("an active id that resolves to nothing is skipped, not faulted on")
    func staleActiveIDIgnored() {
        let a = task("a")
        let rows = NotchTaskRows.rows(today: [a], queue: [], active: UUID())
        #expect(rows.map(\.title) == ["a"])
    }

    // MARK: - Full priority order across all four tiers

    @Test("active, then queue, then today, then fallback — deduped and capped")
    func fullPriorityOrder() {
        let act = task("active")
        let q1 = task("q1"), q2 = task("q2")
        let td = task("today")
        let f1 = task("f1"), f2 = task("f2")
        // fallback is the open list, so it carries everything that is open.
        let open = [act, q1, q2, td, f1, f2]
        let rows = NotchTaskRows.rows(today: [td], queue: [q1.id, q2.id],
                                      active: act.id, fallback: open, limit: 5)
        #expect(rows.map(\.title) == ["active", "q1", "q2", "today", "f1"])
    }

    @Test("the cap bounds the merged four-tier list")
    func capBoundsMergedList() {
        let open = (1...10).map { task("t\($0)") }
        let rows = NotchTaskRows.rows(today: [open[0]], queue: [open[1].id],
                                      active: open[2].id, fallback: open, limit: 4)
        #expect(rows.count == 4)
        // active t3, queued t2, today t1, then fallback resumes at t4.
        #expect(rows.map(\.title) == ["t3", "t2", "t1", "t4"])
    }

    @Test("no open tasks at all yields an empty result — the empty state")
    func genuinelyEmptyYieldsEmpty() {
        let rows = NotchTaskRows.rows(today: [], queue: [UUID()],
                                      active: UUID(), fallback: [])
        #expect(rows.isEmpty)
    }
}
