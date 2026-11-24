import Foundation

/// How the menu bar Sharingan moves: it rests still, then *awakens* — one
/// eased 120° turn (a single tomoe step) — and rests again.
///
/// Why bursts and not a continuous spin: on macOS 26 every status-item image
/// change makes AppKit re-snapshot the button into the menu bar's replicants
/// (`-[NSStatusItem _updateReplicants]`, a CPU-side `renderInContext:` per
/// display). At 12 fps that alone cost ~17% CPU at rest and ~40% with the
/// countdown title showing. Bursts animate only a small slice of each cycle.
public struct IconSpinCadence: Equatable, Sendable {
    /// Seconds between animation frames while a burst runs.
    public var frameInterval: TimeInterval
    /// Seconds the mark sits still between bursts.
    public var restSeconds: TimeInterval
    /// Degrees added to the resting angle on each burst frame; ends at 120.
    /// Every value is on the 5° grid the menu bar icon cache is keyed by.
    public let burstOffsets: [Double]

    /// Defaults: 8 fps for 1 s (8 frames), then 20 s still. Each frame
    /// costs ~10 ms of AppKit snapshotting, so frames — not smoothness — set
    /// the price: 8 fps keeps the burst peak near 8% of a core and averages
    /// well under 1%; the ease-in-out hides the lower frame rate.
    public init(frameInterval: TimeInterval = 1.0 / 8.0,
                restSeconds: TimeInterval = 20,
                burstSeconds: TimeInterval = 1.0,
                turnDegrees: Double = 120) {
        self.frameInterval = frameInterval
        self.restSeconds = restSeconds
        let frames = max(1, Int((burstSeconds / frameInterval).rounded()))
        var offsets: [Double] = []
        for i in 1...frames {
            let u = Double(i) / Double(frames)
            // easeInOutQuad: slow start, fast middle, soft landing.
            let eased = u < 0.5 ? 2 * u * u : 1 - pow(-2 * u + 2, 2) / 2
            let snapped = (eased * turnDegrees / 5).rounded() * 5
            if snapped > (offsets.last ?? 0) { offsets.append(snapped) }
        }
        if offsets.last != turnDegrees { offsets.append(turnDegrees) }
        self.burstOffsets = offsets
    }

    public static let standard = IconSpinCadence()
}
