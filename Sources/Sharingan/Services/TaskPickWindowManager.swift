import AppKit
import SwiftUI
import Combine
import SharinganCore

/// Presents the post-break "What's next?" picker in its own small floating
/// panel whenever the coordinator flags `needsTaskPick` (a break ended with
/// nothing left to work on). A dedicated panel — not a popover sheet — because
/// the menubar popover is transient (almost always closed when a break ends)
/// and the main window may not exist at all; the panel is the only surface
/// guaranteed to be available. Selecting a task (or skipping) answers via
/// `coordinator.resolveTaskPick(with:)`, which clears the flag and hides the
/// panel again through the same subscription.
@MainActor
final class TaskPickWindowManager {
    static let shared = TaskPickWindowManager()
    private var panel: NSPanel?
    private var cancellable: AnyCancellable?
    private weak var coordinator: SharinganCoordinator?

    func install(coordinator: SharinganCoordinator) {
        self.coordinator = coordinator
        cancellable = coordinator.$needsTaskPick
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] needs in
                if needs { self?.show() } else { self?.hide() }
            }
    }

    private func show() {
        guard let coordinator else { return }
        // Already open → just refocus it.
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let size = NSSize(width: 400, height: 480)
        let panel = KeyablePickerPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                    .stationary, .ignoresCycle]
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true

        let view = TaskPickerSheet(
            timer: coordinator.timer,
            onPick: { [weak coordinator] id in coordinator?.resolveTaskPick(with: id) }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        panel.contentView = NSHostingView(rootView: view)

        // Center on the screen with the mouse (or the main screen).
        let screen = NSScreen.screens.first {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let x = frame.midX - size.width / 2
            let y = frame.midY + size.height / 2 + frame.height * 0.04
            panel.setFrameTopLeftPoint(NSPoint(x: x, y: min(y, frame.maxY - 20)))
        }
        WindowAnimator.present(panel)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
    }

    private func hide() {
        guard let panel else { return }
        self.panel = nil
        WindowAnimator.dismiss(panel) {
            panel.orderOut(nil)
            panel.contentView = nil
        }
    }
}

/// Borderless panels can't become key by default — needed so the quick-add
/// field and Esc handling receive keystrokes.
private final class KeyablePickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
