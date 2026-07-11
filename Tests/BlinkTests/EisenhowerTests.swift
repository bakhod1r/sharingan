import Foundation
import Testing
@testable import BlinkCore

@Suite("Eisenhower classification")
struct EisenhowerTests {
    /// Fixed reference point so "within 48h" boundaries are deterministic.
    private let now = Calendar.current.date(
        from: DateComponents(year: 2026, month: 7, day: 12, hour: 12))!

    private func task(due: Date? = nil,
                      plannedToday: Bool = false,
                      priority: TaskPriority = .none,
                      isDone: Bool = false) -> TaskItem {
        TaskItem(title: "t",
                 isDone: isDone,
                 dueDate: due,
                 plannedDate: plannedToday ? Calendar.current.startOfDay(for: now) : nil,
                 priority: priority)
    }

    @Test func overdueHighPriorityIsDoFirst() {
        let t = task(due: now.addingTimeInterval(-3600), priority: .high)
        #expect(EisenhowerQuadrant.classify(t, now: now) == .doFirst)
    }

    @Test func dueTomorrowLowPriorityIsDelegate() {
        // P3 (.low) is not "important", but due within 48h is urgent.
        let t = task(due: now.addingTimeInterval(24 * 3600), priority: .low)
        #expect(EisenhowerQuadrant.classify(t, now: now) == .delegate)
    }

    @Test func noDueMediumPriorityIsSchedule() {
        let t = task(priority: .medium)
        #expect(EisenhowerQuadrant.classify(t, now: now) == .schedule)
    }

    @Test func noDueNoPriorityIsEliminate() {
        let t = task()
        #expect(EisenhowerQuadrant.classify(t, now: now) == .eliminate)
    }

    @Test func plannedTodayCountsAsUrgent() {
        // No due date at all — today's plan alone makes it urgent.
        #expect(EisenhowerQuadrant.classify(
            task(plannedToday: true, priority: .high), now: now) == .doFirst)
        #expect(EisenhowerQuadrant.classify(
            task(plannedToday: true), now: now) == .delegate)
    }

    @Test func dueInThreeDaysIsNotUrgent() {
        let due = now.addingTimeInterval(3 * 24 * 3600)
        #expect(EisenhowerQuadrant.classify(
            task(due: due, priority: .high), now: now) == .schedule)
        #expect(EisenhowerQuadrant.classify(
            task(due: due), now: now) == .eliminate)
    }

    @Test func classifyIsPureOverDoneState() {
        // Done tasks are the caller's job to filter out — classify itself maps
        // the same fields identically regardless of completion.
        let open = task(due: now.addingTimeInterval(-60), priority: .high)
        let done = task(due: now.addingTimeInterval(-60), priority: .high, isDone: true)
        #expect(EisenhowerQuadrant.classify(open, now: now)
                == EisenhowerQuadrant.classify(done, now: now))
    }

    @Test func everyQuadrantHasChrome() {
        for q in EisenhowerQuadrant.allCases {
            #expect(!q.label.isEmpty)
            #expect(!q.icon.isEmpty)
            #expect(q.tintHex.hasPrefix("#"))
        }
    }
}
