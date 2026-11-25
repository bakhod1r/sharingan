import CloudKit
import Foundation
import Testing
@testable import SharinganCore

/// REVIEW 2.10 — custom projects, the focus session log and per-device
/// pomodoro counts crossing Macs. Pure parts only (mapper, merge, combine).
private let zone = CKRecordZone.ID(zoneName: "SharinganData", ownerName: CKCurrentUserDefaultName)

@MainActor
@Suite("Sync gaps: projects")
struct ProjectSyncTests {
    private func tempStore() -> TaskStore {
        TaskStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("blink-projsync-\(UUID().uuidString).sqlite"))
    }

    @Test func projectRoundTripsThroughCKRecord() throws {
        let p = SyncableProject(TaskCategory(name: "Atlas", colorHex: "#112233", icon: "star"))
        let record = RecordMapper.record(for: p, in: zone, systemFields: nil)
        #expect(record.recordType == SyncRecordType.project.rawValue)
        #expect(try #require(RecordMapper.project(from: record)) == p.category)
    }

    @Test func projectRecordNameNeverCollidesWithACategoryOfTheSameName() {
        let cat = TaskCategory(name: "Work", colorHex: "#000000")
        #expect(SyncableProject(cat).recordName != cat.recordName,
                "projects and categories share one CloudKit zone namespace")
    }

    @Test func mergeRemoteAddsAndUpdatesProjects() {
        let store = tempStore()
        store.addProject(name: "Atlas", colorHex: "#111111")
        store.mergeRemote(projects: [TaskCategory(name: "Atlas", colorHex: "#222222", icon: "x"),
                                     TaskCategory(name: "Beta", colorHex: "#333333")])
        #expect(store.customProjects.count == 2)
        #expect(store.customProjects.first { $0.name == "Atlas" }?.colorHex == "#222222")
    }

    @Test func mergeRemoteDeletesProjectsAndDoesNotEchoBack() {
        let store = tempStore()
        store.addProject(name: "Atlas", colorHex: "#111111")
        var fired = false
        store.didPersist = { fired = true }
        store.mergeRemote(deletedProjectNames: ["Atlas"])
        #expect(store.customProjects.isEmpty)
        #expect(!fired)
    }

    @Test func remoteProjectsPersistToDatabase() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("blink-projsync-\(UUID().uuidString).sqlite")
        let store = TaskStore(fileURL: url)
        store.mergeRemote(projects: [TaskCategory(name: "Atlas", colorHex: "#111111")])
        let reopened = TaskStore(fileURL: url)
        #expect(reopened.customProjects.map(\.name) == ["Atlas"])
    }

    @Test func renameIsDeleteOldPlusCreateNewInTheDiffLikeCategories() {
        let store = tempStore()
        store.addProject(name: "Atlas", colorHex: "#111111")
        let shadow = Dictionary(uniqueKeysWithValues: store.customProjects.map(SyncableProject.init).map {
            ($0.recordName, ShadowEntry(recordName: $0.recordName, contentHash: $0.contentHash, systemFields: nil))
        })
        store.renameProject("Atlas", to: "Atlas2")
        let diff = SyncShadow.diff(local: store.customProjects.map(SyncableProject.init), shadow: shadow)
        #expect(diff.created.map(\.category.name) == ["Atlas2"])
        #expect(diff.deletedRecordNames == [SyncableProject(TaskCategory(name: "Atlas", colorHex: "")).recordName])
    }
}

@MainActor
@Suite("Sync gaps: focus session log")
struct SessionLogSyncTests {
    private func rec(start: Date, id: UUID = UUID(), device: String? = "dev-A") -> SessionRecord {
        SessionRecord(id: id, start: start, end: start.addingTimeInterval(1500), phase: .focus,
                      completed: true, taskID: UUID(), taskTitle: "T", plannedSeconds: 1500,
                      appUsage: ["com.apple.dt.Xcode": 90], deviceName: "Mac A", deviceID: device)
    }

    private func tempLog() -> (FocusSessionLog, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sessions-\(UUID().uuidString).json")
        return (FocusSessionLog(fileURL: url), url)
    }

    @Test func sessionRecordRoundTripsThroughCKRecord() throws {
        let r = rec(start: Date(timeIntervalSince1970: 1_700_000_000))
        let ck = RecordMapper.record(for: r, in: zone, systemFields: nil)
        #expect(ck.recordType == SyncRecordType.session.rawValue)
        #expect(ck.recordID.recordName == r.recordName)
        #expect(try #require(RecordMapper.sessionRecord(from: ck)) == r)
        #expect(RecordMapper.sessionRecord(from: ck)?.contentHash == r.contentHash)
    }

