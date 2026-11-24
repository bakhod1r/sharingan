import Testing
import Foundation
@testable import SharinganCore

@Suite("FocusLockPolicy")
struct FocusLockPolicyTests {
    private let vscode = BlockedApp(bundleID: "com.microsoft.VSCode", name: "VS Code")

    private func task(_ apps: [BlockedApp]) -> TaskItem {
        TaskItem(title: "Write", allowedApps: apps)
    }

    private func sampleLock() -> FocusLock {
        FocusLock(taskID: UUID(), taskTitle: "Write", allowedApps: [vscode])
    }

    @Test func lockRequiresRunningFocus() {
        let t = task([vscode])
        #expect(FocusLockPolicy.lock(activeTask: t, phase: .focus, isRunning: true) != nil)
        #expect(FocusLockPolicy.lock(activeTask: t, phase: .focus, isRunning: false) == nil)
        #expect(FocusLockPolicy.lock(activeTask: t, phase: .shortBreak, isRunning: true) == nil)
        #expect(FocusLockPolicy.lock(activeTask: t, phase: .longBreak, isRunning: true) == nil)
    }

    @Test func noLockWithoutAllowedApps() {
        #expect(FocusLockPolicy.lock(activeTask: task([]), phase: .focus, isRunning: true) == nil)
        let off = BlockedApp(bundleID: "a.b", name: "A", isEnabled: false)
        #expect(FocusLockPolicy.lock(activeTask: task([off]), phase: .focus, isRunning: true) == nil)
    }

    @Test func noLockForDoneOrTrashedTask() {
        var t = task([vscode])
        t.isDone = true
        #expect(FocusLockPolicy.lock(activeTask: t, phase: .focus, isRunning: true) == nil)
        var u = task([vscode])
        u.trashedAt = Date()
        #expect(FocusLockPolicy.lock(activeTask: u, phase: .focus, isRunning: true) == nil)
        #expect(FocusLockPolicy.lock(activeTask: nil, phase: .focus, isRunning: true) == nil)
    }

    @Test func allowedAppNotBlocked() {
        #expect(!FocusLockPolicy.shouldBlock(bundleID: "com.microsoft.vscode", lock: sampleLock(),
                                             ownBundleID: nil, snoozedUntil: nil, now: Date()))
    }

    @Test func otherAppBlocked() {
        #expect(FocusLockPolicy.shouldBlock(bundleID: "com.google.Chrome", lock: sampleLock(),
                                            ownBundleID: nil, snoozedUntil: nil, now: Date()))
    }

    @Test func ownAndSystemAppsNeverBlocked() {
        let l = sampleLock()
        let now = Date()
        #expect(!FocusLockPolicy.shouldBlock(bundleID: "com.sharingan.app", lock: l,
                                             ownBundleID: "com.sharingan.app", snoozedUntil: nil, now: now))
        for id in FocusLockPolicy.systemBundleIDs {
            #expect(!FocusLockPolicy.shouldBlock(bundleID: id, lock: l, ownBundleID: nil, snoozedUntil: nil, now: now))
        }
        #expect(!FocusLockPolicy.shouldBlock(bundleID: nil, lock: l, ownBundleID: nil, snoozedUntil: nil, now: now))
    }

    @Test func extraSystemUIAgentsNeverBlocked() {
        let l = sampleLock()
        let now = Date()
        for id in ["com.apple.ScreenSaver.Engine", "com.apple.LocalAuthentication.UIAgent",
                   "com.apple.coreservices.uiagent", "com.apple.systempreferences", "COM.APPLE.DOCK"] {
            #expect(!FocusLockPolicy.shouldBlock(bundleID: id, lock: l, ownBundleID: nil, snoozedUntil: nil, now: now), "\(id)")
        }
    }

    @Test func snoozeSuppressesBlock() {
        let now = Date()
        #expect(!FocusLockPolicy.shouldBlock(bundleID: "com.google.Chrome", lock: sampleLock(),
                                             ownBundleID: nil, snoozedUntil: now + 60, now: now))
    }

    @Test func snoozeExpires() {
        let now = Date()
        #expect(FocusLockPolicy.shouldBlock(bundleID: "com.google.Chrome", lock: sampleLock(),
                                            ownBundleID: nil, snoozedUntil: now - 1, now: now))
    }

    @Test func decodesWithoutAllowedAppsKey() throws {
        let data = try JSONEncoder().encode(TaskItem(title: "x"))
        var obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        obj.removeValue(forKey: "allowedApps")
        let stripped = try JSONSerialization.data(withJSONObject: obj)
        let decoded = try JSONDecoder().decode(TaskItem.self, from: stripped)
        #expect(decoded.allowedApps == [])
    }
}
