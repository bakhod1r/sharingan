import Foundation

/// Pure crossfade bookkeeping for the break-screen Sharingan pattern: when the
/// style changes, the previous pattern fades out while the new one fades in,
/// both drawn in the same iris, so the iris is never patternless.
public struct StyleCrossfade: Equatable, Sendable {
    public private(set) var previousLeft: SharinganStyle?
    public private(set) var previousRight: SharinganStyle?
    public private(set) var start: TimeInterval?

    public init() {}

    /// Crossfade length, seconds: at least the old collapse+open time, never
    /// shorter than 0.8 s (so a 30 fps frame step stays under 0.1 blend).
    public static func duration(for transition: PatternTransitionSpeed) -> Double {
        guard transition != .off else { return 0 }
        return max(transition.closeSeconds + transition.openSeconds, 0.8)
    }

    public static func smooth(_ u: Double) -> Double {
        let c = min(max(u, 0), 1)
        return c * c * c * (c * (c * 6 - 15) + 10)   // smootherstep
    }

    /// 0 = previous only, 1 = current only.
    public func blend(at t: TimeInterval, transition: PatternTransitionSpeed) -> Double {
        guard let start else { return 1 }
        let d = Self.duration(for: transition)
        guard d > 0 else { return 1 }
        return Self.smooth((t - start) / d)
    }

    /// Layer opacities for a blend value; they always sum to 1.
    public static func opacities(blend: Double) -> (previous: Double, current: Double) {
        let b = min(max(blend, 0), 1)
        return (1 - b, b)
    }

    /// Register a style change. A change landing mid-crossfade keeps whichever
    /// style was dominant (blend >= 0.5) as the new "previous" — no pop.
    public mutating func change(oldLeft: SharinganStyle, oldRight: SharinganStyle,
                                newLeft: SharinganStyle, newRight: SharinganStyle,
                                at t: TimeInterval,
                                transition: PatternTransitionSpeed, reduceMotion: Bool) {
        guard !reduceMotion, transition != .off else {
            self = StyleCrossfade()
            return
        }
        let b = blend(at: t, transition: transition)
        let midFade = start != nil && b < 0.5
        let baseL = midFade ? (previousLeft ?? oldLeft) : oldLeft
        let baseR = midFade ? (previousRight ?? oldRight) : oldRight
        previousLeft = baseL == newLeft ? nil : baseL
        previousRight = baseR == newRight ? nil : baseR
        start = (previousLeft == nil && previousRight == nil) ? nil : t
    }
}
