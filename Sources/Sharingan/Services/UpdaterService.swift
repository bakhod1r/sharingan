import AppKit
import Sparkle

/// Thin wrapper around Sparkle's standard updater. Started once from
/// AppDelegate; inert when running outside a real .app bundle (`swift run`,
/// tests), where Sparkle would throw on the missing bundle metadata.
@MainActor
final class UpdaterService: NSObject {
    static let shared = UpdaterService()

    private var controller: SPUStandardUpdaterController?

    func start() {
        guard controller == nil,
              Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
    }

    /// False outside a bundle — the menu item and the Settings controls hide
    /// or disable themselves rather than dispatching into a nil updater.
    var isAvailable: Bool { controller != nil }

    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    var lastUpdateCheckDate: Date? { controller?.updater.lastUpdateCheckDate }

    @objc func checkForUpdates(_ sender: Any?) {
        controller?.checkForUpdates(sender)
    }
}
