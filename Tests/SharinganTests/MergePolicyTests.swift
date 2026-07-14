import XCTest
@testable import SharinganCore

final class MergePolicyTests: XCTestCase {
    private func task(_ title: String, modified: TimeInterval) -> TaskItem {
        var t = TaskItem(title: title, category: "Work")
        t.modifiedAt = Date(timeIntervalSince1970: modified)
        return t
    }

    func testNewerRemoteWins() {
        let local = task("local", modified: 100)
        var remote = local; remote.title = "remote"; remote.modifiedAt = Date(timeIntervalSince1970: 200)
        XCTAssertEqual(MergePolicy.mergeTask(local: local, remote: remote).title, "remote")
    }

    func testOlderRemoteLoses() {
        let local = task("local", modified: 300)
        var remote = local; remote.title = "remote"; remote.modifiedAt = Date(timeIntervalSince1970: 200)
        XCTAssertEqual(MergePolicy.mergeTask(local: local, remote: remote).title, "local")
    }

    func testUnknownLocalTakesRemote() {
        let remote = task("remote", modified: 200)
        XCTAssertEqual(MergePolicy.mergeTask(local: nil, remote: remote), remote)
    }

    // Statistics are additive: two Macs each logging focus for the same day
    // must sum to the truth, never overwrite each other.
    func testFocusLogTakesMaxPerField() {
        let id = UUID(), day = Date(timeIntervalSince1970: 86_400)
        let local = FocusLogEntry(day: day, taskID: id, subtaskID: nil, title: "t", count: 3, seconds: 900)
        let remote = FocusLogEntry(day: day, taskID: id, subtaskID: nil, title: "t", count: 5, seconds: 600)
        let merged = MergePolicy.mergeFocusLog(local: local, remote: remote)
        XCTAssertEqual(merged.count, 5)
        XCTAssertEqual(merged.seconds, 900)
    }

    // A delete must not silently swallow an edit made afterwards elsewhere.
    func testDeleteLosesToANewerLocalEdit() {
        let local = task("edited after the delete", modified: 500)
        XCTAssertFalse(MergePolicy.shouldApplyDelete(
            recordName: local.recordName, local: local,
            deletedAt: Date(timeIntervalSince1970: 400)))
        XCTAssertTrue(MergePolicy.shouldApplyDelete(
            recordName: local.recordName, local: local,
            deletedAt: Date(timeIntervalSince1970: 600)))
    }
}
