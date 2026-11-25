import Foundation
import SQLite3
import Testing
@testable import SharinganCore

@MainActor
@Suite("Review fixes: TaskStore / DB / CLI / FocusQueue")
struct ReviewTaskStoreTests {
    private func dbURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("review-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("blink.sqlite")
    }

    private func store() throws -> TaskStore { TaskStore(fileURL: try dbURL()) }

    // MARK: 1.2

    @Test func recurringCompletionKeepsOriginalSubtasksInDatabase() throws {
        let url = try dbURL()
        let s = TaskStore(fileURL: url)
        s.add(title: "daily", dueDate: Date().addingTimeInterval(3600), recurrence: .daily)
        let id = try #require(s.tasks.first?.id)
        s.addSubtask(id, title: "a")
        s.addSubtask(id, title: "b")
        s.toggleDone(id)
        #expect(s.tasks.count == 2)
        let orig = try #require(s.tasks.first { $0.id == id })
        let next = try #require(s.tasks.first { $0.id != id })
        #expect(Set(orig.subtasks.map(\.id)).isDisjoint(with: Set(next.subtasks.map(\.id))))

        let reloaded = try #require(TaskDatabase(path: url.path)).loadTasks()
        let rOrig = try #require(reloaded.first { $0.id == id })
        #expect(rOrig.subtasks.count == 2)
        let rNext = try #require(reloaded.first { $0.id != id })
        #expect(rNext.subtasks.count == 2)
    }

    // MARK: 2.3

    @Test func duplicateOfDoneColumnTaskDropsColumn() throws {
        let s = try store()
        let doneID = try #require(BoardColumnStore.shared.doneColumnID)
        s.add(title: "x")
        let id = try #require(s.tasks.first?.id)
        s.setBoardColumn(id, columnID: doneID, markDone: true)
        let copyID = try #require(s.duplicate(id))
        #expect(s.tasks.first { $0.id == copyID }?.boardColumnID == nil)
    }

    @Test func duplicateKeepsNonDoneColumn() throws {
        let s = try store()
        s.add(title: "x")
        let id = try #require(s.tasks.first?.id)
        s.setBoardColumn(id, columnID: "custom-col", markDone: false)
        let copyID = try #require(s.duplicate(id))
        #expect(s.tasks.first { $0.id == copyID }?.boardColumnID == "custom-col")
    }

    @Test func recurringSpawnDropsDoneColumn() throws {
        let s = try store()
        let doneID = try #require(BoardColumnStore.shared.doneColumnID)
        s.add(title: "r", recurrence: .daily)
        let id = try #require(s.tasks.first?.id)
        s.setBoardColumn(id, columnID: doneID, markDone: true)
        let next = try #require(s.tasks.first { $0.id != id })
        #expect(next.boardColumnID == nil)
        #expect(!next.isDone)
    }

    // MARK: 1.4

    @Test func snoozeWithoutDueDateStaysDateOnly() throws {
        let s = try store()
        s.add(title: "x")
        let id = try #require(s.tasks.first?.id)
        let day = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        s.snooze(id, to: day)
        let due = try #require(s.tasks.first?.dueDate)
        #expect(DueDate.isDateOnly(due))
        #expect(due == Calendar.current.startOfDay(for: day))
    }

    @Test func snoozeKeepsRealTime() throws {
        let s = try store()
        let cal = Calendar.current
        let due = cal.date(bySettingHour: 15, minute: 30, second: 0, of: Date())!
        s.add(title: "x", dueDate: due)
        let id = try #require(s.tasks.first?.id)
        let day = cal.date(byAdding: .day, value: 2, to: Date())!
        s.snooze(id, to: day)
        let got = try #require(s.tasks.first?.dueDate)
        let c = cal.dateComponents([.hour, .minute], from: got)
        #expect(c.hour == 15 && c.minute == 30)
    }

    @Test func snoozeDateOnlyStaysDateOnly() throws {
        let s = try store()
        let cal = Calendar.current
        s.add(title: "x", dueDate: cal.startOfDay(for: Date()))
        let id = try #require(s.tasks.first?.id)
        s.snooze(id, to: cal.date(byAdding: .day, value: 1, to: Date())!)
        #expect(DueDate.isDateOnly(try #require(s.tasks.first?.dueDate)))
    }

    // MARK: 2.1

    @Test func trashedTasksExcludedFromDerivedLists() throws {
        let s = try store()
        s.add(title: "gone", tags: ["ghost"], project: "GhostProj")
        let id = try #require(s.tasks.first?.id)
        s.delete(id)
        #expect(!s.allProjects.contains { $0.name == "GhostProj" })
        #expect(!s.projects.contains("GhostProj"))
        #expect(!s.allTags.contains("ghost"))
        let (fresh, dups) = s.partitionByDuplicateTitle([TaskItem(title: "gone")])
        #expect(fresh.count == 1 && dups.isEmpty)
        s.restore(id)
        #expect(s.projects.contains("GhostProj"))
        #expect(s.allTags.contains("ghost"))
    }

    @Test func moveIgnoresTrashedSiblings() throws {
        let s = try store()
        s.add(title: "a"); s.add(title: "trash"); s.add(title: "c")
        let ids = s.tasks.map(\.id)
        s.delete(ids[1])
        s.move(ids[2], up: true)   // should swap with a, not the trashed task
        let byID = Dictionary(uniqueKeysWithValues: s.tasks.map { ($0.id, $0.sortOrder) })
        #expect(byID[ids[2]]! < byID[ids[0]]!)
    }

    @Test func clearCompletedKeepsTrashedDoneTasks() throws {
        let s = try store()
        s.add(title: "done-live"); s.add(title: "done-trashed")
        let ids = s.tasks.map(\.id)
        s.toggleDone(ids[0]); s.toggleDone(ids[1])
        s.delete(ids[1])
        s.clearCompleted()
        #expect(!s.tasks.contains { $0.id == ids[0] })
        #expect(s.tasks.contains { $0.id == ids[1] })
        s.restore(ids[1])
        #expect(s.tasks.first { $0.id == ids[1] }?.isDone == true)
    }

    @Test func cliSnapshotSkipsTrashed() {
        var t = TaskItem(title: "t")
        t.trashedAt = Date()
        let live = TaskItem(title: "live")
        let entries = CLIBridge.taskSnapshotEntries(from: [t, live])
        #expect(entries.map(\.title) == ["live"])
    }

    @Test func focusQueueDropsTrashed() throws {
        let s = try store()
        s.add(title: "q")
        let id = try #require(s.tasks.first?.id)
        let name = "review-fq-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        defer { d.removePersistentDomain(forName: name) }
        let q = FocusQueue(defaults: d)
        q.enqueue(id)
        s.delete(id)
        #expect(q.current(validatedAgainst: s) == nil)
    }

    // MARK: 3.2

    @Test func noCamelCaseJiraColumnsOnFreshDatabase() throws {
        let url = try dbURL()
        _ = TaskDatabase(path: url.path)
        _ = TaskDatabase(path: url.path)
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "PRAGMA table_info(tasks);", -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        var names: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            names.append(String(cString: sqlite3_column_text(stmt, 1)))
        }
        #expect(names.contains("jira_key"))
        #expect(!names.contains("jiraKey"))
        #expect(!names.contains("jiraIssueType"))
    }
}
