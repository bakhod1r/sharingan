import AppKit
import SwiftUI

/// Manages the app's main window with AppKit instead of a SwiftUI `Window`
/// scene. A menu-bar (`LSUIElement`) app's SwiftUI `Window` does NOT reliably
/// present at launch, so on some Macs nothing appears until you find the
/// menu-bar icon. Driving an `NSWindow` directly guarantees the window shows on
/// launch and on demand, on every macOS version.
@MainActor
final class MainWindowManager: NSObject, NSWindowDelegate {
    static let shared = MainWindowManager()

    /// Supplies the SwiftUI content. Set once at startup by `SharinganApp`.
    var content: (() -> AnyView)?

    private var window: NSWindow?

    /// Show the window (creating it on first use), become a regular app, and
    /// bring everything to the front.
    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            if window.isVisible {
                window.makeKeyAndOrderFront(nil)
            } else {
                WindowAnimator.present(window)
            }
            return
        }
        guard let content else { return }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1352, height: 936),
            styleMask: [.titled, .closable, .miniaturizable, .resizable,
                        .fullSizeContentView],
            backing: .buffered, defer: false)
        win.title = "Sharingan"
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isReleasedWhenClosed = false
        win.contentMinSize = NSSize(width: 920, height: 620)
        win.contentView = NSHostingView(rootView: content())
        win.delegate = self
        win.center()
        WindowAnimator.present(win)
        self.window = win
    }

    /// Closing the window drops back to a menu-bar-only (accessory) app.
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    /// Whether the main window is currently on screen — used by the menu-bar
    /// popover to avoid opening on top of it (translucent `.thinMaterial`
    /// chrome lets an overlapping window behind bleed through the glass).
    var isOnScreen: Bool { window?.isVisible ?? false }

    /// Temporarily orders the window out (not closed — `windowWillClose`
    /// doesn't fire, so the app stays `.regular` and no state is lost) while
    /// the menu-bar popover is showing.
    func hideTemporarily() { window?.orderOut(nil) }

    /// Brings the window back after the popover that hid it closes.
    func restore() { window?.makeKeyAndOrderFront(nil) }

}
