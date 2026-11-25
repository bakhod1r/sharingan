import Foundation
import Testing
@testable import SharinganCore

/// One board rule for both week boards: scheduled day = plannedDate ?? dueDate.
@MainActor
@Suite("Scheduled day (week boards)")
struct ScheduledDayTests {
    private let cal = Calendar.current
    private var day1: Date { cal.startOfDay(for: Date()) }
    private var day2: Date { cal.date(byAdding: .day, value: 1, to: day1)! }

    private func store(_ tasks: [TaskItem]) throws -> TaskStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("scheduled-day-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let s = TaskStore(fileURL: dir.appendingPathComponent("blink.sqlite"))
        s.insertAll(tasks)
        return s
    }

    @Test func dueDateIsFallbackBoardDay() throws {
        let t = TaskItem(title: "a", dueDate: day1)
        let s = try store([t])
        #expect(s.tasksScheduled(on: day1).map(\.id) == [t.id])
        #expect(s.tasksScheduled(on: day2).isEmpty)
    }

    @Test func plannedDateWinsOverDueDate() throws {
        let t = TaskItem(title: "a", dueDate: day1, plannedDate: day2)
        let s = try store([t])
        #expect(s.tasksScheduled(on: day1).isEmpty)
        #expect(s.tasksScheduled(on: day2).map(\.id) == [t.id])
    }

    @Test func scheduledExcludesDoneAndTrashed() throws {
        let done = TaskItem(title: "d", isDone: true, plannedDate: day1)
        var trashed = TaskItem(title: "t", plannedDate: day1)
        trashed.trashedAt = Date()
        let s = try store([done, trashed])
        #expect(s.tasksScheduled(on: day1).isEmpty)
    }

    @Test func backlogIsUndatedOpenOnly() throws {
        let free = TaskItem(title: "free")
        let planned = TaskItem(title: "p", plannedDate: day1)
        let due = TaskItem(title: "d", dueDate: day1)
        let done = TaskItem(title: "x", isDone: true)
        var trashed = TaskItem(title: "t")
        trashed.trashedAt = Date()
        let s = try store([free, planned, due, done, trashed])
        #expect(s.boardBacklogTasks.map(\.id) == [free.id])
    }

    @Test func scheduleKeepsDueDate() throws {
        let due = cal.date(byAdding: .day, value: 3, to: day1)!
        let t = TaskItem(title: "a", dueDate: due)
        let s = try store([t])
        s.schedule(t.id, on: day2)
        let got = try #require(s.tasks.first)
        #expect(got.plannedDate == day2)
        #expect(got.dueDate == due)
        #expect(s.tasksScheduled(on: day2).count == 1)
    }

    @Test func unscheduleClearsPlannedOnly() throws {
        let due = cal.date(byAdding: .day, value: 3, to: day1)!
        let t = TaskItem(title: "a", dueDate: due, plannedDate: day1)
        let s = try store([t])
        s.unschedule(t.id)
        let got = try #require(s.tasks.first)
        #expect(got.plannedDate == nil)
        #expect(got.dueDate == due)
    }

    @Test func unscheduleClearsDueWhenOnlyPlacement() throws {
        let t = TaskItem(title: "a", dueDate: day1)
        let s = try store([t])
        s.unschedule(t.id)
        let got = try #require(s.tasks.first)
        #expect(got.dueDate == nil)
        #expect(got.plannedDate == nil)
        #expect(s.boardBacklogTasks.map(\.id) == [t.id])
    }
}
