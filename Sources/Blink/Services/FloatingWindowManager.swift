import AppKit
import SwiftUI
import BlinkCore

@MainActor
final class FloatingWindowManager: FloatingTimerController {
    static let shared = FloatingWindowManager()
    private var panel: NSPanel?

    func showFloating(timer: PomodoroTimer) {
        if panel != nil { return }
        let size = NSSize(width: 168, height: 86)
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
        // The card draws its own rounded shadow; the OS window shadow would be a
        // rectangle around the transparent window, so disable it.
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = true
        // Borderless panels only drag from their body when this is set.
        panel.isMovableByWindowBackground = true
        panel.ignoresMouseEvents = false
        panel.isFloatingPanel = true

        let view = FloatingTimerView(timer: timer)
            .environmentObject(timer)
        let hosting = NSHostingView(rootView: view)
        panel.contentView = hosting
        // Size the panel to the view's intrinsic content (responsive to the
        // chosen time format), keeping it anchored at its top-left corner.
        let fitting = hosting.fittingSize
        if fitting.width > 0, fitting.height > 0 {
            let topLeft = NSPoint(x: panel.frame.minX,
                                  y: panel.frame.maxY)
            panel.setContentSize(fitting)
            panel.setFrameTopLeftPoint(topLeft)
        }
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