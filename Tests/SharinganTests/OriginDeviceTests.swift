import Testing
import Foundation
import SQLite3
@testable import SharinganCore

/// Covers `TaskItem.originDevice`: its immutable persistence through the
/// `tasks` upsert, the four audit columns (`created_at`, `updated_at`,
/// `deleted_at`, `origin_device`) present on every table, `TaskStore.knownDevices`,
/// and that trashed tasks stop leaking into the planned/weekly/category/overdue
/// queries.
@Suite("Origin device & trashed-task filtering")
struct OriginDeviceTests {

    // MARK: - Helpers

    private func freshPath() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("origindev-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("blink.sqlite").path
    }

    private func openRaw(_ path: String) -> OpaquePointer? {
        var db: OpaquePointer?
        _ = sqlite3_open(path, &db)
        return db
    }

    /// Scalar-integer query against a raw handle (physical-schema asserts).
    private func scalar(_ db: OpaquePointer?, _ sql: String) -> Int64 {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return -1 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : -1
    }

    /// Scalar-text query against a raw handle.
    private func scalarText(_ db: OpaquePointer?, _ sql: String) -> String? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: c)
    }

    // MARK: - originDevice round-trips and is immutable on update

    @Test func originDevicePersistsAndIsImmutableOnUpdate() throws {
        let path = try freshPath()
        var task = TaskItem(title: "Report", category: "Work", originDevice: "Mac-A")

        do {
            let db = try #require(TaskDatabase(path: path))
            db.saveTasks([task])
        }

        // Round-trips on the first save.
        let firstLoad = try #require(TaskDatabase(path: path)).loadTasks()
        #expect(firstLoad.count == 1)
        #expect(firstLoad.first?.originDevice == "Mac-A")

        // Re-saving the SAME task (same uuid) with a mutated origin must NOT
        // overwrite the stored value — origin is immutable through the upsert.
        task.title = "Report (edited)"
        task.originDevice = "Mac-B"
        do {
            let db = try #require(TaskDatabase(path: path))
            db.saveTasks([task])
        }

        let reloaded = try #require(TaskDatabase(path: path)).loadTasks()
        #expect(reloaded.count == 1)
        let t = try #require(reloaded.first)
        #expect(t.title == "Report (edited)")   // mutable field DID update
        #expect(t.originDevice == "Mac-A")       // immutable field did NOT

        // Confirm the physical column value directly.
        let raw = openRaw(path)
        defer { sqlite3_close(raw) }
        #expect(scalarText(raw, "SELECT origin_device FROM tasks;") == "Mac-A")
    }

    @Test func createdAtIsAlsoImmutableOnUpdate() throws {
        let path = try freshPath()
        let created = Date(timeIntervalSince1970: 1_000_000)
        var task = TaskItem(title: "T", category: "Work", createdAt: created)

        let db = try #require(TaskDatabase(path: path))
        db.saveTasks([task])

        // Mutate created_at in the in-memory struct and re-save.
        task.createdAt = Date(timeIntervalSince1970: 2_000_000)
        db.saveTasks([task])

        let raw = openRaw(path)
        defer { sqlite3_close(raw) }
        // created_at stays the original; the upsert never touches it.
        #expect(Int64(scalar(raw, "SELECT CAST(created_at AS INTEGER) FROM tasks;")) == 1_000_000)
    }

    // MARK: - Audit columns on every table

    @Test func everyTableHasTheFourAuditColumns() throws {
        let path = try freshPath()
        _ = try #require(TaskDatabase(path: path))
        let raw = openRaw(path)
        defer { sqlite3_close(raw) }
        let tables = ["tasks", "categories", "projects", "tags", "task_tags",
                      "templates", "focus_log", "eav_attributes", "eav_entities",
                      "eav_values", "sync_shadow", "sync_state", "sync_outbox"]
        let audit = ["created_at", "updated_at", "deleted_at", "origin_device"]
        for table in tables {
            for column in audit {
                let present = scalar(raw, """
                SELECT COUNT(*) FROM pragma_table_info('\(table)') WHERE name='\(column)';
                """)
                #expect(present == 1, "\(table) must have an \(column) column")
            }
        }
    }

    // MARK: - TaskStore.knownDevices

    @MainActor private func freshStore() throws -> TaskStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("origindev-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return TaskStore(fileURL: dir.appendingPathComponent("t.sqlite"))
    }

    @MainActor @Test func knownDevicesAreDistinctNonEmptyMostFrequentFirst() throws {
        let store = try freshStore()
        // Mac-A: three tasks, Mac-B: one, plus one blank origin (excluded).
        store.insert(TaskItem(title: "a1", category: "Work", originDevice: "Mac-A"))
        store.insert(TaskItem(title: "a2", category: "Work", originDevice: "Mac-A"))
        store.insert(TaskItem(title: "a3", category: "Work", originDevice: "Mac-A"))
        store.insert(TaskItem(title: "b1", category: "Work", originDevice: "Mac-B"))
        store.insert(TaskItem(title: "blank", category: "Work", originDevice: ""))

        #expect(store.knownDevices == ["Mac-A", "Mac-B"])
    }

    @MainActor @Test func knownDevicesExcludesTrashedTasks() throws {
        let store = try freshStore()
        store.insert(TaskItem(title: "keep", category: "Work", originDevice: "Mac-A"))
        store.insert(TaskItem(title: "doomed", category: "Work", originDevice: "Mac-Z"))
        let doomedID = try #require(store.tasks.first { $0.title == "doomed" }).id

        store.delete(doomedID)   // soft-delete → trashed
        // Mac-Z's only task is trashed, so it drops out of the device list.
        #expect(store.knownDevices == ["Mac-A"])
    }

    // MARK: - Trashed tasks no longer leak into normal views

    @MainActor @Test func trashedTasksVanishFromPlannedWeeklyGroupedAndOverdue() throws {
        let store = try freshStore()
        let day = Calendar.current.startOfDay(for: Date())

        // A planned task, an unscheduled task, and an overdue task — one of each
        // gets trashed, plus a live control that must survive every query.
        store.insert(TaskItem(title: "Planned-doomed", category: "Work"))
        store.insert(TaskItem(title: "Planned-live", category: "Work"))
        store.insert(TaskItem(title: "Backlog-doomed", category: "Work"))
        store.insert(TaskItem(title: "Overdue-doomed", category: "Work",
                              dueDate: Date().addingTimeInterval(-3600)))

        func id(_ title: String) throws -> UUID {
            try #require(store.tasks.first { $0.title == title }).id
        }

        try store.setPlannedDate(id("Planned-doomed"), day)
        try store.setPlannedDate(id("Planned-live"), day)

        // Baselines before trashing.
        #expect(store.tasksPlanned(on: day).map(\.title).sorted() == ["Planned-doomed", "Planned-live"])
        #expect(store.overdueCount() == 1)
        #expect(store.unscheduledTasks.contains { $0.title == "Backlog-doomed" })
        #expect(store.grouped().flatMap(\.items).contains { $0.title == "Planned-doomed" })

        // Trash the doomed ones.
        try store.delete(id("Planned-doomed"))
        try store.delete(id("Backlog-doomed"))
        try store.delete(id("Overdue-doomed"))

        // Planned query: only the live planned task remains.
        #expect(store.tasksPlanned(on: day).map(\.title) == ["Planned-live"])
        // Backlog (unscheduled) no longer shows the trashed one.
        #expect(!store.unscheduledTasks.contains { $0.title == "Backlog-doomed" })
        // Category grouping excludes every trashed task.
        let groupedTitles = Set(store.grouped().flatMap(\.items).map(\.title))
        #expect(!groupedTitles.contains("Planned-doomed"))
        #expect(!groupedTitles.contains("Backlog-doomed"))
        #expect(!groupedTitles.contains("Overdue-doomed"))
        #expect(groupedTitles.contains("Planned-live"))
        // Overdue count drops the trashed overdue task.
        #expect(store.overdueCount() == 0)
    }
}
