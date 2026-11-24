import Testing
import Foundation
@testable import SharinganCore

@MainActor
final class FakeFocusLockPresenter: FocusLockPresenter {
    var showCount = 0
    var hideCount = 0
    var lastBackTarget: BlockedApp?
    var lastShown: FocusLock?
    var accepts = true
    func showLock(_ lock: FocusLock, backTarget: BlockedApp?) -> Bool {
        showCount += 1
        lastBackTarget = backTarget
        lastShown = lock
        return accepts
    }
    func hideLock() { hideCount += 1 }
}

@MainActor
@Suite("FocusLockService")
struct FocusLockServiceTests {
    private let vscode = BlockedApp(bundleID: "com.microsoft.VSCode", name: "VS Code")
    private let xcode = BlockedApp(bundleID: "com.apple.dt.Xcode", name: "Xcode")
    private let taskID = UUID()

    private func makeLock(id: UUID? = nil, apps: [BlockedApp]? = nil) -> FocusLock {
        FocusLock(taskID: id ?? taskID, taskTitle: "Write", allowedApps: apps ?? [vscode])
    }

    private final class Box { var scheduled: [(TimeInterval, @MainActor () -> Void)] = []; var date = Date(timeIntervalSince1970: 1_000_000); var front: String? }

    private func make() -> (FocusLockService, FakeFocusLockPresenter, Box) {
        let box = Box()
        let s = FocusLockService()
        let p = FakeFocusLockPresenter()
        s.presenter = p
        s.now = { box.date }
        s.ownBundleID = "app.sharingan"
        s.canResolve = { _ in true }
        s.frontmostBundleID = { box.front }
        s.schedule = { d, f in box.scheduled.append((d, f)) }
        withExtendedLifetime(p) {}
        return (s, p, box)
    }

    @Test func blockedActivationShowsLock() {
        let (s, p, _) = make()
        s.engage(makeLock())
        s.handleActivation(bundleID: "com.google.Chrome")
        #expect(p.showCount == 1)
        #expect(s.isShowing)
        #expect(p.lastBackTarget == vscode)
        s.release()
    }

    @Test func refusedShowDoesNotStickIsShowing() {
        let (s, p, _) = make()
        p.accepts = false
        s.engage(makeLock())
        s.handleActivation(bundleID: "com.google.Chrome")
        #expect(!s.isShowing)
        p.accepts = true
        s.handleActivation(bundleID: "com.google.Chrome")
        #expect(s.isShowing)
        #expect(p.showCount == 2)
        s.release()
    }

    @Test func recheckShowsAfterRefusal() {
        let (s, p, box) = make()
        box.front = "com.google.Chrome"
        p.accepts = false
        s.engage(makeLock())
        #expect(!s.isShowing)
        p.accepts = true
        s.recheck()
        #expect(s.isShowing)
        s.release()
    }

    @Test func allowedActivationHidesLock() {
        let (s, p, _) = make()
        s.engage(makeLock())
        s.handleActivation(bundleID: "com.google.Chrome")
        s.handleActivation(bundleID: "com.microsoft.VSCode")
        #expect(p.hideCount == 1)
        #expect(!s.isShowing)
        s.handleActivation(bundleID: "com.microsoft.VSCode")
        #expect(p.hideCount == 1)
        s.release()
    }

    @Test func repeatedBlockedActivationShowsOnce() {
        let (s, p, _) = make()
        s.engage(makeLock())
        s.handleActivation(bundleID: "com.google.Chrome")
        s.handleActivation(bundleID: "com.google.Chrome")
        #expect(p.showCount == 1)
        s.release()
    }

    @Test func snoozeThenExpiry() {
        let (s, p, box) = make()
        s.engage(makeLock())
        s.snooze()
        s.handleActivation(bundleID: "com.google.Chrome")
        #expect(p.showCount == 0)
        box.date.addTimeInterval(301)
        s.handleActivation(bundleID: "com.google.Chrome")
        #expect(p.showCount == 1)
        s.release()
    }

    @Test func snoozeHidesShowingOverlay() {
        let (s, p, _) = make()
        s.engage(makeLock())
        s.handleActivation(bundleID: "com.google.Chrome")
        s.snooze()
        #expect(p.hideCount == 1)
        #expect(!s.isShowing)
        s.release()
    }

