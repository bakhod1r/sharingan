import Foundation
import AppKit

/// AppBlockerService — break vaqtida ekranga chiqqan bloklangan applarni
/// monitor qiladi. NSWorkspace.frontmostApplicationDidChange notification
/// orqali yangi app frontmost bo'lganda tekshiradi.
@MainActor
public final class AppBlockerService: ObservableObject {
    public static let shared = AppBlockerService()

    @Published public var settings: AppBlockerSettings = .init()
    @Published public private(set) var isActive: Bool = false
    @Published public private(set) var lastBlockedApp: String?

    private var workspaceObserver: NSObjectProtocol?
    /// Apps we hid during the block, so they can be un-hidden when it ends.
    private var hiddenApps: [NSRunningApplication] = []

    /// Lowercased bundle IDs the active focus lock allows. They stay usable even
    /// when also on the blocklist.
    public var exemptBundleIDs: Set<String> = [] {
        didSet {
            let lowered = Set(exemptBundleIDs.map { $0.lowercased() })
            if lowered != exemptBundleIDs { exemptBundleIDs = lowered }
        }
    }

    public init() {}

    /// Blocklist match, minus the focus-lock exemption.
    public func shouldHide(bundleID: String) -> Bool {
        guard settings.matches(bundleID: bundleID) else { return false }
        return !exemptBundleIDs.contains(bundleID.lowercased())
    }

    public func activate() {
        guard settings.enabled else { return }
        guard !isActive else { return }
        isActive = true
        startWatching()
        killExisting()
    }

    public func deactivate() {
        guard isActive else { return }
        isActive = false
        stopWatching()
        // Un-hide everything we hid, otherwise the user's apps stay stuck hidden
        // after the break with no automatic recovery.
        for app in hiddenApps where !app.isTerminated {
            app.unhide()
        }
        hiddenApps.removeAll()
    }

    public func update(_ s: AppBlockerSettings) {
        self.settings = s
    }

    // MARK: - Watch frontmost changes

    private func startWatching() {
        stopWatching()
        workspaceObserver = NSWorkspace.shared.notificationCenter
            .addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                         object: nil, queue: .main)
        { [weak self] note in
            MainActor.assumeIsolated {
                self?.handleAppActivation(note)
            }
        }
    }

    private func stopWatching() {
        if let obs = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            workspaceObserver = nil
        }
    }

    private func handleAppActivation(_ note: Notification) {
        guard isActive else { return }
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        let bid = app.bundleIdentifier ?? ""
        if shouldHide(bundleID: bid) {
            lastBlockedApp = app.localizedName ?? bid
            if settings.killOnFrontmost {
                killApp(app)
            } else {
                hideApp(app)
            }
        }
    }

    // MARK: - App control

    private func hideApp(_ app: NSRunningApplication) {
        if !hiddenApps.contains(where: { $0.processIdentifier == app.processIdentifier }) {
            hiddenApps.append(app)
        }
        app.hide()
    }

    private func killApp(_ app: NSRunningApplication) {
        app.terminate()
    }

    private func killExisting() {
        guard settings.enabled else { return }
        for app in NSWorkspace.shared.runningApplications {
            guard let bid = app.bundleIdentifier else { continue }
            if shouldHide(bundleID: bid) {
                lastBlockedApp = app.localizedName ?? bid
                if settings.killOnFrontmost {
                    killApp(app)
                } else {
                    hideApp(app)
                }
            }
        }
    }

    deinit {
        if let obs = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }
}