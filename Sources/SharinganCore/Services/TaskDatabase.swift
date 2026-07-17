import Foundation
import SQLite3

/// Thin SQLite persistence layer (SQLite3 C library bundled with macOS, no
/// external package). TaskStore keeps its in-memory `@Published` model and
/// public API unchanged — only its load/save internals route through here.
///
/// v3 schema (see docs/schema.md): every table carries an integer
/// `AUTOINCREMENT` surrogate `id`; business keys (a task's UUID, a category
/// name) are `UNIQUE` columns and all internal foreign keys point at the
/// surrogate. Per-task tags live in the `task_tags` junction and subtasks in an
/// EAV store, so no `tasks` column holds a JSON array any more. Saves upsert by
/// business key, so a task's `id` is stable across writes, and removed tasks
/// are left in place (never hard-deleted here).
final class TaskDatabase: SyncOutboxStorage {
    private var db: OpaquePointer?

    /// SQLite needs to copy bound strings/blobs (they're freed after the call).
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// attribute-name → id for `kind = 'subtask'`, cached after schema setup.
    private var subtaskAttr: [String: Int64] = [:]

    /// The audit columns every table carries. `created_at`/`updated_at` default
    /// to now so existing INSERTs need no change; `origin_device` defaults to
    /// empty for bookkeeping tables (only `tasks` stamps the real Mac name).
    /// Ends without a trailing comma — add one when a table constraint follows.
    private static let auditColumns = """
    created_at REAL NOT NULL DEFAULT (unixepoch()), \
    updated_at REAL NOT NULL DEFAULT (unixepoch()), \
    deleted_at REAL, \
    origin_device VARCHAR(255) NOT NULL DEFAULT ''
    """

    /// Subtask EAV attributes, with the value column each uses.
    private static let subtaskAttributes: [(name: String, kind: String)] = [
        ("title", "str"), ("is_done", "int"), ("estimated_pomodoros", "int"),
        ("pomodoros_done", "int"), ("pomodoro_kind", "str"), ("priority", "int"),
    ]

