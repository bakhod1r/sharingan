import Testing
import Foundation
import SQLite3
@testable import SharinganCore

/// Guards the "changed-only" save fast path: `saveTasks` must skip a task whose
/// content hasn't changed, so a persist never rebuilds every task's tag/subtask
/// rows (the rewrite storm that held the SQLite write lock long enough to
/// collide with a background sync write and freeze the main thread).
@Suite("Save fast path")
struct SavePerformanceTests {

    private func freshPath() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("savefast-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("blink.sqlite").path
    }

    private func openRaw(_ path: String) -> OpaquePointer? {
        var db: OpaquePointer?; _ = sqlite3_open(path, &db); return db
    }
    private func scalar(_ db: OpaquePointer?, _ sql: String) -> Int64 {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return -1 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : -1
    }

    @Test func unchangedTaskIsNotRewritten() throws {
        let path = try freshPath()
        let db = try #require(TaskDatabase(path: path))
        var task = TaskItem(title: "T", category: "Work",
                            subtasks: [Subtask(title: "a"), Subtask(title: "b")])
        db.saveTasks([task])

        let raw = openRaw(path)
        defer { sqlite3_close(raw) }
        // Rebuilding subtasks does DELETE+INSERT, which advances the AUTOINCREMENT
        // id. Capture the current max id, then save the identical array again.
        let idBefore = scalar(raw, "SELECT MAX(id) FROM eav_entities;")
        db.saveTasks([task])
        let idAfter = scalar(raw, "SELECT MAX(id) FROM eav_entities;")
        #expect(idBefore == idAfter, "an unchanged task must not rebuild its subtask rows")

        // A real edit must still be written.
        task.title = "T edited"
        db.saveTasks([task])
        #expect(db.loadTasks().first?.title == "T edited")
    }

    @Test func onlyTheChangedTaskRebuildsChildren() throws {
        let path = try freshPath()
        let db = try #require(TaskDatabase(path: path))
        var a = TaskItem(title: "A", category: "Work", subtasks: [Subtask(title: "a1")])
        let b = TaskItem(title: "B", category: "Work", subtasks: [Subtask(title: "b1")])
        db.saveTasks([a, b])

        let raw = openRaw(path)
        defer { sqlite3_close(raw) }
        // B's subtask entity id — must survive an edit that only touches A.
        let bEntityID = scalar(raw, """
        SELECT e.id FROM eav_entities e JOIN tasks t ON t.id = e.owner_id WHERE t.uuid = '\(b.id.uuidString)';
        """)
        a.subtasks = [Subtask(title: "a1"), Subtask(title: "a2")]
        db.saveTasks([a, b])
        let bEntityIDAfter = scalar(raw, """
        SELECT e.id FROM eav_entities e JOIN tasks t ON t.id = e.owner_id WHERE t.uuid = '\(b.id.uuidString)';
        """)
        #expect(bEntityID == bEntityIDAfter, "editing A must not rewrite B's subtasks")
        #expect(db.loadTasks().first { $0.id == a.id }?.subtasks.count == 2)
    }

    @Test func reSavingIdenticalArrayIsANoOp() throws {
        let path = try freshPath()
        let db = try #require(TaskDatabase(path: path))
        let tasks = (0..<5).map { TaskItem(title: "T\($0)", category: "Work",
                                           subtasks: [Subtask(title: "s")]) }
        db.saveTasks(tasks)
        let raw = openRaw(path)
        defer { sqlite3_close(raw) }
        let valuesBefore = scalar(raw, "SELECT MAX(id) FROM eav_values;")
        db.saveTasks(tasks)   // identical — should touch nothing
        let valuesAfter = scalar(raw, "SELECT MAX(id) FROM eav_values;")
        #expect(valuesBefore == valuesAfter)
    }
}
