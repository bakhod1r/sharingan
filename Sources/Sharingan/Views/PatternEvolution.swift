import Foundation
import CoreGraphics
import SharinganCore

/// Pure per-frame math for the break-screen Sharingan evolution: the pattern
/// whirls open out of the pupil at break start, awakens tomoe-by-tomoe
/// (1 → 2 → 3), collapses and re-emerges for cross-family changes, and folds
/// shut as the break ends. No state, no clocks — MoveEyePair's TimelineView
/// and the headless GIF renderer both feed it timestamps, so previews match
/// the app exactly.
struct PatternEvolution {
    var transition: PatternTransitionSpeed = .normal
    /// When the pair appeared (break start).
    var appearStart: TimeInterval = 0
    /// When the current exercise step began.
    var phaseStart: TimeInterval = 0
    /// Steps completed so far — index into the evolution chain.
    var evolutionCount: Int = 0
    /// When the break ends (closing bookend); nil = open-ended.
    var end: TimeInterval? = nil
    var reduceMotion = false
    /// Styles shown when the evolution is off (the user's configured pair).
    var baseLeft: SharinganStyle = .classic
    var baseRight: SharinganStyle = .classic
    /// false = keep the configured styles (no chain walking) but still play
    /// the opening whirl and the closing bookend — used by previews that
    /// must show the user's selection.
    var evolves = true

    /// The canonical awakening order: one tomoe → two → three, then the
    /// Mangekyō family, ending on the Rinnegan before wrapping around.
    static let chain: [SharinganStyle] = [
        .tomoe1, .tomoe2, .classic,
        .mangekyou, .mangekyouEternal, .itachi, .mangekyouKamui,
        .sixStar, .blade, .fourBlade, .madara, .shuriken, .swirl,
        .triangleTomoe, .ringCrescents, .orbit, .crescent, .rinnegan,
    ]

    struct Frame {
        var left: SharinganStyle
        var right: SharinganStyle
        /// 0…1 whirl-out of the whole pattern (0 = hidden in the pupil).
        var emergence: CGFloat
        /// Fractional tomoe count mid-awakening (classic family only).
        var tomoeStage: CGFloat?
        /// 1 while the break runs → 0 over the final moments; multiply into
        /// the lids so the eyes close together with the pattern.
        var endFade: Double
    }

    func frame(at t: TimeInterval) -> Frame {
        let fade = endFade(at: t)
        if reduceMotion || transition == .off {
            return Frame(left: baseLeft, right: baseRight, emergence: 1,
                         tomoeStage: nil, endFade: fade)
        }
        // Non-evolving surfaces: the configured styles whirl open and fold
        // shut, but never walk the chain.
        if !evolves {
            let em = Self.smooth((t - appearStart - 1.0) / transition.openSeconds)
            return Frame(left: baseLeft, right: baseRight,
                         emergence: CGFloat(min(em, fade)),
                         tomoeStage: nil, endFade: fade)
        }

        let chain = Self.chain
        let cur = chain[evolutionCount % chain.count]

        // Break start: the first stage whirls open after the lid awakening.
        if evolutionCount == 0 {
            let em = Self.smooth((t - appearStart - 1.0) / transition.openSeconds)
            return Frame(left: cur, right: cur,
                         emergence: CGFloat(min(em, fade)),
                         tomoeStage: nil, endFade: fade)
        }

        let prev = chain[(evolutionCount - 1) % chain.count]
        let tp = t - phaseStart

        // Tomoe awakening (1 → 2 → 3): the pattern keeps spinning while the
        // next tomoe grows out of the ring and the others glide to their new
        // slots — no collapse in between.
        if let from = Self.tomoeCount(of: prev), let to = Self.tomoeCount(of: cur),
           to == from + 1 {
            let u = Self.smooth((tp - 0.15) / max(transition.openSeconds, 0.4))
            return Frame(left: cur, right: cur,
                         emergence: CGFloat(min(1, fade)),
                         tomoeStage: CGFloat(Double(from) + u),
                         endFade: fade)
        }

        // Cross-family change: collapse into the pupil, then whirl out anew.
        if tp < transition.closeSeconds {
            let em = 1 - Self.smooth(tp / transition.closeSeconds)
            return Frame(left: prev, right: prev,
                         emergence: CGFloat(min(em, fade)),
                         tomoeStage: nil, endFade: fade)
        }
        let em = Self.smooth((tp - transition.closeSeconds) / transition.openSeconds)
        return Frame(left: cur, right: cur,
                     emergence: CGFloat(min(em, fade)),
                     tomoeStage: nil, endFade: fade)
    }

    /// 1 while the break runs, easing to 0 over the final moments.
    private func endFade(at t: TimeInterval) -> Double {
        guard let end, !reduceMotion, transition != .off else { return 1 }
        let dur = max(transition.closeSeconds, 0.6)
        return Self.smooth((end - t - 0.1) / dur)
    }

    private static func tomoeCount(of s: SharinganStyle) -> Int? {
        switch s {
        case .tomoe1:  return 1
        case .tomoe2:  return 2
        case .classic: return 3
        default:       return nil
        }
    }

    /// The activation whirl: tomoe accelerate, spin `turns` times and settle
    /// (smootherstep). Shared by the app and the headless renderer.
    static func activationSpin(at t: TimeInterval, since start: TimeInterval,
                               duration: Double = 1.6, turns: Double = 3) -> Double {
        let u = min(max((t - start) / duration, 0), 1)
        let eased = u * u * u * (u * (u * 6 - 15) + 10)
        return turns * 360 * eased
    }

    /// Break-start awakening: lids hold shut, then sweep open once.
    static func awakenOpenness(at t: TimeInterval, since appear: TimeInterval) -> Double {
        let ta = t - appear
        if ta < 0.35 { return 0 }
        let u = min(max((ta - 0.35) / 0.9, 0), 1)
        return u * u * u * (u * (u * 6 - 15) + 10)
    }

    static func smooth(_ u: Double) -> Double {
        let c = min(max(u, 0), 1)
        return c * c * (3 - 2 * c)
    }
}