    init?(path: String) {
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            sqlite3_close(db); db = nil; return nil
        }
        exec("PRAGMA journal_mode=WAL;")
        exec("PRAGMA busy_timeout=3000;")
        exec("PRAGMA foreign_keys=ON;")
        setUp()
    }

    deinit { sqlite3_close(db) }

    // MARK: - Schema setup & migration

    /// Fresh databases get the v3 schema directly; v1 databases are migrated in
    /// place (data and sync state preserved); already-v3 databases just ensure
    /// the tables exist. Guarded by `PRAGMA user_version`.
    private func setUp() {
        if userVersion() >= 3 {
            createTables()
            ensureSchemaUpToDate()
        } else if tableHasColumn("tasks", "subtasks") {
            migrateFromV1()
        } else {
            createTables()
            setUserVersion(3)
        }
        loadAttributeIDs()
    }

    /// `CREATE TABLE IF NOT EXISTS` never alters an existing table, so a
    /// database already stamped v3 by an earlier build won't gain columns added
    /// later. This brings such a database up to the current shape in place:
    /// renames the intermediate `modified_at`/`trashed_at` columns and adds the
    /// four audit columns wherever they are missing. Idempotent.
    private func ensureSchemaUpToDate() {
        if tableHasColumn("tasks", "modified_at"), !tableHasColumn("tasks", "updated_at") {
            exec("ALTER TABLE tasks RENAME COLUMN modified_at TO updated_at;")
        }
        if tableHasColumn("tasks", "trashed_at"), !tableHasColumn("tasks", "deleted_at") {
            exec("ALTER TABLE tasks RENAME COLUMN trashed_at TO deleted_at;")
        }
        // Per-task content hash lets saveTasks skip rows that did not change,
        // so a persist rewrites one task's tags/subtasks instead of every task's.
        addColumnIfMissing("tasks", "content_hash", "VARCHAR(64)")
        // The issue number behind "T-42". 0 = never assigned; TaskStore
        // backfills those on load, oldest task first.
        addColumnIfMissing("tasks", "number", "INTEGER NOT NULL DEFAULT 0")
        let tables = ["tasks", "categories", "projects", "tags", "task_tags",
                      "templates", "focus_log", "eav_attributes", "eav_entities",
                      "eav_values", "sync_shadow", "sync_state", "sync_outbox"]
        for t in tables {
            // NOT NULL adds need a *constant* default (unixepoch() is rejected by
            // ALTER); 0 is a harmless sentinel for pre-existing audit rows.
            addColumnIfMissing(t, "created_at", "REAL NOT NULL DEFAULT 0")
            addColumnIfMissing(t, "updated_at", "REAL NOT NULL DEFAULT 0")
            addColumnIfMissing(t, "deleted_at", "REAL")
            addColumnIfMissing(t, "origin_device", "VARCHAR(255) NOT NULL DEFAULT ''")
        }
    }

    private func addColumnIfMissing(_ table: String, _ column: String, _ ddl: String) {
        guard !tableHasColumn(table, column) else { return }
        exec("ALTER TABLE \(table) ADD COLUMN \(column) \(ddl);")
    }

    private func createTables() {
        exec("""
        CREATE TABLE IF NOT EXISTS categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name VARCHAR(255) NOT NULL UNIQUE,
            color_hex VARCHAR(9) NOT NULL,
            icon VARCHAR(64) NOT NULL,
            \(Self.auditColumns)
        );
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS projects (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name VARCHAR(255) NOT NULL UNIQUE,
            color_hex VARCHAR(9) NOT NULL,
            icon VARCHAR(64) NOT NULL,
            \(Self.auditColumns)
        );
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS tags (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name VARCHAR(255) NOT NULL UNIQUE,
            \(Self.auditColumns)
        );
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            uuid VARCHAR(36) NOT NULL UNIQUE,
            title VARCHAR(500) NOT NULL,
            category_id INTEGER NOT NULL REFERENCES categories(id) ON UPDATE CASCADE,
            project_id INTEGER REFERENCES projects(id) ON DELETE SET NULL,
            is_done INTEGER NOT NULL DEFAULT 0 CHECK (is_done IN (0,1)),
            priority INTEGER NOT NULL DEFAULT 0 CHECK (priority >= 0),
            recurrence VARCHAR(32) NOT NULL DEFAULT 'none',
            pomodoro_kind VARCHAR(32),
            pomodoros_done INTEGER NOT NULL DEFAULT 0 CHECK (pomodoros_done >= 0),
            estimated_pomodoros INTEGER CHECK (estimated_pomodoros > 0),
            notes VARCHAR(4000) NOT NULL DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 0,
            due_at REAL,
            planned_at REAL,
            completed_at REAL,
            content_hash VARCHAR(64),
            number INTEGER NOT NULL DEFAULT 0 CHECK (number >= 0),
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            deleted_at REAL,
            origin_device VARCHAR(255) NOT NULL DEFAULT ''
        );
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_tasks_live ON tasks(is_done, sort_order) WHERE deleted_at IS NULL;")
        exec("CREATE INDEX IF NOT EXISTS idx_tasks_planned ON tasks(planned_at) WHERE deleted_at IS NULL;")
        exec("CREATE INDEX IF NOT EXISTS idx_tasks_due ON tasks(due_at) WHERE due_at IS NOT NULL;")
        exec("CREATE INDEX IF NOT EXISTS idx_tasks_project ON tasks(project_id) WHERE project_id IS NOT NULL;")
        exec("CREATE INDEX IF NOT EXISTS idx_tasks_deleted ON tasks(deleted_at) WHERE deleted_at IS NOT NULL;")
        exec("CREATE INDEX IF NOT EXISTS idx_tasks_origin ON tasks(origin_device);")

        exec("""
        CREATE TABLE IF NOT EXISTS task_tags (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
            tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
            \(Self.auditColumns),
            UNIQUE (task_id, tag_id)
        );
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_task_tags_tag ON task_tags(tag_id);")

        exec("""
        CREATE TABLE IF NOT EXISTS templates (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            uuid VARCHAR(36) NOT NULL UNIQUE,
            name VARCHAR(255) NOT NULL,
            json VARCHAR(8000) NOT NULL CHECK (json_valid(json)),
            \(Self.auditColumns)
        );
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS focus_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            day REAL NOT NULL,
            task_uuid VARCHAR(36) NOT NULL,
            subtask_uuid VARCHAR(36) NOT NULL DEFAULT '',
            title VARCHAR(500) NOT NULL,
            count INTEGER NOT NULL DEFAULT 0 CHECK (count >= 0),
            seconds REAL NOT NULL DEFAULT 0 CHECK (seconds >= 0),
            \(Self.auditColumns),
            UNIQUE (day, task_uuid, subtask_uuid)
        );
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_focus_log_day ON focus_log(day);")

        // EAV store for subtasks.
        exec("""
        CREATE TABLE IF NOT EXISTS eav_attributes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind VARCHAR(16) NOT NULL,
            name VARCHAR(64) NOT NULL,
            value_kind VARCHAR(8) NOT NULL CHECK (value_kind IN ('str','int','real')),
            \(Self.auditColumns),
            UNIQUE (kind, name)
        );
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS eav_entities (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            uuid VARCHAR(36) NOT NULL UNIQUE,
            kind VARCHAR(16) NOT NULL CHECK (kind IN ('subtask')),
            owner_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
            sort_order INTEGER NOT NULL DEFAULT 0,
            \(Self.auditColumns)
        );
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_eav_entities_owner ON eav_entities(owner_id, kind, sort_order);")
        exec("""
        CREATE TABLE IF NOT EXISTS eav_values (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entity_id INTEGER NOT NULL REFERENCES eav_entities(id) ON DELETE CASCADE,
            attribute_id INTEGER NOT NULL REFERENCES eav_attributes(id),
            value_kind VARCHAR(8) NOT NULL,
            value_str VARCHAR(4000),
            value_int INTEGER,
            value_real REAL,
            \(Self.auditColumns),
            UNIQUE (entity_id, attribute_id),
            CHECK (
                (value_kind = 'str'  AND value_str  IS NOT NULL AND value_int IS NULL AND value_real IS NULL) OR
                (value_kind = 'int'  AND value_int  IS NOT NULL AND value_str IS NULL AND value_real IS NULL) OR
                (value_kind = 'real' AND value_real IS NOT NULL AND value_str IS NULL AND value_int  IS NULL)
            )
        );
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_eav_values_lookup ON eav_values(attribute_id, entity_id);")

        // Sync bookkeeping. sync_shadow is what saves are diffed against —
        // without it a DELETE-all + re-INSERT is indistinguishable from "the
        // user deleted everything".
        exec("""
        CREATE TABLE IF NOT EXISTS sync_shadow (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            record_type VARCHAR(64) NOT NULL,
            record_name VARCHAR(255) NOT NULL,
            content_hash VARCHAR(64) NOT NULL,
            system_fields BLOB,
            \(Self.auditColumns),
            UNIQUE (record_type, record_name)
        );
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS sync_state (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            key VARCHAR(64) NOT NULL UNIQUE,
            value BLOB NOT NULL,
            \(Self.auditColumns)
        );
        """)
        // Durable push queue (see SyncOutbox). Deliberately NOT wiped by
        // resetSyncState(): a tombstone here is the only record that a delete
        // ever happened once the shadow is gone.
        exec("""
        CREATE TABLE IF NOT EXISTS sync_outbox (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            record_type VARCHAR(64) NOT NULL,
            record_name VARCHAR(255) NOT NULL,
            kind VARCHAR(16) NOT NULL CHECK (kind IN ('save','delete')),
            enqueued_at REAL NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            next_attempt_at REAL NOT NULL,
            \(Self.auditColumns),
            UNIQUE (record_type, record_name)
        );
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_outbox_due ON sync_outbox(next_attempt_at);")

        seedAttributes()
    }

    private func seedAttributes() {
        for a in Self.subtaskAttributes {
            run("INSERT OR IGNORE INTO eav_attributes (kind, name, value_kind) VALUES ('subtask',?,?);") {
                bindText($0, 1, a.name); bindText($0, 2, a.kind)
            }
        }
    }

    private func loadAttributeIDs() {
        subtaskAttr.removeAll()
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT name, id FROM eav_attributes WHERE kind='subtask';", -1, &stmt, nil) == SQLITE_OK
        else { return }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = text(stmt, 0) { subtaskAttr[name] = int(stmt, 1) }
        }
    }

    // MARK: v1 → v3 migration

    /// Reads every v1 collection into memory, drops the v1 tables, builds the
    /// v3 schema, then re-persists — so tasks, categories, tags, templates,
    /// focus log and all sync bookkeeping survive the reshape unchanged.
    private func migrateFromV1() {
        ensureV1Columns()
        let tasks = readV1Tasks()
        let categories = readV1Named("categories")
        let projects = readV1Named("projects")
        let tags = readV1Tags()
        let templates = readV1Templates()
        let focus = loadFocusLogV1()
        let shadows = readV1Shadows()
        let states = readV1States()
        let outbox = loadOutbox()   // v1 sync_outbox already matches v3 columns

        // Everything below is one atomic unit: if the process dies partway, the
        // dropped v1 tables are restored on reopen rather than lost.
        transaction {
            for t in ["tasks", "categories", "projects", "tags", "templates",
                      "focus_log", "sync_shadow", "sync_state", "sync_outbox"] {
                exec("DROP TABLE IF EXISTS \(t);")
            }
            createTables()
            loadAttributeIDs()

            saveCategories(categories)
            saveProjects(projects)
            saveTags(tags)
            saveTasks(tasks)
            saveTemplates(templates)
            saveFocusLog(focus)
            for s in shadows { upsertShadow(recordType: s.type, entry: s.entry) }
            for s in states { setSyncStateValue(s.key, s.value) }
            for op in outbox { upsertOutbox(op) }
            return true
        }

        setUserVersion(3)
    }

    /// Some v1 columns arrived via ALTER; make sure they exist before we read.
    private func ensureV1Columns() {
        for (col, ddl) in [("completedAt", "REAL"), ("pomodoroKind", "TEXT"),
                           ("modifiedAt", "REAL"), ("trashedAt", "REAL")]
        where !tableHasColumn("tasks", col) {
            exec("ALTER TABLE tasks ADD COLUMN \(col) \(ddl);")
        }
        exec("UPDATE tasks SET modifiedAt = createdAt WHERE modifiedAt IS NULL;")
    }

    private func readV1Tasks() -> [TaskItem] {
        var out: [TaskItem] = []
        let sql = """
        SELECT id,title,category,tags,isDone,pomodorosDone,createdAt,dueDate,\
        sortOrder,estimatedPomodoros,plannedDate,notes,subtasks,recurrence,project,priority,\
        completedAt,pomodoroKind,modifiedAt,trashedAt FROM tasks;
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

    private func readV1Named(_ table: String) -> [TaskCategory] {
        var out: [TaskCategory] = []
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT name,colorHex,icon FROM \(table);", -1, &stmt, nil) == SQLITE_OK
        else { return out }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(TaskCategory(name: text(stmt, 0) ?? "",
                                    colorHex: text(stmt, 1) ?? "#9AA3AF",
                                    icon: text(stmt, 2) ?? "folder.fill"))
        }
        return out
    }

    private func readV1Tags() -> [String] {
        var out: [String] = []
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT name FROM tags;", -1, &stmt, nil) == SQLITE_OK else { return out }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW { if let n = text(stmt, 0) { out.append(n) } }
        return out
    }

    private func readV1Templates() -> [TaskTemplate] {
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

    private func loadFocusLogV1() -> [FocusLogEntry] {
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

    private struct ShadowRow { let type: String; let entry: ShadowEntry }
    private struct StateRow { let key: String; let value: Data }

    private func readV1Shadows() -> [ShadowRow] {
        var out: [ShadowRow] = []
        var stmt: OpaquePointer?
        let sql = "SELECT record_type, record_name, content_hash, system_fields FROM sync_shadow;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return out }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let type = text(stmt, 0), let name = text(stmt, 1), let hash = text(stmt, 2) else { continue }
            var fields: Data?
            if let blob = sqlite3_column_blob(stmt, 3) {
                fields = Data(bytes: blob, count: Int(sqlite3_column_bytes(stmt, 3)))
            }
            out.append(ShadowRow(type: type,
                                 entry: ShadowEntry(recordName: name, contentHash: hash, systemFields: fields)))
        }
        return out
    }

    private func readV1States() -> [StateRow] {
        var out: [StateRow] = []
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT key, value FROM sync_state;", -1, &stmt, nil) == SQLITE_OK else { return out }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let key = text(stmt, 0), let blob = sqlite3_column_blob(stmt, 1) else { continue }
            out.append(StateRow(key: key, value: Data(bytes: blob, count: Int(sqlite3_column_bytes(stmt, 1)))))
        }
        return out
    }

    // MARK: - Tasks

    func loadTasks() -> [TaskItem] {
        let tagsByTask = loadTaskTags()
        let subtasksByTask = loadSubtasks()
        var out: [TaskItem] = []
        let sql = """
        SELECT t.id, t.uuid, t.title, c.name, p.name, t.is_done, t.pomodoros_done, t.created_at,\
        t.due_at, t.sort_order, t.estimated_pomodoros, t.planned_at, t.notes, t.recurrence,\
        t.priority, t.completed_at, t.pomodoro_kind, t.updated_at, t.deleted_at, t.origin_device,\
        t.number
        FROM tasks t
        JOIN categories c ON c.id = t.category_id
        LEFT JOIN projects p ON p.id = t.project_id
        ORDER BY t.sort_order;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return out }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            let rowID = int(stmt, 0)
            guard let uuid = text(stmt, 1), let id = UUID(uuidString: uuid) else { continue }
            var t = TaskItem(title: text(stmt, 2) ?? "", category: text(stmt, 3) ?? "")
            t.id = id
            t.tags = tagsByTask[rowID] ?? []
            t.project = isNull(stmt, 4) ? nil : text(stmt, 4)
            t.isDone = int(stmt, 5) != 0
            t.pomodorosDone = Int(int(stmt, 6))
            t.createdAt = Date(timeIntervalSince1970: double(stmt, 7))
            t.dueDate = date(stmt, 8)
            t.sortOrder = Int(int(stmt, 9))
            t.estimatedPomodoros = isNull(stmt, 10) ? nil : Int(int(stmt, 10))
            t.plannedDate = date(stmt, 11)
            t.notes = text(stmt, 12) ?? ""
            t.recurrence = Recurrence(string: text(stmt, 13) ?? "none")
            t.priority = TaskPriority(rawValue: Int(int(stmt, 14)))
            t.completedAt = date(stmt, 15)
            t.pomodoroKind = text(stmt, 16).flatMap(PomodoroKind.init(rawValue:))
            t.modifiedAt = date(stmt, 17) ?? t.createdAt
            t.trashedAt = date(stmt, 18)
            if let origin = text(stmt, 19), !origin.isEmpty { t.originDevice = origin }
            t.number = Int(int(stmt, 20))
            t.subtasks = subtasksByTask[rowID] ?? []
            out.append(t)
        }
        return out
    }

    private func loadTaskTags() -> [Int64: [String]] {
        var out: [Int64: [String]] = [:]
        var stmt: OpaquePointer?
        let sql = "SELECT tt.task_id, tg.name FROM task_tags tt JOIN tags tg ON tg.id = tt.tag_id ORDER BY tt.id;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return out }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = text(stmt, 1) { out[int(stmt, 0), default: []].append(name) }
        }
        return out
    }

    private func loadSubtasks() -> [Int64: [Subtask]] {
        var out: [Int64: [Subtask]] = [:]
        let sql = """
        SELECT e.owner_id, e.uuid,
            MAX(CASE WHEN a.name='title'               THEN v.value_str END),
            MAX(CASE WHEN a.name='is_done'             THEN v.value_int END),
            MAX(CASE WHEN a.name='estimated_pomodoros' THEN v.value_int END),
            MAX(CASE WHEN a.name='pomodoros_done'      THEN v.value_int END),
            MAX(CASE WHEN a.name='pomodoro_kind'       THEN v.value_str END),
            MAX(CASE WHEN a.name='priority'            THEN v.value_int END)
        FROM eav_entities e
        JOIN eav_values v ON v.entity_id = e.id
        JOIN eav_attributes a ON a.id = v.attribute_id
        WHERE e.kind = 'subtask'
        GROUP BY e.id
        ORDER BY e.owner_id, e.sort_order;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return out }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            let owner = int(stmt, 0)
            let id = text(stmt, 1).flatMap(UUID.init(uuidString:)) ?? UUID()
            var s = Subtask(id: id, title: text(stmt, 2) ?? "")
            s.isDone = int(stmt, 3) != 0
            s.estimatedPomodoros = isNull(stmt, 4) ? nil : Int(int(stmt, 4))
            s.pomodorosDone = Int(int(stmt, 5))
            s.pomodoroKind = text(stmt, 6).flatMap(PomodoroKind.init(rawValue:))
            s.priority = TaskPriority(rawValue: Int(int(stmt, 7)))
            out[owner, default: []].append(s)
        }
        return out
    }

    /// Persists issue numbers the store just backfilled onto rows that predate
    /// numbering. This cannot ride along with `saveTasks`: `number` is outside
    /// `contentHash` (see SyncableConformances), so a backfilled task reads as
    /// unchanged there and its row would be skipped — the number would be
    /// recomputed from scratch on every launch and never stored, drifting the
    /// moment a task is deleted. `AND number=0` keeps the write once-only, and
    /// touching no other column leaves `updated_at` — and sync — alone.
    func backfillNumbers(_ tasks: [TaskItem]) {
        let numbered = tasks.filter { $0.number > 0 }
        guard !numbered.isEmpty else { return }
        transaction {
            for t in numbered {
                let sql = "UPDATE tasks SET number=? WHERE uuid=? AND number=0;"
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { continue }
                sqlite3_bind_int64(stmt, 1, Int64(t.number))
                bindText(stmt, 2, t.id.uuidString)
                _ = sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
            return true
        }
    }

    /// Upserts each task by UUID (its `id` stays stable) and rebuilds its tag
    /// and subtask rows — but only for tasks whose `content_hash` changed since
    /// the last save. An unchanged task is skipped entirely, so a normal edit
    /// rewrites one task's children instead of every task's, keeping the write
    /// lock held for milliseconds rather than long enough to collide with a
    /// background sync write on another connection. Tasks absent from `tasks`
    /// are left untouched — removed tasks are never hard-deleted here.
    func saveTasks(_ tasks: [TaskItem]) {
        let stored = loadTaskHashes()
        // Nothing changed and nothing to sweep → don't even open a transaction.
        let changed = tasks.filter { stored[$0.id.uuidString] != $0.contentHash }
        guard !changed.isEmpty || tasks.count != stored.count else { return }

        transaction {
            for t in changed {
                ensureCategory(t.category)
                if let p = t.project, !p.isEmpty { ensureProject(p) }
                for tag in t.tags { ensureTag(tag) }

                let sql = """
                INSERT INTO tasks
                (uuid,title,category_id,project_id,is_done,priority,recurrence,pomodoro_kind,\
                pomodoros_done,estimated_pomodoros,notes,sort_order,due_at,planned_at,created_at,\
                updated_at,completed_at,deleted_at,origin_device,content_hash,number)
                VALUES (?,?,\
                (SELECT id FROM categories WHERE name=?),\
                (SELECT id FROM projects WHERE name=?),\
                ?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(uuid) DO UPDATE SET
                    title=excluded.title, category_id=excluded.category_id,
                    project_id=excluded.project_id, is_done=excluded.is_done,
                    priority=excluded.priority, recurrence=excluded.recurrence,
                    pomodoro_kind=excluded.pomodoro_kind, pomodoros_done=excluded.pomodoros_done,
                    estimated_pomodoros=excluded.estimated_pomodoros, notes=excluded.notes,
                    sort_order=excluded.sort_order, due_at=excluded.due_at,
                    planned_at=excluded.planned_at, updated_at=excluded.updated_at,
                    completed_at=excluded.completed_at, deleted_at=excluded.deleted_at,
                    content_hash=excluded.content_hash,
                    -- Write-once: an unnumbered row takes the number the store
                    -- backfilled, but a row that already has one keeps it, so no
                    -- later write (a remote merge, a bad caller) can renumber a
                    -- task out from under the report rows pointing at it.
                    number=CASE WHEN tasks.number=0 THEN excluded.number ELSE tasks.number END;
                    -- created_at and origin_device are immutable: never updated.
                """
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
                bindText(stmt, 1, t.id.uuidString)
                bindText(stmt, 2, t.title)
                bindText(stmt, 3, t.category)
                if let p = t.project, !p.isEmpty { bindText(stmt, 4, p) } else { sqlite3_bind_null(stmt, 4) }
                sqlite3_bind_int(stmt, 5, t.isDone ? 1 : 0)
                sqlite3_bind_int64(stmt, 6, Int64(t.priority.rawValue))
                bindText(stmt, 7, t.recurrence.stringValue)
                if let k = t.pomodoroKind { bindText(stmt, 8, k.rawValue) } else { sqlite3_bind_null(stmt, 8) }
                sqlite3_bind_int64(stmt, 9, Int64(t.pomodorosDone))
                bindOptInt(stmt, 10, t.estimatedPomodoros)
                bindText(stmt, 11, t.notes)
                sqlite3_bind_int64(stmt, 12, Int64(t.sortOrder))
                bindDate(stmt, 13, t.dueDate)
                bindDate(stmt, 14, t.plannedDate)
                sqlite3_bind_double(stmt, 15, t.createdAt.timeIntervalSince1970)
                sqlite3_bind_double(stmt, 16, t.modifiedAt.timeIntervalSince1970)   // updated_at
                bindDate(stmt, 17, t.completedAt)
                bindDate(stmt, 18, t.trashedAt)                                     // deleted_at
                bindText(stmt, 19, t.originDevice)
                bindText(stmt, 20, t.contentHash)
                sqlite3_bind_int64(stmt, 21, Int64(t.number))
                let ok = sqlite3_step(stmt) == SQLITE_DONE
                sqlite3_finalize(stmt)
                guard ok else { return false }

                guard let taskID = queryInt64("SELECT id FROM tasks WHERE uuid=?;", { bindText($0, 1, t.id.uuidString) })
                else { return false }
                guard writeTaskTags(taskID, t.tags), writeSubtasks(taskID, t.subtasks) else { return false }
            }
            sweepEmptiedTrash(keeping: tasks.map(\.id.uuidString))
            return true
        }
    }

    /// uuid → last-persisted content hash, for the changed-only save fast path.
    private func loadTaskHashes() -> [String: String] {
        var out: [String: String] = [:]
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT uuid, content_hash FROM tasks WHERE content_hash IS NOT NULL;",
                                 -1, &stmt, nil) == SQLITE_OK else { return out }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let u = text(stmt, 0), let h = text(stmt, 1) { out[u] = h }
        }
        return out
    }

    /// A live task dropped from the incoming set is left in place, but a task
    /// that was in Trash and is now gone (the user emptied it) is hard-deleted —
    /// its tags and subtasks follow through the ON DELETE CASCADE.
    private func sweepEmptiedTrash(keeping uuids: [String]) {
        let placeholders = uuids.isEmpty ? "''" : uuids.map { _ in "?" }.joined(separator: ",")
        run("DELETE FROM tasks WHERE deleted_at IS NOT NULL AND uuid NOT IN (\(placeholders));") { stmt in
            for (i, u) in uuids.enumerated() { bindText(stmt, Int32(i + 1), u) }
        }
    }

    private func writeTaskTags(_ taskID: Int64, _ tags: [String]) -> Bool {
        run("DELETE FROM task_tags WHERE task_id=?;") { sqlite3_bind_int64($0, 1, taskID) }
        for tag in tags {
            var ok = false
            run("INSERT OR IGNORE INTO task_tags (task_id, tag_id) SELECT ?, id FROM tags WHERE name=?;") {
                sqlite3_bind_int64($0, 1, taskID); bindText($0, 2, tag); ok = true
            }
            if !ok { return false }
        }
        return true
    }

    private func writeSubtasks(_ taskID: Int64, _ subtasks: [Subtask]) -> Bool {
        run("DELETE FROM eav_entities WHERE owner_id=? AND kind='subtask';") { sqlite3_bind_int64($0, 1, taskID) }
        for (i, s) in subtasks.enumerated() {
            var stmt: OpaquePointer?
            let sql = "INSERT INTO eav_entities (uuid, kind, owner_id, sort_order) VALUES (?,'subtask',?,?);"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
            bindText(stmt, 1, s.id.uuidString)
            sqlite3_bind_int64(stmt, 2, taskID)
            sqlite3_bind_int64(stmt, 3, Int64(i))
            let ok = sqlite3_step(stmt) == SQLITE_DONE
            sqlite3_finalize(stmt)
            guard ok else { return false }
            let eid = sqlite3_last_insert_rowid(db)

            setValueStr(eid, "title", s.title)
            setValueInt(eid, "is_done", s.isDone ? 1 : 0)
            setValueInt(eid, "pomodoros_done", Int64(s.pomodorosDone))
            setValueInt(eid, "priority", Int64(s.priority.rawValue))
            if let est = s.estimatedPomodoros { setValueInt(eid, "estimated_pomodoros", Int64(est)) }
            if let k = s.pomodoroKind { setValueStr(eid, "pomodoro_kind", k.rawValue) }
        }
        return true
    }

    private func setValueInt(_ eid: Int64, _ attr: String, _ value: Int64) {
        guard let aid = subtaskAttr[attr] else { return }
        run("INSERT INTO eav_values (entity_id, attribute_id, value_kind, value_int) VALUES (?,?,'int',?);") {
            sqlite3_bind_int64($0, 1, eid); sqlite3_bind_int64($0, 2, aid); sqlite3_bind_int64($0, 3, value)
        }
    }
    private func setValueStr(_ eid: Int64, _ attr: String, _ value: String) {
        guard let aid = subtaskAttr[attr] else { return }
        run("INSERT INTO eav_values (entity_id, attribute_id, value_kind, value_str) VALUES (?,?,'str',?);") {
            sqlite3_bind_int64($0, 1, eid); sqlite3_bind_int64($0, 2, aid); bindText($0, 3, value)
        }
    }

    private func ensureCategory(_ name: String) {
        let preset = TaskCategory.presets.first { $0.name == name }
        run("INSERT OR IGNORE INTO categories (name, color_hex, icon) VALUES (?,?,?);") {
            bindText($0, 1, name)
            bindText($0, 2, preset?.colorHex ?? "#9AA3AF")
            bindText($0, 3, preset?.icon ?? "folder.fill")
        }
    }
    private func ensureProject(_ name: String) {
        run("INSERT OR IGNORE INTO projects (name, color_hex, icon) VALUES (?,'#9AA3AF','folder.fill');") {
            bindText($0, 1, name)
        }
    }
    private func ensureTag(_ name: String) {
        run("INSERT OR IGNORE INTO tags (name) VALUES (?);") { bindText($0, 1, name) }
    }

    // MARK: - Categories

    func loadCategories() -> [TaskCategory] { loadNamed("categories") }
    func loadProjects() -> [TaskCategory] { loadNamed("projects") }

    private func loadNamed(_ table: String) -> [TaskCategory] {
        var out: [TaskCategory] = []
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT name,color_hex,icon FROM \(table) ORDER BY id;", -1, &stmt, nil) == SQLITE_OK
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
            for c in cats {
                run("""
                INSERT INTO categories (name,color_hex,icon) VALUES (?,?,?)
                ON CONFLICT(name) DO UPDATE SET color_hex=excluded.color_hex, icon=excluded.icon;
                """) { bindText($0, 1, c.name); bindText($0, 2, c.colorHex); bindText($0, 3, c.icon) }
            }
            // Remove categories no longer present, but only if no task references
            // them (the FK is NOT NULL, so a referenced category must survive).
            deleteMissingNamed("categories", keep: cats.map(\.name),
                               guardSQL: "id NOT IN (SELECT category_id FROM tasks)")
            return true
        }
    }

    func saveProjects(_ projects: [TaskCategory]) {
        transaction {
            for p in projects {
                run("""
                INSERT INTO projects (name,color_hex,icon) VALUES (?,?,?)
                ON CONFLICT(name) DO UPDATE SET color_hex=excluded.color_hex, icon=excluded.icon;
                """) { bindText($0, 1, p.name); bindText($0, 2, p.colorHex); bindText($0, 3, p.icon) }
            }
            // project_id is ON DELETE SET NULL, so dropping a referenced project
            // is safe — referencing tasks simply lose their project.
            deleteMissingNamed("projects", keep: projects.map(\.name), guardSQL: nil)
            return true
        }
    }

    private func deleteMissingNamed(_ table: String, keep: [String], guardSQL: String?) {
        let placeholders = keep.isEmpty ? "''" : keep.map { _ in "?" }.joined(separator: ",")
        var sql = "DELETE FROM \(table) WHERE name NOT IN (\(placeholders))"
        if let guardSQL { sql += " AND \(guardSQL)" }
        sql += ";"
        run(sql) { stmt in
            for (i, name) in keep.enumerated() { bindText(stmt, Int32(i + 1), name) }
        }
    }

    // MARK: - Tags

    /// The precreated-but-unused registry (sidebar "+"): catalogue tags that no
    /// task references yet. Tags born from typing `#tag` graduate out of this
    /// list the moment a task links them.
    func loadTags() -> [String] {
        var out: [String] = []
        var stmt: OpaquePointer?
        let sql = "SELECT name FROM tags WHERE id NOT IN (SELECT tag_id FROM task_tags) ORDER BY id;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return out }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW { if let n = text(stmt, 0) { out.append(n) } }
        return out
    }

    func saveTags(_ tags: [String]) {
        transaction {
            for t in tags { ensureTag(t) }
            // Drop precreated tags the user removed — but never one a task uses.
            deleteMissingNamed("tags", keep: tags,
                               guardSQL: "id NOT IN (SELECT tag_id FROM task_tags)")
            return true
        }
    }

    // MARK: - Templates

    func loadTemplates() -> [TaskTemplate] {
        var out: [TaskTemplate] = []
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT uuid,name,json FROM templates ORDER BY id;", -1, &stmt, nil) == SQLITE_OK
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
            for t in templates {
                guard let json = encodeJSON(t.item) else { return false }
                run("""
                INSERT INTO templates (uuid,name,json) VALUES (?,?,?)
                ON CONFLICT(uuid) DO UPDATE SET name=excluded.name, json=excluded.json;
                """) { bindText($0, 1, t.id.uuidString); bindText($0, 2, t.name); bindText($0, 3, json) }
            }
            deleteMissingNamed("templates", keep: templates.map(\.id.uuidString), guardSQL: nil)
            return true
        }
    }

    // MARK: - Focus log

    func loadFocusLog() -> [FocusLogEntry] {
        var out: [FocusLogEntry] = []
        var stmt: OpaquePointer?
        let sql = "SELECT day, task_uuid, subtask_uuid, title, count, seconds FROM focus_log;"
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
            for e in entries {
                run("""
                INSERT INTO focus_log (day, task_uuid, subtask_uuid, title, count, seconds)
                VALUES (?,?,?,?,?,?)
                ON CONFLICT(day, task_uuid, subtask_uuid) DO UPDATE SET
                    title=excluded.title, count=excluded.count, seconds=excluded.seconds;
                """) {
                    sqlite3_bind_double($0, 1, e.day.timeIntervalSince1970)
                    bindText($0, 2, e.taskID.uuidString)
                    bindText($0, 3, e.subtaskID?.uuidString ?? "")
                    bindText($0, 4, e.title)
                    sqlite3_bind_int64($0, 5, Int64(e.count))
                    sqlite3_bind_double($0, 6, e.seconds)
                }
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
        run("DELETE FROM sync_shadow WHERE record_type = ? AND record_name = ?;") {
            bindText($0, 1, recordType); bindText($0, 2, recordName)
        }
    }

    /// Wipes shadow + engine state — used when the iCloud account changes, so
    /// the next sync re-establishes from scratch instead of merging one person's
    /// records into another's. The outbox is deliberately left intact.
    func resetSyncState() {
        transaction { exec("DELETE FROM sync_shadow;") && exec("DELETE FROM sync_state;") }
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
        let sql = "INSERT INTO sync_state (key, value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
        var stmt: OpaquePointer?
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
        run("DELETE FROM sync_outbox WHERE record_type = ? AND record_name = ?;") {
            bindText($0, 1, recordType); bindText($0, 2, recordName)
        }
    }

    func clearOutbox() { exec("DELETE FROM sync_outbox;") }

    // MARK: - Low-level helpers

    private func userVersion() -> Int64 {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : 0
    }
    private func setUserVersion(_ v: Int) { exec("PRAGMA user_version = \(v);") }

    /// True when `PRAGMA table_info` lists the column — used to detect a v1
    /// database (the `tasks.subtasks` JSON column exists only there).
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

    @discardableResult
    private func exec(_ sql: String) -> Bool { sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK }

    /// Prepares `sql`, lets `binds` bind its parameters, steps once, finalizes.
    private func run(_ sql: String, _ binds: (OpaquePointer?) -> Void) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        binds(stmt)
        _ = sqlite3_step(stmt)
    }

    /// Prepares `sql`, binds, and returns the first column of the first row.
    private func queryInt64(_ sql: String, _ binds: (OpaquePointer?) -> Void) -> Int64? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        binds(stmt)
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : nil
    }

    private var txDepth = 0

    /// Runs `body` atomically, rolling back if it reports failure. Reentrant:
    /// a nested call uses a SAVEPOINT so the migration can wrap many inner
    /// `saveX` calls (each of which opens its own `transaction`) in one
    /// all-or-nothing unit — a crash mid-migration then leaves the whole thing
    /// uncommitted and SQLite restores the pre-migration database on reopen.
    private func transaction(_ body: () -> Bool) {
        let nested = txDepth > 0
        let name = "sp\(txDepth)"
        guard exec(nested ? "SAVEPOINT \(name);" : "BEGIN;") else { return }
        txDepth += 1
        let ok = body()
        txDepth -= 1
        if ok {
            exec(nested ? "RELEASE \(name);" : "COMMIT;")
        } else if nested {
            exec("ROLLBACK TO \(name);"); exec("RELEASE \(name);")
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
    private func bindOptInt(_ stmt: OpaquePointer?, _ i: Int32, _ value: Int?) {
        if let value { sqlite3_bind_int64(stmt, i, Int64(value)) } else { sqlite3_bind_null(stmt, i) }
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
