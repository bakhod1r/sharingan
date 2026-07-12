import AppKit
import SwiftUI
import SharinganCore

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
    /// Last size preset applied to the panel, so a Settings change is
    /// distinguishable from every other refresh (opacity drags etc. must not
    /// clobber a manual resize).
    private var appliedSize: FloatingTimerSize?

    func showFloating(timer: PomodoroTimer) {
        if panel != nil { applySettings(timer.settings); return }
        let defaults = UserDefaults.standard
        // Restore the remembered size, else the preset from Settings. The user
        // can freely resize from here.
        let preset = timer.settings.floatingSize
        var size = NSSize(width: preset.width, height: preset.height)
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
        // Present BEFORE the move/resize observers below register, so the
        // 0.97→1 settle isn't persisted as a user drag.
        WindowAnimator.present(panel, makeKey: false)

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
        guard let panel else { return }
        self.panel = nil
        WindowAnimator.dismiss(panel) {
            panel.orderOut(nil)
            panel.contentView = nil
        }
    }

    func toggleFloating(timer: PomodoroTimer) {
        if panel == nil { showFloating(timer: timer) } else { hideFloating() }
    }

    func refreshFloating(timer: PomodoroTimer) {
        applySettings(timer.settings)
    }

    /// Snap the panel to a size preset, animating in place (center-anchored),
    /// and remember it so the next launch starts from the same frame. Works
    /// with the panel hidden too — the preset just becomes the launch size.
    func apply(size: FloatingTimerSize) {
        appliedSize = size
        let d = UserDefaults.standard
        d.set(size.width, forKey: sizeKeyW)
        d.set(size.height, forKey: sizeKeyH)
        guard let panel else { return }
        var frame = panel.frame
        let new = NSSize(width: size.width, height: size.height)
        frame.origin.x += (frame.width - new.width) / 2
        frame.origin.y += (frame.height - new.height) / 2
        frame.size = new
        panel.setFrame(clamped(frame, to: panel.screen), display: true, animate: true)
    }

    /// Forget the remembered position and bring the panel back to the center
    /// of its screen (rescues a card stranded by a display change).
    func resetPosition() {
        let d = UserDefaults.standard
        d.removeObject(forKey: posKeyX)
        d.removeObject(forKey: posKeyY)
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        let vis = screen.visibleFrame
        let f = panel.frame
        panel.setFrameOrigin(NSPoint(x: vis.midX - f.width / 2,
                                     y: vis.midY - f.height / 2))
    }

    /// Keep an animated preset change on screen.
    private func clamped(_ frame: NSRect, to screen: NSScreen?) -> NSRect {
        guard let vis = (screen ?? NSScreen.main)?.visibleFrame else { return frame }
        var f = frame
        f.origin.x = min(max(f.origin.x, vis.minX), max(vis.minX, vis.maxX - f.width))
        f.origin.y = min(max(f.origin.y, vis.minY), max(vis.minY, vis.maxY - f.height))
        return f
    }

    /// Apply live appearance settings to the current panel.
    private func applySettings(_ settings: PomodoroSettings) {
        // A preset picked in Settings resizes the panel; anything else (opacity,
        // level) leaves the user's manual frame alone.
        if let applied = appliedSize {
            if applied != settings.floatingSize { apply(size: settings.floatingSize) }
        } else {
            appliedSize = settings.floatingSize
        }
        guard let panel else { return }
        panel.alphaValue = CGFloat(min(max(settings.floatingOpacity, 0.3), 1.0))
        panel.level = settings.floatingAlwaysOnTop ? .floating : .normal
    }
}

private final class FloatingMiniPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
