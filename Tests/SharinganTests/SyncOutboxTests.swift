import XCTest
@testable import SharinganCore

final class SyncOutboxTests: XCTestCase {
    private let type = "task"

    private func makeOutbox(seed: [SyncOutbox.Op] = []) -> SyncOutbox {
        SyncOutbox(storage: InMemorySyncOutboxStorage(seed: seed))
    }

    // MARK: - Coalescing

    func testSaveThenSaveKeepsOriginalEnqueuedAt() {
        let outbox = makeOutbox()
        let t0 = Date(timeIntervalSince1970: 1_000)
        outbox.enqueue(recordType: type, recordName: "a", kind: .save, now: t0)
        let later = outbox.enqueue(recordType: type, recordName: "a",
                                   kind: .save, now: t0.addingTimeInterval(5))
        XCTAssertEqual(outbox.pendingCount, 1)
        XCTAssertEqual(later.enqueuedAt, t0, "coalesced save must keep the first intent's age")
    }

    func testSaveThenDeleteBecomesDelete() {
        let outbox = makeOutbox()
        outbox.enqueue(recordType: type, recordName: "a", kind: .save)
        outbox.enqueue(recordType: type, recordName: "a", kind: .delete)
        XCTAssertEqual(outbox.op(recordType: type, recordName: "a")?.kind, .delete)
        XCTAssertEqual(outbox.pendingCount, 1)
    }

    func testDeleteThenSaveResurrectsAndResetsAge() {
        let outbox = makeOutbox()
        let t0 = Date(timeIntervalSince1970: 1_000)
        outbox.enqueue(recordType: type, recordName: "a", kind: .delete, now: t0)
        let resurrected = outbox.enqueue(recordType: type, recordName: "a",
                                         kind: .save, now: t0.addingTimeInterval(30))
        XCTAssertEqual(resurrected.kind, .save)
        XCTAssertEqual(resurrected.enqueuedAt, t0.addingTimeInterval(30),
                       "a resurrect is a new intent — it must not inherit the tombstone's age")
    }

    // MARK: - Ready ordering & backoff

    func testReadyOrdersByAgeThenTypeThenName() {
        let outbox = makeOutbox()
        let t0 = Date(timeIntervalSince1970: 1_000)
        outbox.enqueue(recordType: type, recordName: "b", kind: .save, now: t0.addingTimeInterval(10))
        outbox.enqueue(recordType: type, recordName: "a", kind: .save, now: t0)
        XCTAssertEqual(outbox.ready(at: t0.addingTimeInterval(100)).map(\.recordName), ["a", "b"])
    }

    func testMarkFailedGatesRetryWithBackoff() {
        let outbox = makeOutbox()
        let t0 = Date(timeIntervalSince1970: 1_000)
        outbox.enqueue(recordType: type, recordName: "a", kind: .save, now: t0)
        outbox.markFailed(SyncOutbox.Key(recordType: type, recordName: "a"), at: t0)
        XCTAssertTrue(outbox.ready(at: t0).isEmpty, "a just-failed op must be gated")
        XCTAssertEqual(outbox.ready(at: t0.addingTimeInterval(3)).count, 1,
                       "after the first backoff (2s) it is ready again")
    }

    func testMarkSentRemovesOp() {
        let outbox = makeOutbox()
        outbox.enqueue(recordType: type, recordName: "a", kind: .save)
        outbox.markSent(SyncOutbox.Key(recordType: type, recordName: "a"))
        XCTAssertEqual(outbox.pendingCount, 0)
    }

    func testEnqueueResetsAttemptsForFreshContent() {
        let outbox = makeOutbox()
        let key = SyncOutbox.Key(recordType: type, recordName: "a")
        outbox.enqueue(recordType: type, recordName: "a", kind: .save)
        outbox.markFailed(key)
        outbox.markFailed(key)
        outbox.enqueue(recordType: type, recordName: "a", kind: .save)
        XCTAssertEqual(outbox.op(recordType: type, recordName: "a")?.attempts, 0)
    }

    // MARK: - Reset

    func testResetClearsEverything() {
        let outbox = makeOutbox()
        outbox.enqueue(recordType: type, recordName: "a", kind: .delete)
        outbox.reset()
        XCTAssertEqual(outbox.pendingCount, 0)
    }

    // MARK: - Backoff shape

    func testBackoffIsExponentialAndCapped() {
        XCTAssertEqual(SyncOutbox.backoff(attempts: 0), 0)
        XCTAssertEqual(SyncOutbox.backoff(attempts: 1), 2)
        XCTAssertEqual(SyncOutbox.backoff(attempts: 2), 4)
        XCTAssertEqual(SyncOutbox.backoff(attempts: 3), 8)
        XCTAssertEqual(SyncOutbox.backoff(attempts: 100), 300, "capped at 5 minutes by default")
    }

    func testBackoffHonoursConfiguredCap() {
        XCTAssertEqual(SyncOutbox.backoff(attempts: 100, cap: 60), 60, "a 1-minute cap is reached")
        XCTAssertEqual(SyncOutbox.backoff(attempts: 100, cap: 900), 900, "a 15-minute cap is reached")
        XCTAssertEqual(SyncOutbox.backoff(attempts: 1, cap: 900), 2, "early attempts are unaffected by the cap")
    }

    func testMaxBackoffPropertyGatesRetry() {
        let outbox = makeOutbox()
        outbox.maxBackoff = 60
        let t0 = Date(timeIntervalSince1970: 1_000)
        let key = SyncOutbox.Key(recordType: type, recordName: "a")
        outbox.enqueue(recordType: type, recordName: "a", kind: .save, now: t0)
        for _ in 0..<10 { outbox.markFailed(key, at: t0) }
        XCTAssertTrue(outbox.ready(at: t0.addingTimeInterval(59)).isEmpty)
        XCTAssertEqual(outbox.ready(at: t0.addingTimeInterval(61)).count, 1,
                       "backoff must not exceed the configured 60s cap")
    }

    // MARK: - Persistence round-trip

    func testOpsSurviveReconstructionFromStorage() {
        let storage = InMemorySyncOutboxStorage()
        let t0 = Date(timeIntervalSince1970: 1_000)
        do {
            let outbox = SyncOutbox(storage: storage)
            outbox.enqueue(recordType: type, recordName: "live", kind: .save, now: t0)
            outbox.enqueue(recordType: type, recordName: "gone", kind: .delete, now: t0)
        }
        // A "relaunch": a brand-new queue over the same storage.
        let reloaded = SyncOutbox(storage: storage)
        XCTAssertEqual(reloaded.pendingCount, 2)
        XCTAssertEqual(reloaded.op(recordType: type, recordName: "gone")?.kind, .delete,
                       "the tombstone must survive a restart")
    }
}
