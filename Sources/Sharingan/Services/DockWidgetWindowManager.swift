import AppKit
import SwiftUI
import SharinganCore

/// Hosts the Dock widget (DockWidgetView) in a non-activating borderless
/// NSPanel pinned flush against the Dock's inner edge — macOS Dock tiles are
/// always square, so "widening the Dock" is really a window aligned flush
/// with it. Placement adapts to the Dock's actual side (bottom, left, or
/// right — see `DockWidgetGeometry`), not just the bottom-Dock case. Shown/
/// hidden purely by the `dockWidgetEnabled` settings flag (via
/// SharinganCoordinator.syncDockWidget()); like the today panel it ignores the
/// running state, so Start is always reachable.
@MainActor
final class DockWidgetWindowManager: DockWidgetController {
    static let shared = DockWidgetWindowManager()
    private var panel: NSPanel?
    private var hosting: NSHostingView<DockWidgetView>?
    private var screenObserver: NSObjectProtocol?
    /// The timer whose settings drive size/alignment/opacity — read fresh in
    /// `reposition()` and `applySettings()` rather than snapshotted once, so a
    /// live Settings change (from `syncDockWidget()`) takes effect immediately.
    private weak var timer: PomodoroTimer?

    func showDockWidget(timer: PomodoroTimer) {
        self.timer = timer
        guard panel == nil else {
            applySettings()
            reposition()
            return
        }
        let preset = timer.settings.dockWidgetSize
        let size = NSSize(width: preset.width, height: preset.height)
        let panel = DockWidgetPanel(
            contentRect: NSRect(origin: .zero, size: size),
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
        self.hosting = hosting
        self.panel = panel
        applySettings()
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
        self.hosting = nil
        WindowAnimator.dismiss(panel) {
            panel.orderOut(nil)
            panel.contentView = nil
        }
    }

    /// Live-apply appearance settings to the current panel: the full preset
    /// frame (hover expansion happens inside the view, not by resizing the
    /// window) and the opacity clamp, same idea as `FloatingWindowManager`.
    private func applySettings() {
        guard let panel, let settings = timer?.settings else { return }
        let preset = settings.dockWidgetSize
        var frame = panel.frame
        frame.size = NSSize(width: preset.width, height: preset.height)
        panel.setFrame(frame, display: true)
        panel.alphaValue = CGFloat(min(max(settings.dockWidgetOpacity, 0.3), 1.0))
    }

    /// Flush against the Dock's inner edge — beside it, centered, on a
    /// vertical Dock; above it, at the Position setting's end, on a
    /// horizontal one. The Dock's side and thickness fall out of the
    /// difference between the screen's full frame and its visibleFrame
    /// (`DockWidgetGeometry.side`); with the Dock auto-hidden the two
    /// (nearly) coincide and it reads as bottom, so the pill rests at the
    /// screen edge instead. The math itself lives in SharinganCore
    /// (`DockWidgetGeometry`) so it is unit-testable without an `NSScreen`.
    private func reposition() {
        guard let panel, let screen = NSScreen.main, let t = timer else { return }
        let vis = screen.visibleFrame
        let full = screen.frame
        let preset = t.settings.dockWidgetSize
        let alignment = t.settings.dockWidgetAlignment
        let s = CGSize(width: preset.width, height: preset.height)
        let origin = DockWidgetGeometry.origin(size: s, alignment: alignment,
                                               visibleFrame: vis, fullFrame: full)
        panel.setFrame(NSRect(origin: origin, size: s), display: true)
        let anchor = DockWidgetGeometry.expandAnchor(alignment: alignment,
                                                      visibleFrame: vis, fullFrame: full)
        hosting?.rootView = DockWidgetView(timer: t, anchor: anchor)
    }
}

private final class DockWidgetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
