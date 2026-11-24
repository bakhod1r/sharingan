import XCTest
@testable import SharinganCore

final class SyncableRecordTests: XCTestCase {
    // A pre-1.3.0 row/JSON has no modifiedAt; it must decode, not throw.
    func testLegacyTaskDecodesWithModifiedAtFallingBackToCreatedAt() throws {
        let json = """
        {"id":"\(UUID().uuidString)","title":"old","category":"Inbox","tags":[],
         "isDone":false,"pomodorosDone":0,"createdAt":1000,"sortOrder":0,
         "notes":"","subtasks":[],"recurrence":"none","priority":0}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        let task = try decoder.decode(TaskItem.self, from: json)
        XCTAssertEqual(task.modifiedAt, task.createdAt)
    }

    func testContentHashIgnoresModifiedAtButTracksTitle() {
        var a = TaskItem(title: "Write plan", category: "Work")
        var b = a
        b.modifiedAt = a.modifiedAt.addingTimeInterval(3600)
        XCTAssertEqual(a.contentHash, b.contentHash,
                       "a bare touch must not push a record")
        b.title = "Write a different plan"
        XCTAssertNotEqual(a.contentHash, b.contentHash)
        a.title = b.title
        XCTAssertEqual(a.contentHash, b.contentHash)
    }

    func testAllowedAppsChangeContentHash() {
        var task = TaskItem(title: "Write plan", category: "Work")
        let before = task.contentHash
        task.allowedApps = [BlockedApp(bundleID: "com.apple.dt.Xcode", name: "Xcode")]
        XCTAssertNotEqual(before, task.contentHash)
    }

    // Pins the hash of a task with no allow-list to a literal, so any change that
    // makes an empty allowedApps alter the payload fails. An empty allow-list must not change it, or every
    // existing task would re-upload on upgrade.
    func testEmptyAllowedAppsKeepsLegacyHash() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","title":"legacy","category":"Inbox","tags":[],
         "isDone":false,"pomodorosDone":0,"createdAt":1000,"modifiedAt":1000,"sortOrder":0,
         "notes":"","subtasks":[],"recurrence":"none","priority":0}
        """.data(using: .utf8)!
        let task = try JSONDecoder().decode(TaskItem.self, from: json)
        XCTAssertEqual(task.allowedApps, [])
        XCTAssertEqual(task.contentHash, "e4779e65684874de1efee6ddfbea3f3ee8975807384eda59a7453c70aa95fb73")
    }

    func testFocusLogRecordNameIsStableAcrossEqualEntries() {
        let id = UUID(), day = Date(timeIntervalSince1970: 86_400)
        let x = FocusLogEntry(day: day, taskID: id, subtaskID: nil, title: "t", count: 1, seconds: 60)
        let y = FocusLogEntry(day: day, taskID: id, subtaskID: nil, title: "t", count: 9, seconds: 600)
        XCTAssertEqual(x.recordName, y.recordName,
                       "same (day, task, subtask) is the same record — counts merge, they do not fork")
        XCTAssertNotEqual(x.contentHash, y.contentHash)
    }
}
