import AppKit
import SwiftUI
import SharinganCore

/// Hosts the Dock widget (DockWidgetView) in a non-activating borderless
/// NSPanel pinned just above the Dock near its Trash end — macOS Dock tiles
/// are always square, so "widening the Dock" is really a window aligned flush
/// with it. Shown/hidden purely by the `dockWidgetEnabled` settings flag (via
/// SharinganCoordinator.syncDockWidget()); like the today panel it ignores the
/// running state, so Start is always reachable.
@MainActor
final class DockWidgetWindowManager: DockWidgetController {
    static let shared = DockWidgetWindowManager()
    private var panel: NSPanel?
    private var screenObserver: NSObjectProtocol?
    private static let size = NSSize(width: 320, height: 56)

    func showDockWidget(timer: PomodoroTimer) {
        guard panel == nil else { reposition(); return }
        let panel = DockWidgetPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                    .stationary, .ignoresCycle]
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The pill draws its own material; the OS shadow would be a rectangle
        // around the transparent window (same reasoning as the floating timer).
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        // Pinned to the Dock — not user-draggable; placement is recomputed
        // whenever the screen layout (and thus the Dock) changes.
        panel.isMovable = false
        panel.isFloatingPanel = true

        let hosting = NSHostingView(rootView: DockWidgetView(timer: timer))
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        self.panel = panel
        reposition()
        WindowAnimator.present(panel, makeKey: false)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { DockWidgetWindowManager.shared.reposition() }
        }
    }

    func hideDockWidget() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        guard let panel else { return }
        self.panel = nil
        WindowAnimator.dismiss(panel) {
            panel.orderOut(nil)
            panel.contentView = nil
        }
    }

    /// Flush against the Dock's inner edge, near the Trash end. The Dock's
    /// side and thickness fall out of the difference between the screen's
    /// full frame and its visibleFrame; with the Dock auto-hidden the two
    /// (nearly) coincide and the pill rests at the screen edge instead.
    private func reposition() {
        guard let panel, let screen = NSScreen.main else { return }
        let vis = screen.visibleFrame
        let full = screen.frame
        let s = Self.size
        var origin = NSPoint(x: vis.maxX - s.width - 16, y: vis.minY + 4)
        if vis.minX > full.minX {          // Dock on the left
            origin = NSPoint(x: vis.minX + 4, y: vis.minY + 16)
        } else if vis.maxX < full.maxX {   // Dock on the right
            origin = NSPoint(x: vis.maxX - s.width - 4, y: vis.minY + 16)
        }
        panel.setFrame(NSRect(origin: origin, size: s), display: true)
    }
}

private final class DockWidgetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