    @Test func legacyJSONWithoutIdGetsADeterministicId() throws {
        let json = """
        [{"start":1700000000,"end":1700001500,"phase":"focus","completed":true}]
        """.data(using: .utf8)!
        let a = try JSONDecoder().decode([SessionRecord].self, from: json)
        let b = try JSONDecoder().decode([SessionRecord].self, from: json)
        #expect(a[0].id == b[0].id, "two decodes (or two Macs) must mint the same id")
        #expect(a[0].deviceID == nil)
        let other = """
        [{"start":1700009999,"end":1700011500,"phase":"focus","completed":true}]
        """.data(using: .utf8)!
        #expect(try JSONDecoder().decode([SessionRecord].self, from: other)[0].id != a[0].id)
    }

    @Test func idPresentInJSONIsKept() throws {
        let r = rec(start: Date())
        let data = try JSONEncoder().encode([r])
        #expect(try JSONDecoder().decode([SessionRecord].self, from: data)[0].id == r.id)
    }

    @Test func mergeRemoteIsUnionById() {
        let (log, url) = tempLog()
        defer { try? FileManager.default.removeItem(at: url) }
        let local = rec(start: Date().addingTimeInterval(-3600))
        log.append(local)
        let remote = rec(start: Date().addingTimeInterval(-7200), device: "dev-B")
        let changed = log.mergeRemote([remote, local])   // `local` is a duplicate
        #expect(changed)
        #expect(log.records.count == 2)
        #expect(Set(log.records.map(\.id)) == [local.id, remote.id])
        #expect(!log.mergeRemote([remote]), "re-delivery is a no-op")
    }

    @Test func mergeRemoteDoesNotFireLocalChangeHook() {
        let (log, url) = tempLog()
        defer { try? FileManager.default.removeItem(at: url) }
        var fired = 0
        log.didAppend = { fired += 1 }
        log.mergeRemote([rec(start: Date())])
        #expect(fired == 0, "an applied fetch must not echo back")
        log.append(rec(start: Date()))
        #expect(fired == 1)
    }

    @Test func mergeRemoteDropsRecordsBeyondRetention() {
        let (log, url) = tempLog()
        defer { try? FileManager.default.removeItem(at: url) }
        let ancient = rec(start: Calendar.current.date(byAdding: .day, value: -500, to: Date())!)
        #expect(!log.mergeRemote([ancient]))
        #expect(log.records.isEmpty)
    }

    @Test func mergedRecordsPersist() {
        let (log, url) = tempLog()
        defer { try? FileManager.default.removeItem(at: url) }
        let remote = rec(start: Date(), device: "dev-B")
        log.mergeRemote([remote])
        log.flushForTesting()
        #expect(FocusSessionLog(fileURL: url).records.map(\.id) == [remote.id])
    }

    @Test func retentionTrimNeverBecomesACloudDelete() {
        let kept = rec(start: Date())
        let trimmed = rec(start: Calendar.current.date(byAdding: .day, value: -401, to: Date())!)
        // Shadow still remembers the trimmed record (it was synced earlier).
        let shadow = [kept, trimmed].reduce(into: [String: ShadowEntry]()) {
            $0[$1.recordName] = ShadowEntry(recordName: $1.recordName, contentHash: $1.contentHash, systemFields: nil)
        }
        let plan = CloudSyncEngine.sessionLogChanges(local: [kept], shadow: shadow)
        #expect(plan.saves.isEmpty)
        #expect(plan.shadowNamesToForget == [trimmed.recordName],
                "forget locally; never delete the other Mac's copy")
    }

    @Test func newLocalSessionIsPushed() {
        let r = rec(start: Date())
        let plan = CloudSyncEngine.sessionLogChanges(local: [r], shadow: [:])
        #expect(plan.saves.map(\.id) == [r.id])
    }
}

