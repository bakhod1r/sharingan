import AppKit
import Combine
import SwiftUI
import SharinganCore

/// Hosts the always-on-desktop "today" panel (TodayPanelView) in a
/// non-activating borderless NSPanel: joins all spaces, draggable by its
/// body, position remembered across launches. Shown/hidden purely by the
/// `showTodayPanel` settings flag (via SharinganCoordinator.syncTodayPanel()) —
/// like the Dock widget, it does not follow the running state.
@MainActor
final class TodayPanelWindowManager: TodayPanelController {
    static let shared = TodayPanelWindowManager()
    private var panel: NSPanel?
    private var moveObserver: NSObjectProtocol?
    private var resizeCancellable: AnyCancellable?
    private let originKey = "sharingan.todayPanel.origin"

    func showTodayPanel(timer: PomodoroTimer) {
        guard panel == nil else { return }

        let hosting = NSHostingView(rootView: TodayPanelView(timer: timer))
        // The card hugs its content (fixed width, fitted height) — size the
        // panel to it exactly so there's no invisible click-eating margin.
        let size = hosting.fittingSize

        let panel = TodayPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                    .stationary, .ignoresCycle]
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The card draws its own glass; the OS shadow would be a rectangle
        // around the transparent window.
        panel.hasShadow = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.ignoresMouseEvents = false
        panel.isFloatingPanel = true

        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        // Restore the remembered origin, else park in the top-right corner.
        if let stored = UserDefaults.standard.string(forKey: originKey) {
            panel.setFrameOrigin(NSPointFromString(stored))
        } else if let screen = NSScreen.main {
            let v = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: v.maxX - size.width - 24,
                                         y: v.maxY - size.height - 24))
        }
        self.panel = panel
        // Present BEFORE the move observer registers, so the presentation
        // settle isn't persisted as a user drag.
        WindowAnimator.present(panel, makeKey: false)

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak panel] _ in
            guard let panel else { return }
            UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin),
                                      forKey: "sharingan.todayPanel.origin")
        }
        // The card's height tracks the task list (rows appear/disappear as
        // tasks complete or get planned) — refit the panel on every change,
        // next runloop so SwiftUI has re-laid-out the hosting view.
        resizeCancellable = TaskStore.shared.$tasks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.resizeToFit() }
            }
    }

    func hideTodayPanel() {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
            self.moveObserver = nil
        }
        resizeCancellable = nil
        guard let panel else { return }
        self.panel = nil
        WindowAnimator.dismiss(panel) {
            panel.orderOut(nil)
            panel.contentView = nil
        }
    }

    /// Refit the panel to the card's new content height, keeping the top-left
    /// corner anchored (windows grow downward from the user's chosen spot).
    private func resizeToFit() {
        guard let panel, let hosting = panel.contentView else { return }
        let size = hosting.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        let old = panel.frame
        guard abs(size.height - old.height) > 0.5
                || abs(size.width - old.width) > 0.5 else { return }
        panel.setFrame(NSRect(x: old.origin.x,
                              y: old.maxY - size.height,
                              width: size.width,
                              height: size.height),
                       display: true)
    }
}

private final class TodayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
