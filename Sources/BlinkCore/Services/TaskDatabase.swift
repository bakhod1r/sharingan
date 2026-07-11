import Foundation
import SQLite3

/// Thin SQLite persistence layer for tasks and categories, using the SQLite3 C
/// library bundled with macOS (no external package). TaskStore keeps its
/// in-memory `@Published` model and public API unchanged — only its load/save
/// internals route through here. Each save replaces the table contents inside a
/// single transaction, so a crash mid-write can never leave a half-written file
/// (the whole point of moving off the plain-JSON blob).
final class TaskDatabase {
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
            completedAt REAL
        );
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS categories (
            name TEXT PRIMARY KEY,
            colorHex TEXT NOT NULL,
            icon TEXT NOT NULL
        );
        """)
        // Databases created before the column shipped need it added in place
        // (CREATE IF NOT EXISTS won't touch an existing table).
        if !tableHasColumn("tasks", "completedAt") {
            exec("ALTER TABLE tasks ADD COLUMN completedAt REAL;")
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
        completedAt \
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
            t.priority = TaskPriority(rawValue: Int(int(stmt, 15))) ?? .none
            t.completedAt = date(stmt, 16)
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
            completedAt) \
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
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
