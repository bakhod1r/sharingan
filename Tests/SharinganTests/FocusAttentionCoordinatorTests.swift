import Testing
import Foundation
@testable import SharinganCore

@MainActor
private final class FakeAttentionSource: AttentionSampleSource {
    var startCount = 0
    var stopCount = 0
    func start(onSample: @escaping @MainActor (AttentionSample) -> Void) { startCount += 1 }
    func stop() { stopCount += 1 }
}

@MainActor
private final class FakeAttentionPresenter: AttentionAlertPresenter {
    var shows: [(AttentionState, String?)] = []
    var hideCount = 0
    var isShowing: Bool { shows.count > hideCount && lastWasShow }
    private var lastWasShow = false
    func showAttentionAlert(state: AttentionState, taskTitle: String?) {
        shows.append((state, taskTitle)); lastWasShow = true
    }
    func hideAttentionAlert() { hideCount += 1; lastWasShow = false }
}

@MainActor
@Suite("Focus attention coordinator wiring", .serialized)
struct FocusAttentionCoordinatorTests {
    private let t0 = Date(timeIntervalSince1970: 2_000_000)

    private struct Rig {
        let c: SharinganCoordinator
        let store: TaskStore
        let att: FocusAttentionService
        let source: FakeAttentionSource
        let presenter: FakeAttentionPresenter
        let cleanup: () -> Void
    }

