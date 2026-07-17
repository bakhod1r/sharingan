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
        // A's task is deleted (not in the live list) — dropped entirely.
        #expect(rows.count == 1)
        #expect(rows[0].entry.taskID == t2)
        #expect(rows[0].subrows.map(\.title) == ["B.1"])
        #expect(rows[0].isDone)
        #expect(!rows[0].isDeleted)
        #expect(rows[0].category == "Work")
    }

    @Test func durationLabelFormatsMinutesAndHours() {
        #expect(FocusReport.durationLabel(0) == "0m")
        #expect(FocusReport.durationLabel(90) == "2m")      // rounds
        #expect(FocusReport.durationLabel(59 * 60) == "59m")
        #expect(FocusReport.durationLabel(75 * 60) == "1h 15m")
        #expect(FocusReport.durationLabel(120 * 60) == "2h")
    }
}

@Suite("Focus log persistence")
struct FocusLogPersistenceTests {
    @Test func roundTripsThroughSQLite() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("focuslog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("t.sqlite").path
        let day = Calendar.current.startOfDay(for: Date())
        let task = UUID(), sub = UUID()
        let entries = [
            FocusLogEntry(day: day, taskID: task, subtaskID: nil,  title: "T",  count: 2, seconds: 3000),
            FocusLogEntry(day: day, taskID: task, subtaskID: sub, title: "T.s", count: 1, seconds: 1500),
        ]
        do {
            let db = try #require(TaskDatabase(path: path))
            db.saveFocusLog(entries)
        }
        let db2 = try #require(TaskDatabase(path: path))
        let loaded = db2.loadFocusLog()
        #expect(Set(loaded) == Set(entries))
    }
}

@Suite("Focus log crediting")
struct FocusLogCreditingTests {
    @MainActor private func freshStore() throws -> TaskStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("focuscredit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return TaskStore(fileURL: dir.appendingPathComponent("t.sqlite"))
    }

    @MainActor @Test func sameDayCreditsMergeIntoOneRow() throws {
        let store = try freshStore()
        store.add(title: "Write report")
        let id = store.tasks[0].id
        store.incrementPomodoro(id, seconds: 1500)
        store.incrementPomodoro(id, seconds: 1500)
        let rows = store.focusEntries(on: Date())
        #expect(rows.count == 1)
        #expect(rows[0].count == 2)
        #expect(rows[0].seconds == 3000)
        #expect(rows[0].title == "Write report")
        #expect(store.tasks[0].pomodorosDone == 2)
    }

    @MainActor @Test func activeSubtaskGetsItsOwnRowTaskRowStaysAggregate() throws {
        let store = try freshStore()
        store.add(title: "Parent")
        let id = store.tasks[0].id
        store.addSubtask(id, title: "Child")
        let sid = store.tasks[0].subtasks[0].id
        store.setActive(id)
        store.activeSubtaskID = sid
        store.incrementPomodoro(id, seconds: 1500)
        let rows = store.focusEntries(on: Date())
        #expect(rows.count == 2)
        let taskRow = rows.first { $0.subtaskID == nil }
        let subRow = rows.first { $0.subtaskID == sid }
        #expect(taskRow?.count == 1 && taskRow?.seconds == 1500)
        #expect(subRow?.count == 1 && subRow?.seconds == 1500)
        #expect(subRow?.title == "Child")
        // Totals must count task-level rows only — no double counting.
        let totals = store.focusDayTotals(on: Date())
        #expect(totals.count == 1)
        #expect(totals.seconds == 1500)
    }

    @MainActor @Test func differentDaysGetDifferentRowsAndHistoryIsNewestFirst() throws {
        let store = try freshStore()
        store.add(title: "T")
        let id = store.tasks[0].id
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        store.incrementPomodoro(id, seconds: 1500, on: yesterday)
        store.incrementPomodoro(id, seconds: 900, on: today)
        #expect(store.focusEntries(on: yesterday).count == 1)
        #expect(store.focusEntries(on: today).count == 1)
        let history = store.focusHistory(for: id, days: 14)
        #expect(history.count == 2)
        #expect(history[0].seconds == 900)   // today first
        #expect(history[1].seconds == 1500)
    }

    @MainActor @Test func deletingTheTaskKeepsItsHistory() throws {
        let store = try freshStore()
        store.add(title: "Doomed")
        let id = store.tasks[0].id
        store.incrementPomodoro(id, seconds: 1500)
        store.delete(id)
        #expect(store.focusEntries(on: Date()).count == 1)
        #expect(store.focusEntries(on: Date())[0].title == "Doomed")
    }

    @MainActor @Test func logSurvivesStoreReload() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("focusreload-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("t.sqlite")
        var id: UUID?
        do {
            let store = TaskStore(fileURL: url)
            store.add(title: "Persist me")
            id = store.tasks[0].id
            store.incrementPomodoro(id!, seconds: 1500)
        }
        let store2 = TaskStore(fileURL: url)
        let rows = store2.focusEntries(on: Date())
        #expect(rows.count == 1)
        #expect(rows[0].taskID == id)
        #expect(rows[0].seconds == 1500)
    }

    @MainActor @Test func staleSubtaskCreditsOnlyTheTask() throws {
        let store = try freshStore()
        store.add(title: "Parent")
        let id = store.tasks[0].id
        store.addSubtask(id, title: "Gone")
        let sid = store.tasks[0].subtasks[0].id
        store.setActive(id)
        var edited = store.tasks[0]
        edited.subtasks.removeAll()          // subtask deleted mid-session
        store.update(edited)
        store.activeSubtaskID = sid          // simulate the stale pointer
        store.incrementPomodoro(id, seconds: 1500)
        let rows = store.focusEntries(on: Date())
        #expect(rows.count == 1)             // task row only, no subtask row
        #expect(rows[0].subtaskID == nil)
        #expect(store.activeSubtaskID == nil)
    }

    @MainActor @Test func renameRefreshesSnapshotTitleOnNextCredit() throws {
        let store = try freshStore()
        store.add(title: "Old name")
        let id = store.tasks[0].id
        store.incrementPomodoro(id, seconds: 900)
        var renamed = store.tasks[0]
        renamed.title = "New name"
        store.update(renamed)
        store.incrementPomodoro(id, seconds: 900)
        let rows = store.focusEntries(on: Date())
        #expect(rows.count == 1)
        #expect(rows[0].title == "New name")
    }

    @MainActor @Test func legacyWrapperStillCreditsCounters() throws {
        let store = try freshStore()
        store.add(title: "Old path")
        let id = store.tasks[0].id
        store.incrementPomodoro(id)
        #expect(store.tasks[0].pomodorosDone == 1)
        #expect(store.focusEntries(on: Date())[0].seconds == 0)
    }
}

@Suite("Focus completion payload")
struct FocusCompletionPayloadTests {
    @MainActor @Test func phaseDidCompleteCarriesSessionSeconds() async throws {
        let t = PomodoroTimer()
        t.settings = PomodoroSettings()
        t.stop()
        t.start()
        t.removeTime(t.totalSeconds - 1)     // ≈1s left in the focus session
        let expected = t.totalSeconds
        await confirmation(expectedCount: 1) { done in
            let obs = NotificationCenter.default.addObserver(
                forName: .phaseDidComplete, object: t, queue: .main) { note in
                if let s = note.userInfo?["seconds"] as? TimeInterval, s == expected {
                    done()
                }
            }
            try? await Task.sleep(for: .seconds(3))
            NotificationCenter.default.removeObserver(obs)
        }
        t.stop()
    }
}
