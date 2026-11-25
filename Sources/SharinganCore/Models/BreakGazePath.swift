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
    /// Iris mode: with `.sharingan` the intro, blends and outro keep the whole iris visible.
    public var iris: BreakIrisStyle

    public init(elapsed: TimeInterval, remaining: TimeInterval?, direction: String,
                gaze: GazeDirection, phaseElapsed: TimeInterval, holdSeconds: Double,
                previousOpenness: Double = 1, reduceMotion: Bool = false,
                iris: BreakIrisStyle = .original) {
        self.elapsed = elapsed
        self.remaining = remaining
        self.direction = direction
        self.gaze = gaze
        self.phaseElapsed = phaseElapsed
        self.holdSeconds = holdSeconds
        self.previousOpenness = previousOpenness
        self.reduceMotion = reduceMotion
        self.iris = iris
    }
}

/// Gaze path, hold envelope and lid rhythm of the exercise steps. Same math as
/// `MoveEyePair.offset` / `pathEnvelope` / `steadyOpenness`.
enum BreakGazePath {
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

    /// Lid openness of the exercise phase, eased from where the previous step left the lids.
    static func exerciseOpenness(_ i: BreakFaceInput) -> Double {
        let mode = steadyOpenness(direction: i.direction, phaseElapsed: i.phaseElapsed)
        if i.reduceMotion { return i.direction == "closed" ? 0 : 1 }
        let eased = smooth(i.phaseElapsed / 0.35)
        return i.previousOpenness + (mode - i.previousOpenness) * eased
    }

    static func gazeOffset(_ i: BreakFaceInput) -> (x: Double, y: Double) {
        let tp = max(0, i.phaseElapsed)
        switch i.direction {
        case "circle_cw":
            let a = tp * 1.7, r = pathEnvelope(tp, hold: i.holdSeconds)
            return (cos(a) * r, sin(a) * r)
        case "circle_ccw":
            let a = -tp * 1.7, r = pathEnvelope(tp, hold: i.holdSeconds)
            return (cos(a) * r, sin(a) * r)
        case "figure8":
            let a = tp * 1.7, r = pathEnvelope(tp, hold: i.holdSeconds)
            return (sin(a) * r, sin(2 * a) / 2 * r)
        default:
            if i.reduceMotion { return (i.gaze.dx, i.gaze.dy) }
            let sway = 0.018
            return (i.gaze.dx + sin(i.elapsed * 0.7) * sway,
                    i.gaze.dy + sin(i.elapsed * 0.53 + 1.3) * sway)
        }
    }

    static func pathEnvelope(_ tp: Double, hold: Double) -> Double {
        let rampIn = smooth(tp / 0.6)
        guard hold > 1.4 else { return rampIn }
        return min(rampIn, smooth((hold - tp) / 0.6))
    }
}
