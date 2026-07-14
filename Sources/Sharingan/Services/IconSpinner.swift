import AppKit

/// Drives the spinning Sharingan: one 12 fps clock advancing a clockwise
/// angle, shared by the menu bar icon and the Dock icon so the two marks
/// stay in phase. Idles — timer gone, angle back to 0 — whenever the user
/// switched the animation off, macOS Reduce Motion is on, or the screens
/// are asleep; an idle spinner costs nothing.
@MainActor
final class IconSpinner {
    /// Degrees in [0, 360). 5°/frame at 12 fps = 60°/s: a full turn every
    /// 6 s, one visible cycle every 2 s (the mark is 3-fold symmetric).
    private(set) var angle: Double = 0

    /// Fires on every animation frame, and once more with (0, false) when
    /// the spinner stops so consumers repaint their static mark.
    var onFrame: ((_ angle: Double, _ spinning: Bool) -> Void)?

    /// The settings switch, pushed in by the menu bar's 1 s tick — a toggle
    /// in Settings takes effect within a second.
    var enabled = false {
        didSet { if oldValue != enabled { sync() } }
    }

    private var timer: Timer?
    private var screensAsleep = false {
        didSet { if oldValue != screensAsleep { sync() } }
    }

    init() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                       object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.screensAsleep = true }
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                       object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.screensAsleep = false }
        }
        ws.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                       object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.sync() }
        }
    }

    private var shouldSpin: Bool {
        enabled && !screensAsleep
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func sync() {
        if shouldSpin, timer == nil {
            let t = Timer.scheduledTimer(withTimeInterval: 1.0 / 12.0,
                                         repeats: true) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.tick() }
            }
            t.tolerance = 0.02
            timer = t
        } else if !shouldSpin, let t = timer {
            t.invalidate()
            timer = nil
            angle = 0
            onFrame?(0, false)
        }
    }

    private func tick() {
        angle = (angle + 5).truncatingRemainder(dividingBy: 360)
        onFrame?(angle, true)
    }
}
