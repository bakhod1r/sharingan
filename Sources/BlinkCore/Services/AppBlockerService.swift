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

    public init() {}

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
        if settings.matches(bundleID: bid) {
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
        app.hide()
    }

    private func killApp(_ app: NSRunningApplication) {
        app.terminate()
    }

    private func killExisting() {
        guard settings.enabled else { return }
        for app in NSWorkspace.shared.runningApplications {
            guard let bid = app.bundleIdentifier else { continue }
            if settings.matches(bundleID: bid) {
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