    private func makeRig(enabled: Bool = true) -> Rig {
        let name = "blink-attention-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = TaskStore(fileURL: dir.appendingPathComponent("tasks.json"))
        let source = FakeAttentionSource()
        let presenter = FakeAttentionPresenter()
        let att = FocusAttentionService(source: source)
        att.presenter = presenter
        let timer = PomodoroTimer()
        let savedSettings = timer.settings
        timer.settings.focusAttentionEnabled = enabled
        let c = SharinganCoordinator(timer: timer,
                                     focusQueue: FocusQueue(defaults: defaults),
                                     taskStore: store, focusAttention: att)
        return Rig(c: c, store: store, att: att, source: source, presenter: presenter,
                   cleanup: {
            att.release()
            timer.stop()
            timer.settings = savedSettings
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: dir)
        })
    }

    private func drain() async {
        await withCheckedContinuation { cont in DispatchQueue.main.async { cont.resume() } }
    }

    private func sample(_ t: Double, away: Bool) -> AttentionSample {
        AttentionSample(faceDetected: true, yaw: away ? 60 : 0,
                        at: t0.addingTimeInterval(t))
    }

    /// 10 fps frames over [from, to].
    private func feed(_ r: Rig, from: Double, to: Double, away: Bool) {
        var t = from
        while t <= to + 1e-9 {
            r.att.now = { [t0] in t0.addingTimeInterval(t) }
            r.att.ingest(sample(t, away: away))
            t += 0.1
        }
    }

    /// Starts a focus session and drives it into the alert (timer paused by guard).
    private func startAndAlert(_ r: Rig) async {
        r.c.timer.start(); await drain()
        feed(r, from: 0, to: 3, away: true)
        await drain()
    }

    @Test func alertPausesTimer() async {
        let r = makeRig(); defer { r.cleanup() }
        var t = TaskItem(title: "Write report"); t.allowedApps = []
        r.store.insert(t); r.store.setActive(t.id)
        await startAndAlert(r)
        #expect(r.source.startCount == 1)
        #expect(r.att.pausedByGuard)
        #expect(!r.c.timer.isRunning)
        #expect(r.c.timer.phase == .paused)
        #expect(r.presenter.isShowing)
        #expect(r.presenter.shows.last?.1 == "Write report")
    }

    @Test func lookingBackResumesTimer() async {
        let r = makeRig(); defer { r.cleanup() }
        await startAndAlert(r)
        feed(r, from: 3.1, to: 4.5, away: false)
        await drain()
        #expect(!r.att.pausedByGuard)
        #expect(r.c.timer.isRunning)
        #expect(r.c.timer.phase == .focus)
        #expect(!r.presenter.isShowing)
        #expect(r.att.isEngaged)
    }

    @Test func manualPauseReleasesAndNeverAutoResumes() async {
        let r = makeRig(); defer { r.cleanup() }
        r.c.timer.start(); await drain()
        r.c.timer.pause(); await drain()
        #expect(!r.att.isEngaged)
        #expect(!r.att.pausedByGuard)
        feed(r, from: 0, to: 3, away: true)
        feed(r, from: 3.1, to: 5, away: false)
        await drain()
        #expect(!r.c.timer.isRunning)
        #expect(r.c.timer.phase == .paused)
    }

    @Test func manualResumeWhileGuardPausedClearsFlagAndStaysEngaged() async {
        let r = makeRig(); defer { r.cleanup() }
        await startAndAlert(r)
        r.c.timer.start(); await drain()
        #expect(r.c.timer.isRunning)
        #expect(!r.att.pausedByGuard)
        #expect(r.att.isEngaged)
        #expect(r.att.state == .attentive)
        #expect(!r.presenter.isShowing)
    }

    @Test func stopWhileGuardPausedReleases() async {
        let r = makeRig(); defer { r.cleanup() }
        await startAndAlert(r)
        r.c.timer.stop(); await drain()
        #expect(!r.att.isEngaged)
        #expect(!r.att.pausedByGuard)
        #expect(!r.c.timer.isRunning)
        #expect(!r.presenter.isShowing)
    }

    @Test func skipToBreakReleases() async {
        let r = makeRig(); defer { r.cleanup() }
        r.c.timer.start(); await drain()
        r.c.timer.skip(); await drain()
        #expect(r.c.timer.phase.isBreak)
        #expect(!r.att.isEngaged)
    }

    @Test func settingOffReleasesRunningSession() async {
        let r = makeRig(); defer { r.cleanup() }
        r.c.timer.start(); await drain()
        #expect(r.att.isEngaged)
        r.c.timer.settings.focusAttentionEnabled = false; await drain()
        #expect(!r.att.isEngaged)
        #expect(r.c.timer.isRunning)
    }

    @Test func settingOffWhileGuardPausedReleasesAndResumes() async {
        let r = makeRig(); defer { r.cleanup() }
        await startAndAlert(r)
        r.c.timer.settings.focusAttentionEnabled = false; await drain()
        #expect(!r.att.isEngaged)
        #expect(!r.presenter.isShowing)
        #expect(r.c.timer.isRunning)
    }

    @Test func disabledSettingNeverEngages() async {
        let r = makeRig(enabled: false); defer { r.cleanup() }
        r.c.timer.start(); await drain()
        #expect(!r.att.isEngaged)
        #expect(r.source.startCount == 0)
    }

    @Test func trackingStaysEngagedWhilePausedByGuard() async {
        let r = makeRig(); defer { r.cleanup() }
        await startAndAlert(r)
        #expect(r.att.isEngaged)
        #expect(r.source.startCount == 1)
        #expect(r.source.stopCount == 0)
    }

    @Test func snoozeLiftsGuardPause() async {
        let r = makeRig(); defer { r.cleanup() }
        await startAndAlert(r)
        r.att.snooze(); await drain()
        #expect(r.c.timer.isRunning)
        #expect(!r.att.pausedByGuard)
        #expect(!r.presenter.isShowing)
        // No alert while snoozed.
        feed(r, from: 3.1, to: 7, away: true)
        #expect(r.att.state == .attentive)
    }

    // MARK: - Per-task guard ("Always guard" off)

    private func guardedTask(_ on: Bool, _ title: String = "T") -> TaskItem {
        var t = TaskItem(title: title); t.attentionGuard = on; return t
    }

    @Test func taskFlagEngagesWhenAlwaysOff() async {
        let r = makeRig(enabled: false); defer { r.cleanup() }
        let t = guardedTask(true); r.store.insert(t); r.store.setActive(t.id)
        r.c.timer.start(); await drain()
        #expect(r.att.isEngaged)
        #expect(r.source.startCount == 1)
    }

    @Test func noFlagAndAlwaysOffDoesNotEngage() async {
        let r = makeRig(enabled: false); defer { r.cleanup() }
        let t = guardedTask(false); r.store.insert(t); r.store.setActive(t.id)
        r.c.timer.start(); await drain()
        #expect(!r.att.isEngaged)
        #expect(r.source.startCount == 0)
    }

    @Test func alwaysOnEngagesRegardlessOfTask() async {
        let r = makeRig(enabled: true); defer { r.cleanup() }
        let t = guardedTask(false); r.store.insert(t); r.store.setActive(t.id)
        r.c.timer.start(); await drain()
        #expect(r.att.isEngaged)
    }

    @Test func turningTaskFlagOffWhileGuardPausedReleasesAndResumes() async {
        let r = makeRig(enabled: false); defer { r.cleanup() }
        let t = guardedTask(true); r.store.insert(t); r.store.setActive(t.id)
        await startAndAlert(r)
        #expect(r.att.pausedByGuard)
        var edited = t; edited.attentionGuard = false
        r.store.update(edited); await drain()
        #expect(!r.att.isEngaged)
        #expect(!r.presenter.isShowing)
        #expect(r.c.timer.isRunning)
    }

    @Test func switchingToUnguardedTaskReleases() async {
        let r = makeRig(enabled: false); defer { r.cleanup() }
        let a = guardedTask(true, "A"), b = guardedTask(false, "B")
        r.store.insert(a); r.store.insert(b); r.store.setActive(a.id)
        r.c.timer.start(); await drain()
        #expect(r.att.isEngaged)
        r.store.setActive(b.id); await drain()
        #expect(!r.att.isEngaged)
        #expect(r.c.timer.isRunning)
    }

    @Test func switchingWhileGuardPausedToUnguardedTaskResumes() async {
        let r = makeRig(enabled: false); defer { r.cleanup() }
        let a = guardedTask(true, "A"), b = guardedTask(false, "B")
        r.store.insert(a); r.store.insert(b); r.store.setActive(a.id)
        await startAndAlert(r)
        r.store.setActive(b.id); await drain()
        #expect(!r.att.isEngaged)
        #expect(r.c.timer.isRunning)
    }
}