@Suite("Sync gaps: pomodoro stats fleet")
struct DeviceStatsTests {
    private let cal = Calendar.current
    private var today: Date { cal.startOfDay(for: Date()) }
    private func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: -offset, to: today)! }

    private func localStats(_ counts: [Int: Int]) -> PomodoroStats {
        var s = PomodoroStats()
        for (offset, n) in counts {
            for _ in 0..<n { s.registerFocusCompletion(on: day(offset).addingTimeInterval(36_000)) }
        }
        return s
    }

    @Test func combinedWithNoRemotesIsIdentical() {
        let s = localStats([0: 2, 1: 1])
        #expect(s.combined(with: []) == s)
    }

    @Test func combinedSumsPerDayAndTodayAcrossDevices() {
        let s = localStats([0: 2, 1: 1])
        let remote = DeviceDailyStats(deviceID: "B", deviceName: "B",
                                      days: [DailyCount(day: day(0), count: 3), DailyCount(day: day(2), count: 4)],
                                      hourCounts: Array(repeating: 0, count: 24))
        let c = s.combined(with: [remote])
        #expect(c.completedTodayCount() == 5)
        #expect(c.history.first { cal.isDate($0.day, inSameDayAs: day(2)) }?.count == 4)
        #expect(c.history.first { cal.isDate($0.day, inSameDayAs: day(1)) }?.count == 1)
        #expect(c.completedFocus == s.completedFocus + 7)
    }

    @Test func combinedStreakComesFromCombinedHistory() {
        // Local worked today only; the other Mac covered the two days before.
        let s = localStats([0: 1])
        let remote = DeviceDailyStats(deviceID: "B", deviceName: "B",
                                      days: [DailyCount(day: day(1), count: 1), DailyCount(day: day(2), count: 1)],
                                      hourCounts: Array(repeating: 0, count: 24))
        #expect(s.combined(with: [remote]).streak.currentStreak == 3)
    }

    @Test func combinedStreakSurvivesNoSessionYetToday() {
        let s = localStats([1: 1])
        let remote = DeviceDailyStats(deviceID: "B", deviceName: "B",
                                      days: [DailyCount(day: day(2), count: 1)],
                                      hourCounts: Array(repeating: 0, count: 24))
        #expect(s.combined(with: [remote]).streak.currentStreak == 2)
    }

    @Test func combinedHourCountsSum() {
        var s = PomodoroStats(); s.hourCounts[9] = 2
        var h = Array(repeating: 0, count: 24); h[9] = 1; h[14] = 5
        let remote = DeviceDailyStats(deviceID: "B", deviceName: "B", days: [], hourCounts: h)
        let c = s.combined(with: [remote])
        #expect(c.hourCounts[9] == 3 && c.hourCounts[14] == 5)
    }

    @Test func deviceStatsRoundTripsThroughCKRecord() throws {
        let d = DeviceDailyStats(deviceID: "dev-1", deviceName: "Studio",
                                 days: [DailyCount(day: Date(timeIntervalSince1970: 86_400), count: 3)],
                                 hourCounts: (0..<24).map { $0 })
        let ck = RecordMapper.record(for: d, in: zone, systemFields: nil)
        #expect(ck.recordType == SyncRecordType.deviceStats.rawValue)
        #expect(ck.recordID.recordName == d.recordName)
        let back = try #require(RecordMapper.deviceStats(from: ck))
        #expect(back == d)
        #expect(back.contentHash == d.contentHash)
    }

    @Test func deviceStatsBuiltFromLocalStatsMirrorsHistory() {
        let s = localStats([0: 2])
        let d = DeviceDailyStats(from: s, deviceID: "x", deviceName: "n")
        #expect(d.days.map(\.count) == [2])
        #expect(d.hourCounts == s.hourCounts)
    }

    @Test func ownRecordIsNeverTreatedAsRemote() {
        #expect(!CloudSyncEngine.shouldKeepRemoteDeviceStats(deviceID: DeviceIdentity.current))
        #expect(CloudSyncEngine.shouldKeepRemoteDeviceStats(deviceID: "other"))
    }

    @Test func malformedDeviceStatsRecordDecodesToNil() {
        let ck = CKRecord(recordType: SyncRecordType.deviceStats.rawValue,
                          recordID: CKRecord.ID(recordName: "stats|x", zoneID: zone))
        #expect(RecordMapper.deviceStats(from: ck) == nil)
    }
}

@MainActor
@Suite("Sync gaps: mirrored session credits once")
struct MirroredCreditTests {
    @Test func mirroredFocusCompletionDoesNotCreditLocalStats() async {
        let timer = PomodoroTimer()
        let before = timer.stats.completedFocus
        let now = Date()
        timer.applyMirroredSession(phase: .focus, isPaused: false,
                                   startedAt: now.addingTimeInterval(-1500),
                                   endsAt: now.addingTimeInterval(0.05),
                                   asOf: now, now: now)
        #expect(timer.isMirroredSession)
        for _ in 0..<40 where timer.phase == .focus {
            try? await Task.sleep(for: .milliseconds(100))
        }
        #expect(timer.phase != .focus, "the mirrored focus must have completed")
        #expect(timer.stats.completedFocus == before,
                "only the owner Mac credits; the follower sees it via the synced per-device counts")
    }
}
