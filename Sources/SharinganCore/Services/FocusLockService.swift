import Foundation
import AppKit

@MainActor
public protocol FocusLockPresenter: AnyObject {
    func showLock(_ lock: FocusLock, backTarget: BlockedApp?)
    func hideLock()
}

/// Watches app activation during a focus session and asks the presenter to
/// show a reminder overlay when an app outside the task's allowlist comes forward.
@MainActor
public final class FocusLockService: ObservableObject {
    public static let shared = FocusLockService()

    public weak var presenter: FocusLockPresenter?
    @Published public private(set) var lock: FocusLock?
    @Published public private(set) var isShowing: Bool = false
    public private(set) var snoozedUntil: Date?

    public var now: () -> Date = Date.init
    public var ownBundleID: String? = Bundle.main.bundleIdentifier
    public var canResolve: (String) -> Bool = {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
    }
    public var frontmostBundleID: () -> String? = {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    private var workspaceObserver: NSObjectProtocol?

    public init() {}

    public func engage(_ newLock: FocusLock) {
        if let current = lock {
            if current == newLock { return }
            if current.taskID != newLock.taskID { snoozedUntil = nil }
        } else {
            snoozedUntil = nil
        }
        lock = newLock
        if workspaceObserver == nil { startWatching() }
        handleActivation(bundleID: frontmostBundleID())
    }

    public func release() {
        stopWatching()
        hideIfShowing()
        lock = nil
        snoozedUntil = nil
    }

    public func snooze() {
        snoozedUntil = now().addingTimeInterval(FocusLockPolicy.snoozeDuration)
        hideIfShowing()
    }

    public func handleActivation(bundleID: String?) {
        guard let lock else { return }
        let blocked = FocusLockPolicy.shouldBlock(
            bundleID: bundleID, lock: lock, ownBundleID: ownBundleID,
            snoozedUntil: snoozedUntil, now: now())
        if blocked {
            guard !isShowing else { return }
            isShowing = true
            presenter?.showLock(lock, backTarget: backTarget(for: lock))
        } else {
            hideIfShowing()
        }
    }

    public func backTarget(for lock: FocusLock) -> BlockedApp? {
        lock.allowedApps.first { $0.isEnabled && canResolve($0.bundleID) }
    }

    private func hideIfShowing() {
        guard isShowing else { return }
        isShowing = false
        presenter?.hideLock()
    }

    private func startWatching() {
        stopWatching()
        workspaceObserver = NSWorkspace.shared.notificationCenter
            .addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                         object: nil, queue: .main)
        { [weak self] note in
            MainActor.assumeIsolated {
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                self?.handleActivation(bundleID: app?.bundleIdentifier)
            }
        }
    }

    private func stopWatching() {
        if let obs = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            workspaceObserver = nil
        }
    }
}
