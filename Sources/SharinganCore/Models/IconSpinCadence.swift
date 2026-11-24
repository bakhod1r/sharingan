import Foundation

/// How the menu bar Sharingan moves: it rests still, then *awakens* — one
/// eased 120° turn (a single tomoe step) — and rests again.
///
/// Why bursts and not a continuous spin: on macOS 26 every status-item image
/// change makes AppKit re-snapshot the button into the menu bar's replicants
/// (`-[NSStatusItem _updateReplicants]`, a CPU-side `renderInContext:` per
/// display). At 12 fps that alone cost ~17% CPU at rest and ~40% with the
/// countdown title showing. Bursts keep the 12 fps smoothness while moving,
/// but only for a small slice of each cycle.
public struct IconSpinCadence: Equatable, Sendable {
    /// Seconds between animation frames while a burst runs.
    public var frameInterval: TimeInterval
    /// Seconds the mark sits still between bursts.
    public var restSeconds: TimeInterval
    /// Degrees added to the resting angle on each burst frame; ends at 120.
    /// Every value is on the 5° grid the menu bar icon cache is keyed by.
    public let burstOffsets: [Double]

    public init(frameInterval: TimeInterval = 1.0 / 12.0,
                restSeconds: TimeInterval = 9,
                burstSeconds: TimeInterval = 1.5,
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
