import AppKit
import SwiftUI
import SharinganCore

/// Hosts the Floating widget (FloatingWidgetView) in a non-activating borderless
/// NSPanel pinned flush against the Dock's inner edge by default — macOS Dock
/// tiles are always square, so "widening the Dock" is really a window aligned
/// flush with it. Draggable to a custom position (see `returnToDock()`), and
/// while docked, placement adapts to the Dock's actual side (bottom, left, or
/// right — see `FloatingWidgetGeometry`), not just the bottom-Dock case. Shown/
/// hidden purely by the `dockWidgetEnabled` settings flag (via
/// SharinganCoordinator.syncFloatingWidget()); like the today panel it ignores the
/// running state, so Start is always reachable.
@MainActor
final class FloatingWidgetWindowManager: FloatingWidgetController {
    static let shared = FloatingWidgetWindowManager()
    private var panel: NSPanel?
    private var hosting: NSHostingView<FloatingWidgetView>?
    private var screenObserver: NSObjectProtocol?
    private var moveObserver: NSObjectProtocol?
    /// The timer whose settings drive size/alignment/opacity — read fresh in
    /// `reposition()` and `applySettings()` rather than snapshotted once, so a
    /// live Settings change (from `syncFloatingWidget()`) takes effect immediately.
    private weak var timer: PomodoroTimer?
    private static let posKeyX = "sharingan.dockwidget.x"
    private static let posKeyY = "sharingan.dockwidget.y"
    /// Set around every programmatic `setFrame` (dock-anchored placement,
    /// settings-driven resize) so the `didMoveNotification` observer below can
    /// tell those apart from an actual user drag and only persist the latter.
    private var isRepositioning = false

