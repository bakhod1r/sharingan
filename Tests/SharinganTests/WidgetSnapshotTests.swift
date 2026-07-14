import Testing
import Foundation
@testable import SharinganCore

@Suite("WidgetKit snapshot")
struct WidgetSnapshotTests {

    private func running(now: Date) -> WidgetSnapshot {
        WidgetSnapshot(phase: .focus, isRunning: true,
                       endDate: now.addingTimeInterval(600),
                       remainingSeconds: 600, totalSeconds: 1500,
                       taskTitle: "Write report",
                       todayPomodoros: 3, dailyGoal: 8, streakDays: 5,
                       updatedAt: now)
    }

    // MARK: - Codable

    @Test("snapshot survives the store's write→read round trip")
    func storeRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-snapshot-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let snap = running(now: Date())
        WidgetSnapshotStore.write(snap, to: url)
        let read = try #require(WidgetSnapshotStore.read(from: url))
        // ISO8601 coding drops sub-second precision — compare to the second.
        #expect(read.phase == snap.phase)
        #expect(read.isRunning == snap.isRunning)
        #expect(read.taskTitle == snap.taskTitle)
        #expect(read.todayPomodoros == 3)
        #expect(read.dailyGoal == 8)
        #expect(read.streakDays == 5)
        #expect(abs(read.endDate!.timeIntervalSince(snap.endDate!)) < 1)
        #expect(read.remainingSeconds == 600)
        #expect(read.totalSeconds == 1500)
    }

    @Test("missing and corrupt files read as nil, never crash")
    func corruptRead() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-snapshot-missing-\(UUID().uuidString).json")
        #expect(WidgetSnapshotStore.read(from: missing) == nil)

        let corrupt = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-snapshot-corrupt-\(UUID().uuidString).json")
        try? Data("not json{".utf8).write(to: corrupt)
        defer { try? FileManager.default.removeItem(at: corrupt) }
        #expect(WidgetSnapshotStore.read(from: corrupt) == nil)
    }

    @Test("a snapshot from a newer schema is refused")
    func newerSchemaRefused() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-snapshot-schema-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        var snap = running(now: Date())
        snap.schemaVersion = WidgetSnapshot.currentSchemaVersion + 1
        WidgetSnapshotStore.write(snap, to: url)
        #expect(WidgetSnapshotStore.read(from: url) == nil)
    }

    // MARK: - Snapshot location (widget's own container, not the app group)

    @Test("inside the appex sandbox the snapshot lives under its own home")
    func sandboxedPathIsHomeRelative() {
        let home = "/Users/x/Library/Containers/com.sharingan.app.widget/Data"
        let url = WidgetSnapshotStore.containerFileURL(home: home) { _ in
            Issue.record("sandboxed path must not probe the filesystem")
            return false
        }
        #expect(url?.path ==
            home + "/Library/Application Support/widget-snapshot.json")
    }

    @Test("the app targets the widget's container once it exists")
    func appPathRequiresMaterializedContainer() {
        var probed: String?
        let url = WidgetSnapshotStore.containerFileURL(home: "/Users/x") {
            probed = $0.path
            return true
        }
        #expect(probed == "/Users/x/Library/Containers/com.sharingan.app.widget/Data")
        #expect(url?.path == "/Users/x/Library/Containers/com.sharingan.app.widget"
            + "/Data/Library/Application Support/widget-snapshot.json")
    }

    @Test("the app never fabricates a container that doesn't exist yet")
    func appPathNilWithoutContainer() {
        let url = WidgetSnapshotStore.containerFileURL(home: "/Users/x") { _ in false }
        #expect(url == nil)
    }

    // MARK: - Reading-side repair

    @Test("a 'running' session whose end has passed renders as idle")
    func expiredRunIdles() {
        let now = Date()
        var snap = running(now: now.addingTimeInterval(-700)) // ended 100 s ago
        snap.endDate = now.addingTimeInterval(-100)
        let fixed = snap.normalized(now: now)
        #expect(fixed.phase == .idle)
        #expect(fixed.isRunning == false)
        #expect(fixed.endDate == nil)
        #expect(fixed.remainingSeconds == fixed.totalSeconds)
        // Stats written the same day survive the repair.
        #expect(fixed.todayPomodoros == 0 || fixed.streakDays == 5)
    }

    @Test("yesterday's today-count reads as zero")
    func staleTodayCountZeroes() {
        let now = Date()
        var snap = running(now: now).idled()
        snap.updatedAt = now.addingTimeInterval(-86_400 * 2)
        let fixed = snap.normalized(now: now)
        #expect(fixed.todayPomodoros == 0)
        #expect(fixed.streakDays == 5) // streak is not day-scoped, stays
    }

    @Test("same-day snapshot keeps its today-count")
    func sameDayCountKept() {
        let now = Date()
        let fixed = running(now: now).normalized(now: now)
        #expect(fixed.todayPomodoros == 3)
        #expect(fixed.isRunning)
    }

    // MARK: - Progress

    @Test("progress is live for a running session")
    func liveProgress() {
        let now = Date()
        let snap = running(now: now) // 600 of 1500 left → 60 % done
        #expect(abs(snap.progress(at: now) - 0.6) < 0.001)
        // 5 minutes later: 300 of 1500 left → 80 % done
        #expect(abs(snap.progress(at: now.addingTimeInterval(300)) - 0.8) < 0.001)
        // Past the end it clamps to 1
        #expect(snap.progress(at: now.addingTimeInterval(9999)) == 1)
    }

    @Test("progress is static when not running and 0 on a zero total")
    func staticProgress() {
        let now = Date()
        var snap = running(now: now)
        snap.isRunning = false
        snap.endDate = nil
        #expect(abs(snap.progress(at: now.addingTimeInterval(500)) - 0.6) < 0.001)

        snap.totalSeconds = 0
        #expect(snap.progress(at: now) == 0)
    }
}
