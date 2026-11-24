import AppKit
import SharinganCore

/// Drives the menu bar Sharingan's motion: still most of the time, then a
/// short 12 fps *awakening* — one eased 120° turn (`IconSpinCadence`) — every
/// few seconds. A continuous 12 fps spin cost 17–40% CPU, because each frame
/// makes AppKit re-snapshot the status item into the menu bar replicants;
/// bursts animate only a small slice of each cycle. Idles — timers gone,
/// angle back to 0 — whenever the user switched the animation off, macOS
/// Reduce Motion is on, or the screens are asleep; an idle spinner costs
/// nothing.
@MainActor
final class IconSpinner {
    /// Degrees in [0, 360), always on the 5° grid.
    private(set) var angle: Double = 0

    /// Fires on every animation frame, and once more with (0, false) when
    /// the spinner stops so consumers repaint their static mark.
    var onFrame: ((_ angle: Double, _ spinning: Bool) -> Void)?

    /// The settings switch, pushed in by the menu bar's 1 s tick — a toggle
    /// in Settings takes effect within a second.
    var enabled = false {
        didSet { if oldValue != enabled { sync() } }
    }

    private let cadence: IconSpinCadence
    /// The 12 fps clock while a burst runs, or the one-shot rest timer
    /// between bursts — never both.
    private var timer: Timer?
    private var burstBase: Double = 0
    private var burstFrame = 0
    private var screensAsleep = false {
        didSet { if oldValue != screensAsleep { sync() } }
    }

    init(cadence: IconSpinCadence = .standard) {
        self.cadence = cadence
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
            scheduleRest()
        } else if !shouldSpin, let t = timer {
            t.invalidate()
            timer = nil
            angle = 0
            onFrame?(0, false)
        }
    }

    private func scheduleRest() {
        let t = Timer.scheduledTimer(withTimeInterval: cadence.restSeconds,
                                     repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.startBurst() }
        }
        t.tolerance = 0.5
        timer = t
    }

    private func startBurst() {
        guard shouldSpin else { timer = nil; return }
        burstBase = angle
        burstFrame = 0
        let t = Timer.scheduledTimer(withTimeInterval: cadence.frameInterval,
                                     repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.tick() }
        }
        t.tolerance = 0.02
        timer = t
    }

    private func tick() {
        guard burstFrame < cadence.burstOffsets.count else { return }
        let offset = cadence.burstOffsets[burstFrame]
        burstFrame += 1
        angle = (burstBase + offset).truncatingRemainder(dividingBy: 360)
        onFrame?(angle, true)
        if burstFrame == cadence.burstOffsets.count {
            timer?.invalidate()
            scheduleRest()
        }
    }
}