    func showFloatingWidget(timer: PomodoroTimer) {
        self.timer = timer
        guard panel == nil else {
            applySettings()
            reposition()
            return
        }
        let preset = timer.settings.dockWidgetSize
        let size = NSSize(width: preset.width, height: preset.height)
        let panel = FloatingWidgetPanel(
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
        // around the transparent window.
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        // Draggable to a custom position (persisted below); dock-anchored
        // placement in `reposition()` still recomputes on screen changes as
        // long as no custom position has been dragged in.
        panel.isMovable = true
        // Borderless panels only drag from their body when this is set.
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true

        let hosting = NSHostingView(rootView: FloatingWidgetView(timer: timer))
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        self.hosting = hosting
        self.panel = panel
        applySettings()
        reposition()
        // Present BEFORE the move observer below registers, so the initial
        // placement (and the 0.97→1 settle) isn't persisted as a user drag.
        WindowAnimator.present(panel, makeKey: false)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { FloatingWidgetWindowManager.shared.reposition() }
        }
        // Persist position on drag — but only real drags: every programmatic
        // setFrame (dock placement, settings resize, the initial 0.97→1
        // settle animation) brackets itself with `isRepositioning`, and a
        // real user drag additionally has the mouse button physically down
        // (`NSEvent.pressedMouseButtons`) — a settle-animation move fires
        // `didMoveNotification` with no button held, so that check alone
        // would otherwise let a programmatic move slip through as a "drag"
        // on any code path that forgets to bracket itself with
        // `isRepositioning`. Once persisted, also re-derive the hover-expand
        // anchor (same screen-half logic as `reposition()`) and push it into
        // the hosted view — otherwise a pill dragged across the screen
        // midline keeps expanding the old direction until the next
        // `reposition()`.
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak panel] _ in
            guard let panel else { return }
            let origin = panel.frame.origin
            let size = panel.frame.size
            MainActor.assumeIsolated {
                let manager = FloatingWidgetWindowManager.shared
                guard !manager.isRepositioning,
                      NSEvent.pressedMouseButtons & 1 != 0 else { return }
                let d = UserDefaults.standard
                d.set(Double(origin.x), forKey: FloatingWidgetWindowManager.posKeyX)
                d.set(Double(origin.y), forKey: FloatingWidgetWindowManager.posKeyY)
                guard let t = manager.timer, let hosting = manager.hosting,
                      let vis = NSScreen.main?.visibleFrame else { return }
                let anchor = FloatingWidgetGeometry.expandAnchor(customOrigin: origin, size: size,
                                                             visibleFrame: vis)
                hosting.rootView = FloatingWidgetView(timer: t, anchor: anchor)
            }
        }
    }

    func hideFloatingWidget() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
            self.moveObserver = nil
        }
        guard let panel else { return }
        self.panel = nil
        self.hosting = nil
        WindowAnimator.dismiss(panel) {
            panel.orderOut(nil)
            panel.contentView = nil
        }
    }

    /// Clears any dragged-in custom position and snaps back to the
    /// Dock-anchored placement — the pill's "Return to Dock" context-menu
    /// action.
    func returnToDock() {
        let d = UserDefaults.standard
        d.removeObject(forKey: Self.posKeyX)
        d.removeObject(forKey: Self.posKeyY)
        reposition()
    }

    /// The user-dragged position, if one has been persisted.
    private func customOrigin() -> CGPoint? {
        let d = UserDefaults.standard
        guard d.object(forKey: Self.posKeyX) != nil else { return nil }
        return CGPoint(x: d.double(forKey: Self.posKeyX), y: d.double(forKey: Self.posKeyY))
    }

    /// Live-apply appearance settings to the current panel: the full preset
    /// frame (hover expansion happens inside the view, not by resizing the
    /// window) and the opacity clamp.
    private func applySettings() {
        guard let panel, let settings = timer?.settings else { return }
        let preset = settings.dockWidgetSize
        var frame = panel.frame
        frame.size = NSSize(width: preset.width, height: preset.height)
        isRepositioning = true
        panel.setFrame(frame, display: true)
        isRepositioning = false
        panel.alphaValue = CGFloat(min(max(settings.dockWidgetOpacity, 0.3), 1.0))
    }

    /// Flush against the Dock's inner edge — beside it, centered, on a
    /// vertical Dock; above it, at the Position setting's end, on a
    /// horizontal one — UNLESS the pill has been dragged to a custom
    /// position, in which case that position wins (clamped back into the
    /// visible frame on screen changes) and dock placement is skipped. The
    /// Dock's side and thickness fall out of the difference between the
    /// screen's full frame and its visibleFrame (`FloatingWidgetGeometry.side`);
    /// with the Dock auto-hidden the two (nearly) coincide and it reads as
    /// bottom, so the pill rests at the screen edge instead. The math itself
    /// lives in SharinganCore (`FloatingWidgetGeometry`) so it is unit-testable
    /// without an `NSScreen`.
    private func reposition() {
        guard let panel, let screen = NSScreen.main, let t = timer else { return }
        let vis = screen.visibleFrame
        let full = screen.frame
        let preset = t.settings.dockWidgetSize
        let alignment = t.settings.dockWidgetAlignment
        let s = CGSize(width: preset.width, height: preset.height)

        let origin: CGPoint
        let anchor: FloatingWidgetAlignment
        if let custom = customOrigin() {
            origin = FloatingWidgetGeometry.clamp(origin: custom, size: s, visibleFrame: vis)
            anchor = FloatingWidgetGeometry.expandAnchor(customOrigin: origin, size: s, visibleFrame: vis)
        } else {
            origin = FloatingWidgetGeometry.origin(size: s, alignment: alignment,
                                               visibleFrame: vis, fullFrame: full)
            anchor = FloatingWidgetGeometry.expandAnchor(alignment: alignment,
                                                      visibleFrame: vis, fullFrame: full)
        }
        isRepositioning = true
        panel.setFrame(NSRect(origin: origin, size: s), display: true)
        isRepositioning = false
        hosting?.rootView = FloatingWidgetView(timer: t, anchor: anchor)
    }
}

private final class FloatingWidgetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
