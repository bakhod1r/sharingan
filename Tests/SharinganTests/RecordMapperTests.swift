import XCTest
import CloudKit
@testable import SharinganCore

final class RecordMapperTests: XCTestCase {
    private let zone = CKRecordZone.ID(zoneName: "SharinganData", ownerName: CKCurrentUserDefaultName)

    func testTaskRoundTripsThroughCKRecord() throws {
        var task = TaskItem(title: "Ship sync", category: "Work")
        task.tags = ["cloud", "1.3"]
        task.notes = "line one\nline two"
        task.dueDate = Date(timeIntervalSince1970: 1_800_000)
        task.estimatedPomodoros = 4
        task.isDone = true
        task.completedAt = Date(timeIntervalSince1970: 1_900_000)

        let record = RecordMapper.record(for: task, in: zone, systemFields: nil)
        XCTAssertEqual(record.recordType, SyncRecordType.task.rawValue)
        XCTAssertEqual(record.recordID.recordName, task.recordName)

        let back = try XCTUnwrap(RecordMapper.task(from: record))
        XCTAssertEqual(back, task)
    }

    func testFocusLogRoundTrips() throws {
        let entry = FocusLogEntry(day: Date(timeIntervalSince1970: 86_400), taskID: UUID(),
                                  subtaskID: UUID(), title: "Deep work", count: 3, seconds: 4500)
        let record = RecordMapper.record(for: entry, in: zone, systemFields: nil)
        XCTAssertEqual(try XCTUnwrap(RecordMapper.focusLog(from: record)), entry)
    }

    // A record from a newer app version carries fields this build has never
    // heard of; decoding must not throw them away or fail.
    func testUnknownFieldsDoNotBreakDecoding() throws {
        let task = TaskItem(title: "Forward compatible", category: "Work")
        let record = RecordMapper.record(for: task, in: zone, systemFields: nil)
        record["somethingFromTheFuture"] = "value" as CKRecordValue
        XCTAssertEqual(try XCTUnwrap(RecordMapper.task(from: record)).title, "Forward compatible")
    }

    func testMalformedRecordDecodesToNilRatherThanCrashing() {
        let record = CKRecord(recordType: SyncRecordType.task.rawValue,
                              recordID: CKRecord.ID(recordName: "not-a-task", zoneID: zone))
        XCTAssertNil(RecordMapper.task(from: record))
    }
}
