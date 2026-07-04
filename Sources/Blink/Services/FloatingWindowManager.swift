import AppKit
import SwiftUI
import BlinkCore

@MainActor
final class FloatingWindowManager: FloatingTimerController {
    static let shared = FloatingWindowManager()
    private var panel: NSPanel?

    func showFloating(timer: PomodoroTimer) {
        if panel != nil { return }
        let size = NSSize(width: 220, height: 96)
        let panel = FloatingMiniPanel(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                     .stationary, .ignoresCycle]
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = true
        panel.ignoresMouseEvents = false
        panel.isFloatingPanel = true

        let view = FloatingTimerView(timer: timer)
            .environmentObject(timer)
        let hosting = NSHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = hosting
        panel.center()
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hideFloating() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
    }

    func toggleFloating(timer: PomodoroTimer) {
        if panel == nil { showFloating(timer: timer) } else { hideFloating() }
    }
}

private final class FloatingMiniPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}