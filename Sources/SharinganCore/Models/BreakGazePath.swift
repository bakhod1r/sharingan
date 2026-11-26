import Foundation

/// Phase of a break-screen face animation: the video intro, the exercise guide, the outro.
public enum BreakFacePhase: Equatable, Sendable { case intro, exercise, outro }

/// Everything a break face needs to pick its pose (shared by the Looking-for and Angry faces).
public struct BreakFaceInput: Sendable {
    /// Seconds since the break eyes appeared.
    public var elapsed: TimeInterval
    /// Seconds until the break ends; nil = unknown (no outro).
    public var remaining: TimeInterval?
    public var direction: String
    public var gaze: GazeDirection
    /// Seconds since the current exercise step began.
    public var phaseElapsed: TimeInterval
    public var holdSeconds: Double
    /// Lid openness at the moment the step changed, for a continuous ease.
    public var previousOpenness: Double
    public var reduceMotion: Bool
    /// Iris offset at the moment the step changed: the iris glides from here back to center, then out to the new target.
    public var previousGaze: GazeDirection
    /// Iris mode: with `.sharingan` the intro, blends and outro keep the whole iris visible.
    public var iris: BreakIrisStyle

    public init(elapsed: TimeInterval, remaining: TimeInterval?, direction: String,
                gaze: GazeDirection, phaseElapsed: TimeInterval, holdSeconds: Double,
                previousOpenness: Double = 1, reduceMotion: Bool = false,
                iris: BreakIrisStyle = .original,
                previousGaze: GazeDirection = .center) {
        self.elapsed = elapsed
        self.remaining = remaining
        self.direction = direction
        self.gaze = gaze
        self.phaseElapsed = phaseElapsed
        self.holdSeconds = holdSeconds
        self.previousOpenness = previousOpenness
        self.reduceMotion = reduceMotion
        self.iris = iris
        self.previousGaze = previousGaze
    }
}

/// Gaze path, hold envelope and lid rhythm of the exercise steps. Same math as
/// `MoveEyePair.offset` / `pathEnvelope` / `steadyOpenness`.
public enum BreakGazePath {
    /// Seconds the iris glides back to center when the step changes.
    public static let returnDuration = 0.4
    /// Seconds the iris glides from center out to the new target.
    public static let outDuration = 0.5
    /// Seconds over which the idle sway fades in after the glide ends.
    public static let swayFade = 0.5
    static let nearEpsilon = 0.05

    static func smooth(_ u: Double) -> Double {
        let c = min(max(u, 0), 1)
        return c * c * (3 - 2 * c)
    }

    /// The step's own lid value: closed holds shut, blink snaps shut and reopens each second.
    static func steadyOpenness(direction: String, phaseElapsed: TimeInterval) -> Double {
        switch direction {
        case "closed":
            return 0
        case "blink":
            let ph = max(0, phaseElapsed).truncatingRemainder(dividingBy: 1.0)
            if ph < 0.12 { return 1 - smooth(ph / 0.12) }
            if ph < 0.34 { return smooth((ph - 0.12) / 0.22) }
            return 1
        default:
            return 1
        }
    }

    /// How far the intro clip's iris has handed over to the step's gaze: 0 before `start`, 1 after
    /// `start + ramp`. Lids/brows/fire keep playing the clip; only the iris follows the instruction,
    /// so the face never looks somewhere other than the step says.
    public static func introFollow(_ elapsed: TimeInterval, start: TimeInterval, ramp: TimeInterval) -> Double {
        smooth((elapsed - start) / ramp)
    }

    /// Lid openness of the exercise phase, eased from where the previous step left the lids.
    static func exerciseOpenness(_ i: BreakFaceInput) -> Double {
        let mode = steadyOpenness(direction: i.direction, phaseElapsed: i.phaseElapsed)
        if i.reduceMotion { return i.direction == "closed" ? 0 : 1 }
        let eased = smooth(i.phaseElapsed / 0.35)
        return i.previousOpenness + (mode - i.previousOpenness) * eased
    }

    /// Glide easing: 80% smoothstep + 20% linear. Starts and stops softly (end speed 0.2x
    /// average, not a hard linear start) yet peaks at only 1.4x average, so a unit travel over
    /// the 0.4 s return moves at most ~0.058 per 60 fps frame.
    static func glide(_ u: Double) -> Double {
        let c = min(max(u, 0), 1)
        return 0.8 * smooth(c) + 0.2 * c
    }

    /// Iris offset of the current step: glides back to center, then out to the target (or along the path).
    /// `sway` adds the idle drift (off when capturing the live offset for a step change).
    public static func gazeOffset(_ i: BreakFaceInput, sway withSway: Bool = true) -> (x: Double, y: Double) {
        let tp = max(0, i.phaseElapsed)
        let from = (x: i.previousGaze.dx, y: i.previousGaze.dy)
        let fromMag = (from.x * from.x + from.y * from.y).squareRoot()
        switch i.direction {
        case "circle_cw", "circle_ccw", "figure8":
            let shift = (!i.reduceMotion && fromMag > nearEpsilon) ? returnDuration : 0
            if tp < shift {
                let k = 1 - glide(tp / shift)
                return (from.x * k, from.y * k)
            }
            let t = tp - shift
            let hold = shift > 0 ? i.holdSeconds - shift : i.holdSeconds
            let r = pathEnvelope(t, hold: hold)
            switch i.direction {
            case "circle_cw": return (cos(t * 1.7) * r, sin(t * 1.7) * r)
            case "circle_ccw": return (cos(-t * 1.7) * r, sin(-t * 1.7) * r)
            default:
                let a = t * 1.7
                return (sin(a) * r, sin(2 * a) / 2 * r)
            }
        default:
            let to = (x: i.gaze.dx, y: i.gaze.dy)
            if i.reduceMotion { return to }
            let dist = ((to.x - from.x) * (to.x - from.x) + (to.y - from.y) * (to.y - from.y)).squareRoot()
            let toMag = (to.x * to.x + to.y * to.y).squareRoot()
            var base = to
            var total = 0.0
            if dist >= nearEpsilon {
                let ret = fromMag > nearEpsilon ? returnDuration : 0
                let out = toMag > nearEpsilon ? outDuration : 0
                total = ret + out
                if tp < ret {
                    let k = 1 - glide(tp / ret)
                    base = (from.x * k, from.y * k)
                } else if out > 0 {
                    let k = glide((tp - ret) / out)
                    base = (to.x * k, to.y * k)
                } else {
                    base = (0, 0)
                }
            }
            guard withSway else { return base }
            // A barely-there slow drift keeps the eyes alive during long holds; it fades in once the glide ends.
            let amp = 0.018 * smooth((tp - total) / swayFade)
            return (base.x + sin(i.elapsed * 0.7) * amp,
                    base.y + sin(i.elapsed * 0.53 + 1.3) * amp)
        }
    }

    static func pathEnvelope(_ tp: Double, hold: Double) -> Double {
        let rampIn = smooth(tp / 0.6)
        guard hold > 1.4 else { return rampIn }
        return min(rampIn, smooth((hold - tp) / 0.6))
    }
}
