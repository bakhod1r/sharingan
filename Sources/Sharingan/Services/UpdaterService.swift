import AppKit
import Sparkle

/// Thin wrapper around Sparkle's standard updater. Started once from
/// AppDelegate; inert when running outside a real .app bundle (`swift run`,
/// tests), where Sparkle would throw on the missing bundle metadata.
///
/// Updates are fully silent: Sparkle checks and downloads in the background,
/// and when the update is staged this service installs it (relaunching the
/// app) the moment no focus/break session is in flight — never mid-pomodoro,
/// and never with a dialog. `isSafeToInstall` is the gate the AppDelegate
/// wires to the live timer; `installOpportunity()` is poked whenever the
/// timer goes idle, so a download that finished mid-session installs right
/// after the session ends.
@MainActor
final class UpdaterService: NSObject {
    static let shared = UpdaterService()

    private var controller: SPUStandardUpdaterController?
    /// Sparkle's "install now and relaunch, no UI" handler, kept while a
    /// staged update waits for the timer to go idle.
    private var pendingInstall: (() -> Void)?
    /// True when installing/relaunching right now won't interrupt the user —
    /// no running or paused session. Defaults to false so nothing can install
    /// before the AppDelegate has wired the real timer in.
    var isSafeToInstall: () -> Bool = { false }

    func start() {
        guard controller == nil,
              Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: self,
                                                  userDriverDelegate: nil)
        // Silent pipeline: scheduled checks + background download. The
        // install happens in the delegate below, gated on an idle timer.
        controller?.updater.automaticallyDownloadsUpdates = true
    }

    /// False outside a bundle — the menu item and the Settings controls hide
    /// or disable themselves rather than dispatching into a nil updater.
    var isAvailable: Bool { controller != nil }

    /// A staged update is waiting for the session to end.
    var updateReady: Bool { pendingInstall != nil }

    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    var lastUpdateCheckDate: Date? { controller?.updater.lastUpdateCheckDate }

    @objc func checkForUpdates(_ sender: Any?) {
        controller?.checkForUpdates(sender)
    }

    /// Called whenever the timer becomes idle (and once at wiring time):
    /// installs the staged update, if any, now that it's safe.
    func installOpportunity() {
        guard let install = pendingInstall, isSafeToInstall() else { return }
        pendingInstall = nil
        install()   // installs the update and relaunches the app, no UI
    }
}

extension UpdaterService: SPUUpdaterDelegate {
    /// Sparkle downloaded and staged an update. Taking the handler (return
    /// true) suppresses every "update available" dialog; the update goes in
    /// silently at the next idle moment — or, as Sparkle guarantees anyway,
    /// on app quit if that comes first.
    nonisolated func updater(_ updater: SPUUpdater,
                             willInstallUpdateOnQuit item: SUAppcastItem,
                             immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        Task { @MainActor in
            self.pendingInstall = immediateInstallHandler
            self.installOpportunity()
        }
        return true
    }
}
