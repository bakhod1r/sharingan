import XCTest
import CloudKit
@testable import SharinganCore

final class ActiveTimerRecordTests: XCTestCase {
    private let zone = CKRecordZone.ID(zoneName: "SharinganData",
                                       ownerName: CKCurrentUserDefaultName)

    private func state(deviceID: String = "mac-1",
                       phase: String = "focus",
                       startedAt: Date = Date(timeIntervalSince1970: 1000),
                       endsAt: Date? = Date(timeIntervalSince1970: 2500),
                       isPaused: Bool = false,
                       updatedAt: Date = Date(timeIntervalSince1970: 1000)) -> ActiveTimerState {
        ActiveTimerState(deviceID: deviceID, deviceName: "Studio", phase: phase,
                         startedAt: startedAt, endsAt: endsAt, isPaused: isPaused,
                         taskTitle: "Ship sync", updatedAt: updatedAt)
    }

    // MARK: - Mapper

    func testActiveTimerRoundTrips() throws {
        let original = state()
        let record = RecordMapper.record(for: original, in: zone, systemFields: nil)
        XCTAssertEqual(record.recordType, SyncRecordType.activeTimer.rawValue)
        XCTAssertEqual(try XCTUnwrap(RecordMapper.activeTimer(from: record)), original)
    }

    // One record, not one per Mac: whoever wrote last is the current timer.
    func testTimerRecordNameIsConstant() {
        let a = state(deviceID: "mac-1", phase: "focus")
        let b = state(deviceID: "mac-2", phase: "shortBreak")
        XCTAssertEqual(RecordMapper.record(for: a, in: zone, systemFields: nil).recordID.recordName,
                       RecordMapper.record(for: b, in: zone, systemFields: nil).recordID.recordName)
    }

    // MARK: - Apply rules (pure)

    // An echo of our own write must never drive our timer — that is the loop
    // breaker (A starts → B applies → B publishes → A must NOT re-apply).
    func testOwnDeviceRecordIsIgnoredOnFetch() {
        let mine = state(deviceID: DeviceIdentity.current)
        XCTAssertFalse(CloudSyncEngine.shouldSurface(remoteTimer: mine))
        XCTAssertFalse(CloudSyncEngine.shouldApply(remote: mine,
                                                   now: Date(timeIntervalSince1970: 1500),
                                                   current: nil))
    }

    func testRunningRecordWithPastDeadlineIsStale() {
        let old = state(endsAt: Date(timeIntervalSince1970: 2000))
        XCTAssertFalse(CloudSyncEngine.shouldApply(
            remote: old, now: Date(timeIntervalSince1970: 3000), current: nil),
            "a session that already ended is history, not a command")
    }

    // A paused session is never stale by clock — its remaining time is
    // frozen, not ticking.
    func testPausedRecordWithPastDeadlineStillApplies() {
        let paused = state(endsAt: Date(timeIntervalSince1970: 2000), isPaused: true)
        XCTAssertTrue(CloudSyncEngine.shouldApply(
            remote: paused, now: Date(timeIntervalSince1970: 3000), current: nil))
    }

    func testNewestUpdateWinsAgainstTheFreshestKnownState() {
        let now = Date(timeIntervalSince1970: 1500)
        let older = state(updatedAt: Date(timeIntervalSince1970: 1000))
        let newer = state(updatedAt: Date(timeIntervalSince1970: 1200))
        XCTAssertFalse(CloudSyncEngine.shouldApply(remote: older, now: now, current: newer))
        XCTAssertTrue(CloudSyncEngine.shouldApply(remote: newer, now: now, current: older))
    }

    func testMergeTimerTakesTheNewerWrite() {
        let older = state(updatedAt: Date(timeIntervalSince1970: 1000))
        let newer = state(deviceID: "mac-2", updatedAt: Date(timeIntervalSince1970: 1200))
        XCTAssertEqual(MergePolicy.mergeTimer(local: older, remote: newer), newer)
        XCTAssertEqual(MergePolicy.mergeTimer(local: newer, remote: older), newer)
        XCTAssertEqual(MergePolicy.mergeTimer(local: nil, remote: older), older)
    }

    // MARK: - Pause round trip

    // Pause on A → apply on B → resume on B → apply on A: the remaining time
    // must survive both hops, however late each record arrives.
    func testPauseRoundTripKeepsRemainingTimeConsistent() {
        let pausedAtA = Date(timeIntervalSince1970: 10_000)
        let remainingAtPause: TimeInterval = 600

        // A pauses with 10:00 left: endsAt frozen relative to updatedAt.
        let pausedRecord = state(deviceID: "mac-A",
                                 startedAt: pausedAtA.addingTimeInterval(-900),
                                 endsAt: pausedAtA.addingTimeInterval(remainingAtPause),
                                 isPaused: true,
                                 updatedAt: pausedAtA)

        // B fetches it 47 seconds later — remaining must still read 10:00.
        let fetchOnB = pausedAtA.addingTimeInterval(47)
        XCTAssertEqual(pausedRecord.remaining(now: fetchOnB), remainingAtPause,
                       accuracy: 1.0)

        // B resumes 5 minutes later: endsAt = resume time + what was left.
        let resumeOnB = pausedAtA.addingTimeInterval(300)
        let resumedRecord = state(deviceID: "mac-B",
                                  startedAt: resumeOnB.addingTimeInterval(-900),
                                  endsAt: resumeOnB.addingTimeInterval(remainingAtPause),
                                  isPaused: false,
                                  updatedAt: resumeOnB)

        // A fetches the resume 3 seconds later: the wall-clock deadline rules,
        // so A shows 3 seconds less — both Macs end at the same instant.
        let fetchOnA = resumeOnB.addingTimeInterval(3)
        XCTAssertEqual(resumedRecord.remaining(now: fetchOnA),
                       remainingAtPause - 3, accuracy: 1.0)
        XCTAssertTrue(CloudSyncEngine.shouldApply(remote: resumedRecord,
                                                  now: fetchOnA,
                                                  current: pausedRecord),
                      "the resume is newer than the pause and must win")
    }

    // MARK: - Mirrored apply on the real timer

    @MainActor
    func testApplyMirroredPausedSessionFreezesAtTheRemoteRemaining() {
        let timer = PomodoroTimer(settings: PomodoroSettings())
        let pausedAt = Date()
        timer.applyMirroredSession(phase: .focus,
                                   isPaused: true,
                                   startedAt: pausedAt.addingTimeInterval(-900),
                                   endsAt: pausedAt.addingTimeInterval(600),
                                   asOf: pausedAt)
        XCTAssertEqual(timer.phase, .paused)
        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(timer.remainingSeconds, 600, accuracy: 1.0)
        XCTAssertEqual(timer.effectivePhase, .focus)
    }

    @MainActor
    func testApplyMirroredRunningSessionAlignsToTheWallClockDeadline() {
        let timer = PomodoroTimer(settings: PomodoroSettings())
        let now = Date()
        timer.applyMirroredSession(phase: .shortBreak,
                                   isPaused: false,
                                   startedAt: now.addingTimeInterval(-100),
                                   endsAt: now.addingTimeInterval(200),
                                   asOf: now.addingTimeInterval(-10))
        XCTAssertEqual(timer.phase, .shortBreak)
        XCTAssertTrue(timer.isRunning)
        XCTAssertEqual(timer.remainingSeconds, 200, accuracy: 1.5)
        XCTAssertEqual(timer.totalSeconds, 300, accuracy: 1.5)
        timer.stop()
    }
}
