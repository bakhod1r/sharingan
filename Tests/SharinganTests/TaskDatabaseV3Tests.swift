import Testing
import Foundation
import SQLite3
@testable import SharinganCore

/// Covers the v3 schema (docs/schema.md): integer surrogate keys, tags in the
/// `task_tags` junction, subtasks in the EAV store, upsert-by-UUID persistence,
/// and the in-place v1 → v3 migration.
@Suite("TaskDatabase v3")
struct TaskDatabaseV3Tests {

    // MARK: - Helpers

    private func freshPath() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("taskdb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("blink.sqlite").path
    }

    private func openRaw(_ path: String) -> OpaquePointer? {
        var db: OpaquePointer?
        _ = sqlite3_open(path, &db)
        return db
    }

    /// Runs a scalar-integer query against a raw handle (for asserting on the
    /// physical schema the public API hides).
    private func scalar(_ db: OpaquePointer?, _ sql: String) -> Int64 {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return -1 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : -1
    }

    // MARK: - Round trips

    @Test func taskWithTagsAndSubtasksRoundTrips() throws {
        let path = try freshPath()
        var task = TaskItem(title: "Write report", category: "Work",
                            tags: ["urgent", "q3"], notes: "draft first")
        task.project = "Launch"
        task.priority = .high
        task.subtasks = [
            Subtask(title: "Outline", isDone: true, estimatedPomodoros: 2, pomodorosDone: 2),
            Subtask(title: "Body", pomodoroKind: .big, priority: .medium),
        ]
        do {
            let db = try #require(TaskDatabase(path: path))
            db.saveCategories([TaskCategory(name: "Work", colorHex: "#4F8DFD")])
            db.saveTasks([task])
        }
        let reloaded = try #require(TaskDatabase(path: path)).loadTasks()
        #expect(reloaded.count == 1)
        let t = try #require(reloaded.first)
        #expect(t.id == task.id)
        #expect(t.title == "Write report")
        #expect(t.category == "Work")
        #expect(t.project == "Launch")
        #expect(t.priority == .high)
        #expect(t.tags == ["urgent", "q3"])
        #expect(t.subtasks.count == 2)
        #expect(t.subtasks[0].title == "Outline")
        #expect(t.subtasks[0].isDone)
        #expect(t.subtasks[0].estimatedPomodoros == 2)
        #expect(t.subtasks[1].pomodoroKind == .big)
        #expect(t.subtasks[1].priority == .medium)
        // Subtask order is preserved by sort_order.
        #expect(t.subtasks.map(\.id) == task.subtasks.map(\.id))
    }

    @Test func tagsLiveInJunctionNotOnTask() throws {
        let path = try freshPath()
        let task = TaskItem(title: "T", category: "Work", tags: ["a", "b"])
        do {
            let db = try #require(TaskDatabase(path: path))
            db.saveTasks([task])
        }
        let raw = openRaw(path)
        defer { sqlite3_close(raw) }
        // Two tags catalogued, two junction rows, and no JSON `tags` column left.
        #expect(scalar(raw, "SELECT COUNT(*) FROM tags;") == 2)
        #expect(scalar(raw, "SELECT COUNT(*) FROM task_tags;") == 2)
        #expect(scalar(raw, "SELECT COUNT(*) FROM pragma_table_info('tasks') WHERE name='tags';") == 0)
        #expect(scalar(raw, "SELECT COUNT(*) FROM pragma_table_info('tasks') WHERE name='subtasks';") == 0)
    }

    // MARK: - Upsert semantics

    @Test func upsertKeepsSurrogateIdStable() throws {
        let path = try freshPath()
        var task = TaskItem(title: "Original", category: "Work")
        let db = try #require(TaskDatabase(path: path))
        db.saveTasks([task])

        let raw = openRaw(path)
        defer { sqlite3_close(raw) }
        let firstID = scalar(raw, "SELECT id FROM tasks;")

        task.title = "Edited"
        db.saveTasks([task])
        // Same row updated in place — id must not churn.
        #expect(scalar(raw, "SELECT COUNT(*) FROM tasks;") == 1)
        #expect(scalar(raw, "SELECT id FROM tasks;") == firstID)
        #expect(db.loadTasks().first?.title == "Edited")
    }

    @Test func removedLiveTaskSurvivesButEmptiedTrashIsDeleted() throws {
        let path = try freshPath()
        let a = TaskItem(title: "A", category: "Work")
        let b = TaskItem(title: "B", category: "Work")
        var trashed = TaskItem(title: "Gone", category: "Work")
        trashed.trashedAt = Date()
        let db = try #require(TaskDatabase(path: path))
        db.saveTasks([a, b, trashed])

        // Omitting a live task keeps it ("o'chgan tasklar o'chmasin"); omitting a
        // trashed task removes it ("trashdan keyingilarni o'chirib yubor").
        db.saveTasks([a])
        let titles = Set(db.loadTasks().map(\.title))
        #expect(titles == ["A", "B"])
    }

