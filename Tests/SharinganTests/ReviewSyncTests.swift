import XCTest
import CloudKit
@testable import SharinganCore

final class ReviewSyncTests: XCTestCase {
    private let zone = CKRecordZone.ID(zoneName: "SharinganData", ownerName: CKCurrentUserDefaultName)

    func testTrashedAtSurvivesRoundTripAndHashMatches() throws {
        var task = TaskItem(title: "Gone", category: "Work")
        task.trashedAt = Date(timeIntervalSince1970: 1_800_000)
        task.jiraIssueType = "Bug"
        let record = RecordMapper.record(for: task, in: zone, systemFields: nil)
        let back = try XCTUnwrap(RecordMapper.task(from: record))
        XCTAssertEqual(back.trashedAt, task.trashedAt)
        XCTAssertEqual(back.contentHash, task.contentHash)
    }

    func testRecordWithoutTrashedAtDecodesAsNotTrashed() throws {
        let task = TaskItem(title: "Live", category: "Work")
        let record = RecordMapper.record(for: task, in: zone, systemFields: nil)
        XCTAssertNil(record["trashedAt"])
        XCTAssertNil(try XCTUnwrap(RecordMapper.task(from: record)).trashedAt)
    }

    func testJiraIssueTypeAffectsHash() {
        var a = TaskItem(title: "J", category: "Work")
        let b = a
        a.jiraIssueType = "Story"
        XCTAssertNotEqual(a.contentHash, b.contentHash)
    }
}
