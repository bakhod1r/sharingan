import Testing
import Foundation
import AppKit
@testable import SharinganCore

@MainActor
@Suite("FocusLock coordinator wiring", .serialized)
struct FocusLockCoordinatorTests {
    private let vscode = BlockedApp(bundleID: "com.microsoft.VSCode", name: "VS Code")
    private let chrome = BlockedApp(bundleID: "com.google.Chrome", name: "Chrome")

    private final class Box { var front: String? }

    private struct Rig {
        let c: SharinganCoordinator
        let store: TaskStore
        let presenter: FakeFocusLockPresenter
        let box: Box
        let focus: FocusLockService
        let blocker: AppBlockerService
        let cleanup: () -> Void
    }

    private func makeRig() -> Rig {
        let name = "blink-focuslock-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = TaskStore(fileURL: dir.appendingPathComponent("tasks.json"))
        let box = Box()
        let presenter = FakeFocusLockPresenter()
        let svc = FocusLockService()
        svc.presenter = presenter
        svc.ownBundleID = "app.sharingan"
        svc.canResolve = { _ in true }
        svc.frontmostBundleID = { box.front }
        let blocker = AppBlockerService()
        let c = SharinganCoordinator(timer: PomodoroTimer(),
                                     focusQueue: FocusQueue(defaults: defaults),
                                     taskStore: store, focusLock: svc, appBlocker: blocker)
        return Rig(c: c, store: store, presenter: presenter, box: box,
                   focus: svc, blocker: blocker, cleanup: {
            svc.release()
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: dir)
        })
    }

    private func drain() async {
        await withCheckedContinuation { cont in DispatchQueue.main.async { cont.resume() } }
    }

    private func addActiveTask(_ r: Rig, apps: [BlockedApp]) -> UUID {
        var t = TaskItem(title: "Write")
        t.allowedApps = apps
        r.store.insert(t)
        r.store.setActive(t.id)
        return t.id
    }

    @Test func engagesOnFocusStart() async {
        let r = makeRig(); defer { r.cleanup() }
        _ = addActiveTask(r, apps: [vscode])
        r.c.timer.start()
        await drain()
        #expect(r.focus.lock != nil)
        #expect(r.blocker.exemptBundleIDs == ["com.microsoft.vscode"])
    }

    @Test func releasesOnPause() async {
        let r = makeRig(); defer { r.cleanup() }
        _ = addActiveTask(r, apps: [vscode])
        r.c.timer.start(); await drain()
        r.c.timer.pause(); await drain()
        #expect(r.focus.lock == nil)
        #expect(r.blocker.exemptBundleIDs.isEmpty)
    }

    @Test func releasesOnBreak() async {
        let r = makeRig(); defer { r.cleanup() }
        _ = addActiveTask(r, apps: [vscode])
        r.c.timer.start(); await drain()
        r.c.timer.skip(); await drain()
        #expect(r.c.timer.phase.isBreak)
        #expect(r.focus.lock == nil)
    }

    @Test func releasesWhenActiveTaskCleared() async {
        let r = makeRig(); defer { r.cleanup() }
        _ = addActiveTask(r, apps: [vscode])
        r.c.timer.start(); await drain()
        #expect(r.focus.lock != nil)
        r.store.setActive(nil); await drain()
        #expect(r.focus.lock == nil)
    }

    @Test func editingAllowedAppsReevaluates() async {
        let r = makeRig(); defer { r.cleanup() }
        let id = addActiveTask(r, apps: [vscode])
        r.box.front = "com.google.Chrome"
        r.c.timer.start(); await drain()
        #expect(r.focus.isShowing)
        var t = r.store.tasks.first { $0.id == id }!
        t.allowedApps.append(chrome)
        r.store.update(t); await drain()
        #expect(!r.focus.isShowing)
        #expect(r.blocker.exemptBundleIDs.contains("com.google.chrome"))
    }
}