    @Test func editingSubtasksReplacesThemCleanly() throws {
        let path = try freshPath()
        var task = TaskItem(title: "T", category: "Work",
                            subtasks: [Subtask(title: "one"), Subtask(title: "two")])
        let db = try #require(TaskDatabase(path: path))
        db.saveTasks([task])

        task.subtasks = [Subtask(title: "only")]
        db.saveTasks([task])

        let reloaded = try #require(db.loadTasks().first)
        #expect(reloaded.subtasks.map(\.title) == ["only"])
        let raw = openRaw(path)
        defer { sqlite3_close(raw) }
        // No orphaned entities or values from the removed subtasks.
        #expect(scalar(raw, "SELECT COUNT(*) FROM eav_entities;") == 1)
        #expect(scalar(raw, "SELECT COUNT(*) FROM eav_values WHERE entity_id NOT IN (SELECT id FROM eav_entities);") == 0)
    }

    // MARK: - Schema shape

    @Test func everyTableHasIntegerAutoincrementPK() throws {
        let path = try freshPath()
        _ = try #require(TaskDatabase(path: path))
        let raw = openRaw(path)
        defer { sqlite3_close(raw) }
        let tables = ["tasks", "categories", "projects", "tags", "task_tags",
                      "templates", "focus_log", "eav_attributes", "eav_entities",
                      "eav_values", "sync_shadow", "sync_state", "sync_outbox"]
        for t in tables {
            let pkIsIntId = scalar(raw, """
            SELECT COUNT(*) FROM pragma_table_info('\(t)') WHERE name='id' AND pk=1 AND type='INTEGER';
            """)
            #expect(pkIsIntId == 1, "\(t) must have an INTEGER id primary key")
        }
        // AUTOINCREMENT registers each such table in sqlite_sequence once used.
        #expect(scalar(raw, "SELECT COUNT(*) FROM sqlite_master WHERE name='sqlite_sequence';") == 1)
    }

