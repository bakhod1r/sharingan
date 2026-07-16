import Foundation
import SQLite3

/// Thin SQLite persistence layer for tasks and categories, using the SQLite3 C
/// library bundled with macOS (no external package). TaskStore keeps its
/// in-memory `@Published` model and public API unchanged — only its load/save
/// internals route through here. Each save replaces the table contents inside a
/// single transaction, so a crash mid-write can never leave a half-written file
/// (the whole point of moving off the plain-JSON blob).
final class TaskDatabase: SyncOutboxStorage {
    private var db: OpaquePointer?

    /// SQLite needs to copy bound strings/blobs (they're freed after the call).
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init?(path: String) {
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            sqlite3_close(db); db = nil; return nil
        }
        exec("PRAGMA journal_mode=WAL;")
        exec("PRAGMA busy_timeout=3000;")
        createTables()
    }

    deinit { sqlite3_close(db) }

    // MARK: - Schema

    private func createTables() {
        exec("""
        CREATE TABLE IF NOT EXISTS tasks (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            category TEXT NOT NULL,
            tags TEXT NOT NULL DEFAULT '[]',
            isDone INTEGER NOT NULL DEFAULT 0,
            pomodorosDone INTEGER NOT NULL DEFAULT 0,
            createdAt REAL NOT NULL,
            dueDate REAL,
            sortOrder INTEGER NOT NULL DEFAULT 0,
            estimatedPomodoros INTEGER,
            plannedDate REAL,
            notes TEXT NOT NULL DEFAULT '',
            subtasks TEXT NOT NULL DEFAULT '[]',
            recurrence TEXT NOT NULL DEFAULT 'none',
            project TEXT,
            priority INTEGER NOT NULL DEFAULT 0,
            completedAt REAL,
            pomodoroKind TEXT,
            modifiedAt REAL
        );
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS categories (
            name TEXT PRIMARY KEY,
            colorHex TEXT NOT NULL,
            icon TEXT NOT NULL
        );
        """)
        // Projects share the categories' colour/icon shape but their own table.
        // VARCHAR + integer surrogate PK by project convention; the natural key
        // stays enforced through UNIQUE(name).
        exec("""
        CREATE TABLE IF NOT EXISTS projects (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name VARCHAR(255) NOT NULL UNIQUE,
            colorHex VARCHAR(9) NOT NULL,
            icon VARCHAR(64) NOT NULL
        );
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS templates (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            json TEXT NOT NULL
        );
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS tags (
            name TEXT PRIMARY KEY
        );
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS focus_log (
            day REAL NOT NULL,
            task_id TEXT NOT NULL,
            subtask_id TEXT NOT NULL DEFAULT '',
            title TEXT NOT NULL,
            count INTEGER NOT NULL DEFAULT 0,
            seconds REAL NOT NULL DEFAULT 0,
            PRIMARY KEY (day, task_id, subtask_id)
        );
        """)
        // Sync bookkeeping. sync_shadow is what the whole-collection saves
        // above are diffed against — without it a DELETE-all + re-INSERT is
        // indistinguishable from "the user deleted everything".
        exec("""
        CREATE TABLE IF NOT EXISTS sync_shadow (
            record_type TEXT NOT NULL,
            record_name TEXT NOT NULL,
            content_hash TEXT NOT NULL,
            system_fields BLOB,
            PRIMARY KEY (record_type, record_name)
        );
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS sync_state (
            key TEXT PRIMARY KEY,
            value BLOB NOT NULL
        );
        """)
        // The durable push queue (see SyncOutbox). Deliberately NOT wiped by
        // resetSyncState(): a tombstone here is the only record that a delete
        // ever happened once the shadow is gone. VARCHAR by project convention.
        exec("""
        CREATE TABLE IF NOT EXISTS sync_outbox (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            record_type VARCHAR(64) NOT NULL,
            record_name VARCHAR(255) NOT NULL,
            kind VARCHAR(16) NOT NULL,
            enqueued_at REAL NOT NULL,
            attempts INTEGER NOT NULL,
            next_attempt_at REAL NOT NULL,
            UNIQUE (record_type, record_name)
        );
        """)
        // Databases created before the column shipped need it added in place
        // (CREATE IF NOT EXISTS won't touch an existing table).
        if !tableHasColumn("tasks", "completedAt") {
            exec("ALTER TABLE tasks ADD COLUMN completedAt REAL;")
        }
        // The task-level pomodoro size never had a column — it silently
        // dropped on every save/reload (subtask kinds survived inside the
        // subtasks JSON). Found by the import end-to-end round-trip test.
        if !tableHasColumn("tasks", "pomodoroKind") {
            exec("ALTER TABLE tasks ADD COLUMN pomodoroKind TEXT;")
        }
        // Databases created before 1.3.0 need the sync timestamp added in
        // place; backfilling it from createdAt keeps every existing task's
        // first sync a clean create rather than a spurious conflict.
        if !tableHasColumn("tasks", "modifiedAt") {
            exec("ALTER TABLE tasks ADD COLUMN modifiedAt REAL;")
            exec("UPDATE tasks SET modifiedAt = createdAt WHERE modifiedAt IS NULL;")
        }
        // Soft-delete / Trash timestamp; NULL means the task is live.
        if !tableHasColumn("tasks", "trashedAt") {
            exec("ALTER TABLE tasks ADD COLUMN trashedAt REAL;")
        }
    }

    /// True when `PRAGMA table_info` lists the column — guards ALTER TABLE,
    /// which SQLite errors on (rather than ignores) for an existing column.
    private func tableHasColumn(_ table: String, _ column: String) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table));", -1, &stmt, nil) == SQLITE_OK
        else { return false }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if text(stmt, 1) == column { return true }
        }
        return false
    }

    // MARK: - Tasks

    func loadTasks() -> [TaskItem] {
        var out: [TaskItem] = []
        let sql = """
        SELECT id,title,category,tags,isDone,pomodorosDone,createdAt,dueDate,\
        sortOrder,estimatedPomodoros,plannedDate,notes,subtasks,recurrence,project,priority,\
        completedAt,pomodoroKind,modifiedAt,trashedAt \
        FROM tasks;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return out }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idText = text(stmt, 0), let id = UUID(uuidString: idText) else { continue }
            var t = TaskItem(title: text(stmt, 1) ?? "", category: text(stmt, 2) ?? "")
            t.id = id
            t.tags = decodeJSON([String].self, text(stmt, 3)) ?? []
            t.isDone = int(stmt, 4) != 0
            t.pomodorosDone = Int(int(stmt, 5))
            t.createdAt = Date(timeIntervalSince1970: double(stmt, 6))
            t.dueDate = date(stmt, 7)
            t.sortOrder = Int(int(stmt, 8))
            t.estimatedPomodoros = isNull(stmt, 9) ? nil : Int(int(stmt, 9))
            t.plannedDate = date(stmt, 10)
            t.notes = text(stmt, 11) ?? ""
            t.subtasks = decodeJSON([Subtask].self, text(stmt, 12)) ?? []
            t.recurrence = Recurrence(string: text(stmt, 13) ?? "none")
            t.project = isNull(stmt, 14) ? nil : text(stmt, 14)
            t.priority = TaskPriority(rawValue: Int(int(stmt, 15)))
            t.completedAt = date(stmt, 16)
            t.pomodoroKind = text(stmt, 17).flatMap(PomodoroKind.init(rawValue:))
            t.modifiedAt = date(stmt, 18) ?? t.createdAt
            t.trashedAt = date(stmt, 19)
            out.append(t)
        }
        return out
    }

    func saveTasks(_ tasks: [TaskItem]) {
        transaction {
            guard exec("DELETE FROM tasks;") else { return false }
            let sql = """
            INSERT INTO tasks (id,title,category,tags,isDone,pomodorosDone,createdAt,dueDate,\
            sortOrder,estimatedPomodoros,plannedDate,notes,subtasks,recurrence,project,priority,\
            completedAt,pomodoroKind,modifiedAt,trashedAt) \
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
            defer { sqlite3_finalize(stmt) }
            for t in tasks {
                sqlite3_reset(stmt)
                bindText(stmt, 1, t.id.uuidString)
                bindText(stmt, 2, t.title)
                bindText(stmt, 3, t.category)
                bindText(stmt, 4, encodeJSON(t.tags) ?? "[]")
                sqlite3_bind_int(stmt, 5, t.isDone ? 1 : 0)
                sqlite3_bind_int(stmt, 6, Int32(t.pomodorosDone))
                sqlite3_bind_double(stmt, 7, t.createdAt.timeIntervalSince1970)
                bindDate(stmt, 8, t.dueDate)
                sqlite3_bind_int(stmt, 9, Int32(t.sortOrder))
                if let est = t.estimatedPomodoros { sqlite3_bind_int(stmt, 10, Int32(est)) }
                else { sqlite3_bind_null(stmt, 10) }
                bindDate(stmt, 11, t.plannedDate)
                bindText(stmt, 12, t.notes)
                bindText(stmt, 13, encodeJSON(t.subtasks) ?? "[]")
                bindText(stmt, 14, t.recurrence.stringValue)
                if let p = t.project { bindText(stmt, 15, p) } else { sqlite3_bind_null(stmt, 15) }
                sqlite3_bind_int(stmt, 16, Int32(t.priority.rawValue))
                bindDate(stmt, 17, t.completedAt)
                if let k = t.pomodoroKind { bindText(stmt, 18, k.rawValue) }
                else { sqlite3_bind_null(stmt, 18) }
                bindDate(stmt, 19, t.modifiedAt)
                bindDate(stmt, 20, t.trashedAt)
                guard sqlite3_step(stmt) == SQLITE_DONE else { return false }
            }
            return true
        }
    }

    // MARK: - Categories

    func loadCategories() -> [TaskCategory] {
        var out: [TaskCategory] = []
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT name,colorHex,icon FROM categories;", -1, &stmt, nil) == SQLITE_OK
        else { return out }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(TaskCategory(name: text(stmt, 0) ?? "",
                                    colorHex: text(stmt, 1) ?? "#9AA3AF",
                                    icon: text(stmt, 2) ?? "folder.fill"))
        }
        return out
    }

    func saveCategories(_ cats: [TaskCategory]) {
        transaction {
            guard exec("DELETE FROM categories;") else { return false }
            let sql = "INSERT INTO categories (name,colorHex,icon) VALUES (?,?,?);"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
            defer { sqlite3_finalize(stmt) }
            for c in cats {
                sqlite3_reset(stmt)
                bindText(stmt, 1, c.name)
                bindText(stmt, 2, c.colorHex)
                bindText(stmt, 3, c.icon)
                guard sqlite3_step(stmt) == SQLITE_DONE else { return false }
            }
            return true
        }
    }

    // MARK: - Projects (same shape as categories, own table)

    func loadProjects() -> [TaskCategory] {
        var out: [TaskCategory] = []
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT name,colorHex,icon FROM projects;", -1, &stmt, nil) == SQLITE_OK
        else { return out }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(TaskCategory(name: text(stmt, 0) ?? "",
                                    colorHex: text(stmt, 1) ?? "#9AA3AF",
                                    icon: text(stmt, 2) ?? "folder.fill"))
        }
        return out
    }

    func saveProjects(_ projects: [TaskCategory]) {
        transaction {
            guard exec("DELETE FROM projects;") else { return false }
            let sql = "INSERT INTO projects (name,colorHex,icon) VALUES (?,?,?);"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
            defer { sqlite3_finalize(stmt) }
            for p in projects {
                sqlite3_reset(stmt)
                bindText(stmt, 1, p.name)
                bindText(stmt, 2, p.colorHex)
                bindText(stmt, 3, p.icon)
                guard sqlite3_step(stmt) == SQLITE_DONE else { return false }
            }
            return true
        }
    }

    // MARK: - Tags

    /// User-precreated tags with 0 uses so far (sidebar "+"). Tags born from
    /// typing `#tag` on a task live only on the task itself and never appear
    /// here — this table is purely the "precreated, unused so far" registry.
    func loadTags() -> [String] {
        var out: [String] = []
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT name FROM tags;", -1, &stmt, nil) == SQLITE_OK
        else { return out }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let n = text(stmt, 0) { out.append(n) }
        }
        return out
    }

    func saveTags(_ tags: [String]) {
        transaction {
            guard exec("DELETE FROM tags;") else { return false }
            let sql = "INSERT INTO tags (name) VALUES (?);"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
            defer { sqlite3_finalize(stmt) }
            for t in tags {
                sqlite3_reset(stmt)
                bindText(stmt, 1, t)
                guard sqlite3_step(stmt) == SQLITE_DONE else { return false }
            }
            return true
        }
    }

    // MARK: - Templates

    /// The template's `TaskItem` is stored as one JSON blob — templates are
    /// only ever read back whole, so there's nothing to gain from columns.
    func loadTemplates() -> [TaskTemplate] {
        var out: [TaskTemplate] = []
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT id,name,json FROM templates;", -1, &stmt, nil) == SQLITE_OK
        else { return out }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idText = text(stmt, 0), let id = UUID(uuidString: idText),
                  let item = decodeJSON(TaskItem.self, text(stmt, 2)) else { continue }
            out.append(TaskTemplate(id: id, name: text(stmt, 1) ?? "", item: item))
        }
        return out
    }

    func saveTemplates(_ templates: [TaskTemplate]) {
        transaction {
            guard exec("DELETE FROM templates;") else { return false }
            let sql = "INSERT INTO templates (id,name,json) VALUES (?,?,?);"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
            defer { sqlite3_finalize(stmt) }
            for t in templates {
                sqlite3_reset(stmt)
                bindText(stmt, 1, t.id.uuidString)
                bindText(stmt, 2, t.name)
                guard let json = encodeJSON(t.item) else { return false }
                bindText(stmt, 3, json)
                guard sqlite3_step(stmt) == SQLITE_DONE else { return false }
            }
            return true
        }
    }

    // MARK: - Focus log

    func loadFocusLog() -> [FocusLogEntry] {
        var out: [FocusLogEntry] = []
        var stmt: OpaquePointer?
        let sql = "SELECT day, task_id, subtask_id, title, count, seconds FROM focus_log;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return out }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let taskID = UUID(uuidString: text(stmt, 1) ?? "") else { continue }
            let subRaw = text(stmt, 2) ?? ""
            out.append(FocusLogEntry(
                day: Date(timeIntervalSince1970: double(stmt, 0)),
                taskID: taskID,
                subtaskID: subRaw.isEmpty ? nil : UUID(uuidString: subRaw),
                title: text(stmt, 3) ?? "",
                count: Int(int(stmt, 4)),
                seconds: double(stmt, 5)))
        }
        return out
    }

    func saveFocusLog(_ entries: [FocusLogEntry]) {
        transaction {
            guard exec("DELETE FROM focus_log;") else { return false }
            let sql = """
            INSERT INTO focus_log (day, task_id, subtask_id, title, count, seconds)
            VALUES (?,?,?,?,?,?);
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
            defer { sqlite3_finalize(stmt) }
            for e in entries {
                sqlite3_reset(stmt)
                sqlite3_bind_double(stmt, 1, e.day.timeIntervalSince1970)
                bindText(stmt, 2, e.taskID.uuidString)
                bindText(stmt, 3, e.subtaskID?.uuidString ?? "")
                bindText(stmt, 4, e.title)
                sqlite3_bind_int64(stmt, 5, Int64(e.count))
                sqlite3_bind_double(stmt, 6, e.seconds)
                guard sqlite3_step(stmt) == SQLITE_DONE else { return false }
            }
            return true
        }
    }

    // MARK: - Sync bookkeeping

    func loadShadow(recordType: String) -> [String: ShadowEntry] {
        var out: [String: ShadowEntry] = [:]
        var stmt: OpaquePointer?
        let sql = "SELECT record_name, content_hash, system_fields FROM sync_shadow WHERE record_type = ?;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return out }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, recordType)
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let name = text(stmt, 0), let hash = text(stmt, 1) else { continue }
            var fields: Data?
            if let blob = sqlite3_column_blob(stmt, 2) {
                fields = Data(bytes: blob, count: Int(sqlite3_column_bytes(stmt, 2)))
            }
            out[name] = ShadowEntry(recordName: name, contentHash: hash, systemFields: fields)
        }
        return out
    }

    /// Written only after CloudKit confirms a save/fetch — never speculatively,
    /// or an interrupted sync would forget changes it never actually pushed.
    func upsertShadow(recordType: String, entry: ShadowEntry) {
        let sql = """
        INSERT INTO sync_shadow (record_type, record_name, content_hash, system_fields)
        VALUES (?,?,?,?)
        ON CONFLICT(record_type, record_name) DO UPDATE SET
            content_hash = excluded.content_hash,
            system_fields = excluded.system_fields;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, recordType)
        bindText(stmt, 2, entry.recordName)
        bindText(stmt, 3, entry.contentHash)
        if let fields = entry.systemFields {
            _ = fields.withUnsafeBytes {
                sqlite3_bind_blob(stmt, 4, $0.baseAddress, Int32(fields.count), Self.transient)
            }
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        _ = sqlite3_step(stmt)
    }

    func deleteShadow(recordType: String, recordName: String) {
        var stmt: OpaquePointer?
        let sql = "DELETE FROM sync_shadow WHERE record_type = ? AND record_name = ?;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, recordType)
        bindText(stmt, 2, recordName)
        _ = sqlite3_step(stmt)
    }

    /// Wipes all sync bookkeeping — used when the iCloud account changes, so
    /// the next sync re-establishes state from scratch instead of merging one
    /// person's records into another's.
    func resetSyncState() {
        transaction {
            exec("DELETE FROM sync_shadow;") && exec("DELETE FROM sync_state;")
        }
    }

    func syncStateValue(_ key: String) -> Data? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM sync_state WHERE key = ?;", -1, &stmt, nil) == SQLITE_OK
        else { return nil }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, key)
        guard sqlite3_step(stmt) == SQLITE_ROW, let blob = sqlite3_column_blob(stmt, 0) else { return nil }
        return Data(bytes: blob, count: Int(sqlite3_column_bytes(stmt, 0)))
    }

    func setSyncStateValue(_ key: String, _ value: Data) {
        var stmt: OpaquePointer?
        let sql = "INSERT INTO sync_state (key, value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, key)
        _ = value.withUnsafeBytes {
            sqlite3_bind_blob(stmt, 2, $0.baseAddress, Int32(value.count), Self.transient)
        }
        _ = sqlite3_step(stmt)
    }

    // MARK: - Sync outbox (SyncOutboxStorage)

    func loadOutbox() -> [SyncOutbox.Op] {
        var out: [SyncOutbox.Op] = []
        var stmt: OpaquePointer?
        let sql = "SELECT record_type, record_name, kind, enqueued_at, attempts, next_attempt_at FROM sync_outbox;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return out }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let type = text(stmt, 0), let name = text(stmt, 1),
                  let kind = SyncOutbox.Kind(rawValue: text(stmt, 2) ?? "") else { continue }
            out.append(SyncOutbox.Op(
                recordType: type,
                recordName: name,
                kind: kind,
                enqueuedAt: Date(timeIntervalSince1970: double(stmt, 3)),
                attempts: Int(int(stmt, 4)),
                nextAttemptAt: Date(timeIntervalSince1970: double(stmt, 5))))
        }
        return out
    }

    func upsertOutbox(_ op: SyncOutbox.Op) {
        let sql = """
        INSERT INTO sync_outbox (record_type, record_name, kind, enqueued_at, attempts, next_attempt_at)
        VALUES (?,?,?,?,?,?)
        ON CONFLICT(record_type, record_name) DO UPDATE SET
            kind = excluded.kind,
            enqueued_at = excluded.enqueued_at,
            attempts = excluded.attempts,
            next_attempt_at = excluded.next_attempt_at;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, op.recordType)
        bindText(stmt, 2, op.recordName)
        bindText(stmt, 3, op.kind.rawValue)
        sqlite3_bind_double(stmt, 4, op.enqueuedAt.timeIntervalSince1970)
        sqlite3_bind_int64(stmt, 5, Int64(op.attempts))
        sqlite3_bind_double(stmt, 6, op.nextAttemptAt.timeIntervalSince1970)
        _ = sqlite3_step(stmt)
    }

    func deleteOutbox(recordType: String, recordName: String) {
        var stmt: OpaquePointer?
        let sql = "DELETE FROM sync_outbox WHERE record_type = ? AND record_name = ?;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, recordType)
        bindText(stmt, 2, recordName)
        _ = sqlite3_step(stmt)
    }

    func clearOutbox() { exec("DELETE FROM sync_outbox;") }

    // MARK: - Low-level helpers

    @discardableResult
    private func exec(_ sql: String) -> Bool { sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK }

    /// Runs `body` inside BEGIN…COMMIT and rolls back if any step reports
    /// failure — a half-failed replace must never commit the bare DELETE.
    private func transaction(_ body: () -> Bool) {
        guard exec("BEGIN;") else { return }
        if body() {
            exec("COMMIT;")
        } else {
            exec("ROLLBACK;")
        }
    }

    private func bindText(_ stmt: OpaquePointer?, _ i: Int32, _ value: String) {
        sqlite3_bind_text(stmt, i, value, -1, Self.transient)
    }
    private func bindDate(_ stmt: OpaquePointer?, _ i: Int32, _ date: Date?) {
        if let d = date { sqlite3_bind_double(stmt, i, d.timeIntervalSince1970) }
        else { sqlite3_bind_null(stmt, i) }
    }

    private func text(_ stmt: OpaquePointer?, _ i: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, i) else { return nil }
        return String(cString: c)
    }
    private func int(_ stmt: OpaquePointer?, _ i: Int32) -> Int64 { sqlite3_column_int64(stmt, i) }
    private func double(_ stmt: OpaquePointer?, _ i: Int32) -> Double { sqlite3_column_double(stmt, i) }
    private func isNull(_ stmt: OpaquePointer?, _ i: Int32) -> Bool {
        sqlite3_column_type(stmt, i) == SQLITE_NULL
    }
    private func date(_ stmt: OpaquePointer?, _ i: Int32) -> Date? {
        isNull(stmt, i) ? nil : Date(timeIntervalSince1970: double(stmt, i))
    }

    private func encodeJSON<T: Encodable>(_ value: T) -> String? {
        (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) }
    }
    private func decodeJSON<T: Decodable>(_ type: T.Type, _ json: String?) -> T? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? decoder.decode(type, from: data)
    }
}