    @Test func releaseHidesAndIgnoresActivations() {
        let (s, p, _) = make()
        s.engage(makeLock())
        s.handleActivation(bundleID: "com.google.Chrome")
        s.release()
        #expect(p.hideCount == 1)
        #expect(s.lock == nil)
        s.handleActivation(bundleID: "com.google.Chrome")
        #expect(p.showCount == 1)
    }

    @Test func taskSwitchResetsSnooze() {
        let (s, p, _) = make()
        s.engage(makeLock())
        s.snooze()
        s.engage(makeLock(id: UUID()))
        s.handleActivation(bundleID: "com.google.Chrome")
        #expect(p.showCount == 1)
        s.release()
    }

    @Test func sameLockEngageIsNoOp() {
        let (s, p, box) = make()
        box.front = "com.google.Chrome"
        s.engage(makeLock())
        #expect(p.showCount == 1)
        s.engage(makeLock())
        #expect(p.showCount == 1)
        s.release()
    }

    @Test func engageEvaluatesFrontmost() {
        let (s, p, box) = make()
        box.front = "com.microsoft.VSCode"
        s.engage(makeLock())
        #expect(p.showCount == 0)
        s.release()
    }

    @Test func sameTaskNewAllowedAppsKeepsSnoozeAndReevaluates() {
        let (s, p, box) = make()
        s.engage(makeLock())
        box.front = "com.google.Chrome"
        s.handleActivation(bundleID: "com.google.Chrome")
        #expect(p.showCount == 1)
        box.front = "com.google.Chrome"
        s.engage(makeLock(apps: [vscode, BlockedApp(bundleID: "com.google.Chrome", name: "Chrome")]))
        #expect(p.hideCount == 1)
        #expect(!s.isShowing)
        s.snooze()
        s.engage(makeLock(apps: [xcode]))
        #expect(s.snoozedUntil != nil)
        s.release()
    }

    @Test func backTargetSkipsUnresolvable() {
        let (s, _, _) = make()
        let lock = makeLock(apps: [vscode, xcode])
        s.canResolve = { $0 != "com.microsoft.VSCode" }
        #expect(s.backTarget(for: lock) == xcode)
        s.canResolve = { _ in false }
        #expect(s.backTarget(for: lock) == nil)
    }

    @Test func lockChangeWhileShowingReshowsWithNewTitle() {
        let (s, p, box) = make()
        box.front = "com.google.Chrome"
        s.engage(makeLock())
        #expect(p.showCount == 1)
        let b = FocusLock(taskID: UUID(), taskTitle: "Other", allowedApps: [xcode])
        s.engage(b)
        #expect(p.lastShown == b)
        #expect(p.lastBackTarget == xcode)
        #expect(s.isShowing)
        #expect(p.hideCount == 1)
        s.release()
    }

    @Test func snoozeExpiryRechecksFrontmost() {
        let (s, p, box) = make()
        box.front = "com.google.Chrome"
        s.engage(makeLock())
        s.snooze()
        #expect(p.showCount == 1)
        #expect(box.scheduled.count == 1)
        #expect(box.scheduled[0].0 == FocusLockPolicy.snoozeDuration)
        box.date.addTimeInterval(301)
        box.scheduled[0].1()
        #expect(p.showCount == 2)
        #expect(s.isShowing)
        s.release()
    }

    @Test func releaseCancelsSnoozeRecheck() {
        let (s, p, box) = make()
        box.front = "com.google.Chrome"
        s.engage(makeLock())
        s.snooze()
        s.release()
        box.date.addTimeInterval(301)
        box.scheduled[0].1()
        #expect(p.showCount == 1)
    }

    @Test func newSnoozeIgnoresOldRecheck() {
        let (s, p, box) = make()
        box.front = "com.google.Chrome"
        s.engage(makeLock())
        s.snooze()
        box.date.addTimeInterval(200)
        s.snooze()
        box.date.addTimeInterval(101)
        box.scheduled[0].1()
        #expect(p.showCount == 1)
        s.release()
    }
}