    @Test func categoryForeignKeyResolvesById() throws {
        let path = try freshPath()
        let db = try #require(TaskDatabase(path: path))
        db.saveCategories([TaskCategory(name: "Work", colorHex: "#111111", icon: "star.fill")])
        db.saveTasks([TaskItem(title: "T", category: "Work")])
        let raw = openRaw(path)
        defer { sqlite3_close(raw) }
        // The task links to the category row by integer id, not by name.
        #expect(scalar(raw, """
        SELECT COUNT(*) FROM tasks t JOIN categories c ON c.id = t.category_id WHERE c.name='Work';
        """) == 1)
    }

    @Test func unknownCategoryIsAutoCreatedToSatisfyFK() throws {
        // saveTasks may run before saveCategories for a brand-new custom
        // category; the NOT NULL FK must still be satisfiable.
        let path = try freshPath()
        let db = try #require(TaskDatabase(path: path))
        db.saveTasks([TaskItem(title: "T", category: "Freeform")])
        #expect(db.loadCategories().contains { $0.name == "Freeform" })
        #expect(db.loadTasks().first?.category == "Freeform")
    }

    @Test func precreatedTagsHideOnceUsed() throws {
        let path = try freshPath()
        let db = try #require(TaskDatabase(path: path))
        db.saveTags(["later", "someday"])
        #expect(Set(db.loadTags()) == ["later", "someday"])
        // Using one on a task graduates it out of the precreated-unused list.
        db.saveTasks([TaskItem(title: "T", category: "Work", tags: ["later"])])
        #expect(db.loadTags() == ["someday"])
    }

    // MARK: - Migration

    @Test func migratesV1DatabaseInPlace() throws {
        let path = try freshPath()
        seedV1Database(at: path)

        // Opening through the v3 code path triggers migration.
        let db = try #require(TaskDatabase(path: path))
        let tasks = db.loadTasks()
        #expect(tasks.count == 1)
        let t = try #require(tasks.first)
        #expect(t.title == "Legacy task")
        #expect(t.category == "Work")
        #expect(Set(t.tags) == ["old", "tag"])
        #expect(t.subtasks.map(\.title) == ["step one", "step two"])
        #expect(t.subtasks[1].isDone)

        let raw = openRaw(path)
        defer { sqlite3_close(raw) }
        #expect(scalar(raw, "PRAGMA user_version;") == 3)
        // Old JSON columns are gone; data now lives in the junction + EAV.
        #expect(scalar(raw, "SELECT COUNT(*) FROM pragma_table_info('tasks') WHERE name='subtasks';") == 0)
        #expect(scalar(raw, "SELECT COUNT(*) FROM task_tags;") == 2)
        #expect(scalar(raw, "SELECT COUNT(*) FROM eav_entities;") == 2)
    }

    @Test func migrationPreservesSyncState() throws {
        let path = try freshPath()
        seedV1Database(at: path)
        // Seed a sync_state row the way v1 stored it.
        let raw0 = openRaw(path)
        let payload = "engine-state".data(using: .utf8)!
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(raw0, "INSERT INTO sync_state (key, value) VALUES ('ck', ?);", -1, &stmt, nil)
        _ = payload.withUnsafeBytes { sqlite3_bind_blob(stmt, 1, $0.baseAddress, Int32(payload.count),
                                                        unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        sqlite3_step(stmt); sqlite3_finalize(stmt); sqlite3_close(raw0)

        let db = try #require(TaskDatabase(path: path))
        #expect(db.syncStateValue("ck") == payload)
    }

    /// Writes a minimal but authentic v1-shaped database (JSON `tags` /
    /// `subtasks` columns, TEXT UUID PKs, `user_version` 0).
    private func seedV1Database(at path: String) {
        var db: OpaquePointer?
        sqlite3_open(path, &db)
        let ddl = """
        CREATE TABLE tasks (
            id TEXT PRIMARY KEY, title TEXT NOT NULL, category TEXT NOT NULL,
            tags TEXT NOT NULL DEFAULT '[]', isDone INTEGER NOT NULL DEFAULT 0,
            pomodorosDone INTEGER NOT NULL DEFAULT 0, createdAt REAL NOT NULL,
            dueDate REAL, sortOrder INTEGER NOT NULL DEFAULT 0, estimatedPomodoros INTEGER,
            plannedDate REAL, notes TEXT NOT NULL DEFAULT '', subtasks TEXT NOT NULL DEFAULT '[]',
            recurrence TEXT NOT NULL DEFAULT 'none', project TEXT, priority INTEGER NOT NULL DEFAULT 0,
            completedAt REAL, pomodoroKind TEXT, modifiedAt REAL, trashedAt REAL
        );
        CREATE TABLE categories (name TEXT PRIMARY KEY, colorHex TEXT NOT NULL, icon TEXT NOT NULL);
        CREATE TABLE projects (id INTEGER PRIMARY KEY AUTOINCREMENT, name VARCHAR(255) NOT NULL UNIQUE,
            colorHex VARCHAR(9) NOT NULL, icon VARCHAR(64) NOT NULL);
        CREATE TABLE templates (id TEXT PRIMARY KEY, name TEXT NOT NULL, json TEXT NOT NULL);
        CREATE TABLE tags (name TEXT PRIMARY KEY);
        CREATE TABLE focus_log (day REAL NOT NULL, task_id TEXT NOT NULL, subtask_id TEXT NOT NULL DEFAULT '',
            title TEXT NOT NULL, count INTEGER NOT NULL DEFAULT 0, seconds REAL NOT NULL DEFAULT 0,
            PRIMARY KEY (day, task_id, subtask_id));
        CREATE TABLE sync_shadow (record_type TEXT NOT NULL, record_name TEXT NOT NULL,
            content_hash TEXT NOT NULL, system_fields BLOB, PRIMARY KEY (record_type, record_name));
        CREATE TABLE sync_state (key TEXT PRIMARY KEY, value BLOB NOT NULL);
        CREATE TABLE sync_outbox (id INTEGER PRIMARY KEY AUTOINCREMENT, record_type VARCHAR(64) NOT NULL,
            record_name VARCHAR(255) NOT NULL, kind VARCHAR(16) NOT NULL, enqueued_at REAL NOT NULL,
            attempts INTEGER NOT NULL, next_attempt_at REAL NOT NULL, UNIQUE (record_type, record_name));
        INSERT INTO categories (name, colorHex, icon) VALUES ('Work', '#4F8DFD', 'briefcase.fill');
        INSERT INTO tasks (id, title, category, tags, createdAt, subtasks, modifiedAt) VALUES (
            '11111111-1111-1111-1111-111111111111', 'Legacy task', 'Work', '["old","tag"]',
            1000, '[{"id":"22222222-2222-2222-2222-222222222222","title":"step one","isDone":false,"pomodorosDone":0,"priority":0},{"id":"33333333-3333-3333-3333-333333333333","title":"step two","isDone":true,"pomodorosDone":0,"priority":0}]',
            1000);
        PRAGMA user_version = 0;
        """
        sqlite3_exec(db, ddl, nil, nil, nil)
        sqlite3_close(db)
    }
}
