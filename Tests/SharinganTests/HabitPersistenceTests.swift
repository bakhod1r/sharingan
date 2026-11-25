import XCTest
import SQLite3
@testable import SharinganCore

final class HabitDatabaseTests: XCTestCase {
    private func freshPath() throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("habitdb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("blink.sqlite").path
    }
    private let habit = TaskHabit(schedule: .weekdays([2, 4]), mode: .pomodoro(target: 3),
                                  startDay: Date(timeIntervalSince1970: 1_700_000_000))

    func testHabitRoundTrips() throws {
        let path = try freshPath()
        var t = TaskItem(title: "Run", category: "Work"); t.habit = habit
        do {
            let db = try XCTUnwrap(TaskDatabase(path: path))
            db.saveTasks([t, TaskItem(title: "Plain", category: "Work")])
        }
        let loaded = try XCTUnwrap(TaskDatabase(path: path)).loadTasks()
        XCTAssertEqual(loaded.first { $0.title == "Run" }?.habit, habit)
        XCTAssertNil(loaded.first { $0.title == "Plain" }?.habit)
    }

    func testHabitOnlyChangeStillPersistsAndClears() throws {
        let path = try freshPath()
        let db = try XCTUnwrap(TaskDatabase(path: path))
        var t = TaskItem(title: "Run", category: "Work")
        db.saveTasks([t])
        t.habit = habit
        db.saveTasks([t])
        XCTAssertEqual(db.loadTasks().first?.habit, habit)
        t.habit = TaskHabit(schedule: .daily, mode: .manual, startDay: habit.startDay)
        db.saveTasks([t])
        XCTAssertEqual(db.loadTasks().first?.habit?.mode, .manual)
        t.habit = nil
        db.saveTasks([t])
        XCTAssertNil(db.loadTasks().first?.habit)
    }

    func testHabitDoesNotChangeSyncHash() {
        var t = TaskItem(title: "Run", category: "Work")
        let before = t.contentHash
        t.habit = habit
        XCTAssertEqual(t.contentHash, before)
    }

    func testMigratesExistingDatabaseWithoutHabitColumn() throws {
        let path = try freshPath()
        var t = TaskItem(title: "Old", category: "Work")
        do {
            let db = try XCTUnwrap(TaskDatabase(path: path))
            db.saveTasks([t])
        }
        var raw: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &raw), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(raw, "ALTER TABLE tasks DROP COLUMN habit; DROP TABLE habit_checks;", nil, nil, nil), SQLITE_OK)
        sqlite3_close(raw)

        let db = try XCTUnwrap(TaskDatabase(path: path))
        XCTAssertEqual(db.loadTasks().count, 1)
        t.habit = habit
        db.saveTasks([t])
        XCTAssertEqual(db.loadTasks().first?.habit, habit)
        db.setHabitCheck(day: Date(timeIntervalSince1970: 0), taskID: t.id, checked: true)
        XCTAssertEqual(db.loadHabitChecks().count, 1)
    }

    func testHabitChecksCRUDAndUniqueness() throws {
        let db = try XCTUnwrap(TaskDatabase(path: try freshPath()))
        let a = UUID(), b = UUID()
        let d1 = Date(timeIntervalSince1970: 86_400), d2 = Date(timeIntervalSince1970: 172_800)
        db.setHabitCheck(day: d1, taskID: a, checked: true)
        db.setHabitCheck(day: d1, taskID: a, checked: true)   // idempotent
        db.setHabitCheck(day: d2, taskID: a, checked: true)
        db.setHabitCheck(day: d1, taskID: b, checked: true)
        XCTAssertEqual(Set(db.loadHabitChecks()),
                       [HabitCheck(day: d1, taskID: a), HabitCheck(day: d2, taskID: a), HabitCheck(day: d1, taskID: b)])
        XCTAssertEqual(db.loadHabitChecks().count, 3)
        db.setHabitCheck(day: d1, taskID: a, checked: false)
        XCTAssertEqual(db.loadHabitChecks().count, 2)
        db.setHabitCheck(day: d1, taskID: a, checked: false)  // no-op
        XCTAssertEqual(db.loadHabitChecks().count, 2)
    }
}

final class HabitMergeTests: XCTestCase {
    func testRemoteTaskUpdatePreservesLocalHabit() {
        let habit = TaskHabit(schedule: .daily, mode: .manual, startDay: Date(timeIntervalSince1970: 0))
        var local = TaskItem(title: "local", category: "Work")
        local.habit = habit; local.modifiedAt = Date(timeIntervalSince1970: 100)
        var remote = local; remote.title = "remote"; remote.habit = nil
        remote.modifiedAt = Date(timeIntervalSince1970: 200)
        let merged = MergePolicy.mergeTask(local: local, remote: remote)
        XCTAssertEqual(merged.title, "remote")
        XCTAssertEqual(merged.habit, habit)
    }
}

