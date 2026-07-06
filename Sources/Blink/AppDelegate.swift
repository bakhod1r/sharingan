import AppKit
import SwiftUI
import BlinkCore

/// AppKit-based menu bar controller — creates NSStatusItem directly,
/// works reliably without Xcode/xcbuild (unlike SwiftUI MenuBarExtra
/// which sometimes fails to register at runtime with CLI toolchain).
@MainActor
final class MenuBarController: NSObject {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    weak var timer: PomodoroTimer?
    weak var coordinator: BlinkCoordinator?

    func install(timer: PomodoroTimer, coordinator: BlinkCoordinator) {
        self.timer = timer
        self.coordinator = coordinator

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        updateTitle()

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 720)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(timer: timer)
        )
        self.popover = popover

        if let button = item.button {
            button.image = Self.menuBarIcon()
            button.imagePosition = .imageLeading
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Sync coordinator services now that the menu bar is live.
        coordinator.syncAlarm()
        coordinator.installShortcuts()
        coordinator.syncCamera()
        coordinator.installCLIBridge()

        // Refresh title every second.
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateTitle() }
        }
    }

    private func updateTitle() {
        guard let timer, let button = statusItem?.button else { return }
        let s = max(0, timer.remainingSeconds)
        // The eye glyph is a real template image (set once in install); the title
        // is just the time, spaced off the icon.
        button.title = String(format: " %02d:%02d", Int(s) / 60, Int(s) % 60)
    }

    /// The menu-bar eye icon as a template image, so macOS tints it correctly on
    /// both light and dark menu bars.
    private static func menuBarIcon() -> NSImage? {
        for name in ["menubar_black_32", "menubar_black_16", "menubar_light"] {
            guard let url = Bundle.module.url(forResource: "MenubarIcons/\(name)",
                                              withExtension: "png"),
                  let img = NSImage(contentsOf: url) else { continue }
            let height: CGFloat = 16
            let aspect = img.size.width / max(img.size.height, 1)
            img.size = NSSize(width: height * aspect, height: height)
            img.isTemplate = true
            return img
        }
        return NSImage(systemSymbolName: "eye.fill", accessibilityDescription: "Blink")
    }

    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var timer: PomodoroTimer?
    var coordinator: BlinkCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let timer = PomodoroTimer()
        let coord = BlinkCoordinator(timer: timer)
        coord.breakPresenter = BreakWindowManager.shared
        coord.floatingController = FloatingWindowManager.shared
        coord.quickAddController = QuickAddWindowManager.shared
        self.timer = timer
        self.coordinator = coord

        // Feed the AppKit-managed main window its SwiftUI content, otherwise
        // MainWindowManager.show() (used by the popover's "Open window" button
        // and the settings gear) bails at its `guard let content` and nothing
        // appears. This wiring was lost in the AppKit restructure.
        MainWindowManager.shared.content = { AnyView(MainWindowView(timer: timer)) }

        MenuBarController.shared.install(timer: timer, coordinator: coord)
    }
}