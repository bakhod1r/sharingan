import XCTest
@testable import SharinganCore

private struct Rec: SyncableRecord, Equatable {
    let recordName: String
    let contentHash: String
}

final class SyncShadowTests: XCTestCase {
    private func shadow(_ pairs: [(String, String)]) -> [String: ShadowEntry] {
        Dictionary(uniqueKeysWithValues: pairs.map {
            ($0.0, ShadowEntry(recordName: $0.0, contentHash: $0.1, systemFields: nil))
        })
    }

    func testUnchangedCollectionProducesEmptyDiff() {
        let local = [Rec(recordName: "a", contentHash: "1"), Rec(recordName: "b", contentHash: "2")]
        let diff = SyncShadow.diff(local: local, shadow: shadow([("a", "1"), ("b", "2")]))
        XCTAssertEqual(diff, SyncDiff(created: [], changed: [], deletedRecordNames: []))
    }

    func testNewRecordIsCreated() {
        let local = [Rec(recordName: "a", contentHash: "1")]
        let diff = SyncShadow.diff(local: local, shadow: [:])
        XCTAssertEqual(diff.created, local)
        XCTAssertTrue(diff.changed.isEmpty)
        XCTAssertTrue(diff.deletedRecordNames.isEmpty)
    }

    func testEditedRecordIsChangedNotRecreated() {
        let local = [Rec(recordName: "a", contentHash: "2")]
        let diff = SyncShadow.diff(local: local, shadow: shadow([("a", "1")]))
        XCTAssertEqual(diff.changed, local)
        XCTAssertTrue(diff.created.isEmpty)
    }

    // The whole point of the shadow: a DELETE-all + re-INSERT save must not
    // look like "everything deleted, everything created".
    func testMissingRecordIsDeletedNotResurrected() {
        let diff = SyncShadow.diff(local: [Rec(recordName: "a", contentHash: "1")],
                                   shadow: shadow([("a", "1"), ("gone", "9")]))
        XCTAssertEqual(diff.deletedRecordNames, ["gone"])
        XCTAssertTrue(diff.created.isEmpty)
        XCTAssertTrue(diff.changed.isEmpty)
    }

    func testDiffIsDeterministicallyOrdered() {
        let local = [Rec(recordName: "b", contentHash: "1"), Rec(recordName: "a", contentHash: "1")]
        let diff = SyncShadow.diff(local: local, shadow: [:])
        XCTAssertEqual(diff.created.map(\.recordName), ["a", "b"])
    }
}
