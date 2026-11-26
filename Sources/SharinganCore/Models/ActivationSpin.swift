import Foundation

/// The pattern's activation whirl (accelerate, spin `turns`, settle) with a
/// carried base angle, so restarting it on a step change never snaps the
/// rotation: the angle shown just before the restart is folded into `base`.
public struct ActivationSpin: Equatable, Sendable {
    public var duration: Double
    public var turns: Double
    /// Angle (degrees) carried over from earlier activations.
    public private(set) var base: Double = 0
    public private(set) var start: TimeInterval = 0

    public init(duration: Double = 1.6, turns: Double = 3, start: TimeInterval = 0) {
        self.duration = duration
        self.turns = turns
        self.start = start
    }

    /// One activation's angle: smootherstep from 0 to `turns` full turns.
    public static func burst(at t: TimeInterval, since start: TimeInterval,
                             duration: Double = 1.6, turns: Double = 3) -> Double {
        let u = min(max((t - start) / duration, 0), 1)
        return turns * 360 * (u * u * u * (u * (u * 6 - 15) + 10))
    }

    /// Total activation angle at `t` (carried base + current burst).
    public func angle(at t: TimeInterval) -> Double {
        base + Self.burst(at: t, since: start, duration: duration, turns: turns)
    }

    /// Begin a fresh burst at `newStart`; the angle at `now` is preserved.
    public mutating func restart(at newStart: TimeInterval, now: TimeInterval) {
        base = angle(at: now)
        start = newStart
    }

    /// First appearance: nothing carried.
    public mutating func reset(start newStart: TimeInterval) {
        base = 0
        start = newStart
    }
}
