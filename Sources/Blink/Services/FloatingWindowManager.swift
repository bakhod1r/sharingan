import AppKit
import SwiftUI
import BlinkCore

@MainActor
final class FloatingWindowManager: FloatingTimerController {
    static let shared = FloatingWindowManager()
    private var panel: NSPanel?
    private var moveObserver: NSObjectProtocol?
    private let posKeyX = "blink.floating.x"
    private let posKeyY = "blink.floating.y"

    func showFloating(timer: PomodoroTimer) {
        if panel != nil { applySettings(timer.settings); return }
        let compact = timer.settings.floatingCompact
        let size = compact ? NSSize(width: 132, height: 66)
                           : NSSize(width: 168, height: 86)
        let panel = FloatingMiniPanel(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                     .stationary, .ignoresCycle]
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
            let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
            panel.setContentSize(fitting)
            panel.setFrameTopLeftPoint(topLeft)
        }
        // Restore the remembered position, if any.
        let defaults = UserDefaults.standard
        if defaults.object(forKey: posKeyX) != nil {
            let x = defaults.double(forKey: posKeyX)
            let y = defaults.double(forKey: posKeyY)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        self.panel = panel
        applySettings(timer.settings)
        panel.orderFrontRegardless()

        // Persist the position whenever the user drags the panel.
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak panel] _ in
            guard let panel else { return }
            let origin = panel.frame.origin
            let d = UserDefaults.standard
            d.set(Double(origin.x), forKey: "blink.floating.x")
            d.set(Double(origin.y), forKey: "blink.floating.y")
        }
    }

    func hideFloating() {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
            self.moveObserver = nil
        }
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
    }

    func toggleFloating(timer: PomodoroTimer) {
        if panel == nil { showFloating(timer: timer) } else { hideFloating() }
    }

    func refreshFloating(timer: PomodoroTimer) {
        applySettings(timer.settings)
    }

    /// Apply live appearance settings to the current panel (no-op if hidden).
    private func applySettings(_ settings: PomodoroSettings) {
        guard let panel else { return }
        panel.alphaValue = CGFloat(min(max(settings.floatingOpacity, 0.3), 1.0))
        panel.level = settings.floatingAlwaysOnTop ? .floating : .normal
    }
}

private final class FloatingMiniPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
