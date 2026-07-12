import Foundation
import SQLite3
import Testing
@testable import SharinganCore

@MainActor
@Suite("Task completion history")
struct TaskArchiveTests {
    private func tempStore() -> TaskStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("blink-archive-\(UUID().uuidString).json")
        return TaskStore(fileURL: url)
    }

    @Test func toggleDoneSetsCompletedAt() throws {
        let s = tempStore()
        s.add(title: "Finish me")
        let id = s.tasks[0].id
        #expect(s.tasks[0].completedAt == nil)

        s.toggleDone(id)
        let stamp = try #require(s.tasks.first { $0.id == id }?.completedAt)
        #expect(abs(stamp.timeIntervalSinceNow) < 5)
    }

    @Test func unToggleClearsCompletedAt() {
        let s = tempStore()
        s.add(title: "Undo me")
        let id = s.tasks[0].id
        s.toggleDone(id)
        s.toggleDone(id)
        let task = s.tasks.first { $0.id == id }
        #expect(task?.isDone == false)
        #expect(task?.completedAt == nil)
    }

    @Test func decodesLegacyJSONWithoutCompletedAt() throws {
        // Old persisted rows never carried the key — must still decode.
        let json = #"{"title":"Legacy","isDone":true}"#
        let task = try JSONDecoder().decode(TaskItem.self, from: Data(json.utf8))
        #expect(task.title == "Legacy")
        #expect(task.isDone)
        #expect(task.completedAt == nil)
    }

    @Test func completedAtRoundTripsThroughCodable() throws {
        var task = TaskItem(title: "Round trip")
        task.completedAt = Date(timeIntervalSince1970: 1_000_000)
        let data = try JSONEncoder().encode(task)
        let decoded = try JSONDecoder().decode(TaskItem.self, from: data)
        #expect(decoded.completedAt == task.completedAt)
    }

    @Test func spawnedOccurrenceHasNoCompletionState() throws {
        let s = tempStore()
        s.add(title: "Daily habit", recurrence: .daily)
        let id = s.tasks[0].id
        s.toggleDone(id)

        let spawned = try #require(
            s.tasks.first { $0.title == "Daily habit" && $0.id != id })
        #expect(spawned.isDone == false)
        #expect(spawned.completedAt == nil)
        // The completed original keeps its stamp.
        #expect(s.tasks.first { $0.id == id }?.completedAt != nil)
    }

    @Test func csvIncludesCompletedColumn() {
        let s = tempStore()
        s.add(title: "Shipped")
        s.add(title: "Open")
        s.toggleDone(s.tasks.first { $0.title == "Shipped" }!.id)

        let csv = s.csv()
        let lines = csv.split(separator: "\n").map(String.init)
        #expect(lines[0] == "title,category,tags,done,pomodoros,due,created,completed")
        let shippedRow = lines.first { $0.contains("Shipped") }!
        let stamp = s.tasks.first { $0.title == "Shipped" }!.completedAt!
        #expect(shippedRow.hasSuffix(ISO8601DateFormatter().string(from: stamp)))
        // Open task ends with an empty completed field.
        #expect(lines.first { $0.contains("\"Open\"") }!.hasSuffix(","))
    }

    @Test func completedAtPersistsAcrossInstances() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("blink-archive-persist-\(UUID().uuidString).json")
        let a = TaskStore(fileURL: url)
        a.add(title: "Keep my stamp")
        a.toggleDone(a.tasks[0].id)
        let stamp = a.tasks[0].completedAt

        let b = TaskStore(fileURL: url)
        let reloaded = b.tasks.first { $0.title == "Keep my stamp" }
        #expect(reloaded?.completedAt != nil)
        // Stored as an epoch double — compare with tolerance.
        #expect(abs(reloaded!.completedAt!.timeIntervalSince(stamp!)) < 0.001)
    }

    @Test func migratesPreColumnDatabase() throws {
        // A database created before completedAt shipped: same table, no column.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("blink-archive-migrate-\(UUID().uuidString).sqlite")
        var raw: OpaquePointer?
        try #require(sqlite3_open(url.path, &raw) == SQLITE_OK)
        let old = """
        CREATE TABLE tasks (
            id TEXT PRIMARY KEY, title TEXT NOT NULL, category TEXT NOT NULL,
            tags TEXT NOT NULL DEFAULT '[]', isDone INTEGER NOT NULL DEFAULT 0,
            pomodorosDone INTEGER NOT NULL DEFAULT 0, createdAt REAL NOT NULL,
            dueDate REAL, sortOrder INTEGER NOT NULL DEFAULT 0,
            estimatedPomodoros INTEGER, plannedDate REAL,
            notes TEXT NOT NULL DEFAULT '', subtasks TEXT NOT NULL DEFAULT '[]',
            recurrence TEXT NOT NULL DEFAULT 'none', project TEXT,
            priority INTEGER NOT NULL DEFAULT 0
        );
        INSERT INTO tasks (id, title, category, createdAt)
        VALUES ('\(UUID().uuidString)', 'Old row', 'Work', 0);
        """
        try #require(sqlite3_exec(raw, old, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(raw)

        let s = TaskStore(fileURL: url)
        let task = try #require(s.tasks.first { $0.title == "Old row" })
        #expect(task.completedAt == nil)
        s.toggleDone(task.id)   // exercises the added column on save

        let reloaded = TaskStore(fileURL: url)
        #expect(reloaded.tasks.first { $0.title == "Old row" }?.completedAt != nil)
    }
}
