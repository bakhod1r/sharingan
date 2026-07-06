import AppKit
import SwiftUI
import BlinkCore

@MainActor
final class FloatingWindowManager: FloatingTimerController {
    static let shared = FloatingWindowManager()
    private var panel: NSPanel?
    private var moveObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private let posKeyX = "blink.floating.x"
    private let posKeyY = "blink.floating.y"
    private let sizeKeyW = "blink.floating.w"
    private let sizeKeyH = "blink.floating.h"

    func showFloating(timer: PomodoroTimer) {
        if panel != nil { applySettings(timer.settings); return }
        let defaults = UserDefaults.standard
        // Restore the remembered size, else a default that depends on the compact
        // setting. The user can freely resize from here.
        let compact = timer.settings.floatingCompact
        let defaultSize = compact ? NSSize(width: 150, height: 90)
                                  : NSSize(width: 186, height: 108)
        var size = defaultSize
        if defaults.object(forKey: sizeKeyW) != nil {
            let w = defaults.double(forKey: sizeKeyW)
            let h = defaults.double(forKey: sizeKeyH)
            if w > 0, h > 0 { size = NSSize(width: w, height: h) }
        }

        let panel = FloatingMiniPanel(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.borderless, .resizable, .fullSizeContentView, .nonactivatingPanel],
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
        // Resize bounds — small pill up to a card big enough to show the task.
        panel.minSize = NSSize(width: 120, height: 66)
        panel.maxSize = NSSize(width: 460, height: 340)

        let view = FloatingTimerView(timer: timer)
            .environmentObject(timer)
        let hosting = NSHostingView(rootView: view)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        // Restore the remembered position, if any.
        if defaults.object(forKey: posKeyX) != nil {
            let x = defaults.double(forKey: posKeyX)
            let y = defaults.double(forKey: posKeyY)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        self.panel = panel
        applySettings(timer.settings)
        panel.orderFrontRegardless()

        // Persist position on drag (and slosh the liquid); persist size on resize.
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak panel] _ in
            guard let panel else { return }
            let origin = panel.frame.origin
            let d = UserDefaults.standard
            d.set(Double(origin.x), forKey: "blink.floating.x")
            d.set(Double(origin.y), forKey: "blink.floating.y")
            MainActor.assumeIsolated {
                FloatingMotion.shared.moved(to: origin.x)
            }
        }
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main
        ) { [weak panel] _ in
            guard let panel else { return }
            let s = panel.frame.size
            let d = UserDefaults.standard
            d.set(Double(s.width), forKey: "blink.floating.w")
            d.set(Double(s.height), forKey: "blink.floating.h")
        }
    }

    func hideFloating() {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
            self.moveObserver = nil
        }
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
            self.resizeObserver = nil
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
