import Foundation

extension LookingForEyesPose {
    /// Element-wise blend between two poses (`k` 0 = self, 1 = other).
    public func blended(to o: LookingForEyesPose, _ k: Double) -> LookingForEyesPose {
        func m(_ a: Double, _ b: Double) -> Double { a + (b - a) * k }
        func ma(_ a: [Double], _ b: [Double]) -> [Double] { zip(a, b).map { m($0, $1) } }
        var r = k < 0.5 ? self : o
        r.axis = m(axis, o.axis)
        r.ringBottom = m(ringBottom, o.ringBottom)
        r.ringLeftRel = m(ringLeftRel, o.ringLeftRel)
        r.whiteGap = m(whiteGap, o.whiteGap)
        r.pupilShift = m(pupilShift, o.pupilShift)
        r.pupilY = m(pupilY, o.pupilY)
        r.pupilRadiusX = m(pupilRadiusX, o.pupilRadiusX)
        r.highlightRelX = m(highlightRelX, o.highlightRelX)
        r.highlightRelY = m(highlightRelY, o.highlightRelY)
        r.highlightAlpha = m(highlightAlpha, o.highlightAlpha)
        r.lid = ma(lid, o.lid)
        r.brow = ma(brow, o.brow)
        r.crease = ma(crease, o.crease)
        r.mouth = ma(mouth, o.mouth)
        r.spark = m(spark, o.spark)
        r.fireLevel = m(fireLevel, o.fireLevel)
        r.fireTop = m(fireTop, o.fireTop)
        r.embers = m(embers, o.embers)
        r.lidOpenness = m(lidOpenness, o.lidOpenness)
        r.irisRadius = m(irisRadius, o.irisRadius)
        return r
    }
}

/// Pure choreography of the "Looking-for" face on the break screen:
/// intro (the full video clip) -> exercise (angry squint, iris follows the
/// exercise gaze) -> outro (spark, fire, lids close exactly at break end).
public enum LookingForBreakChoreography {
    public typealias Phase = BreakFacePhase
    public typealias Input = BreakFaceInput

    public static let introDuration = LookingForEyesTimeline.duration
    /// Intro -> squint ease.
    public static let blendDuration: TimeInterval = 0.35
    /// Spark + fire (video frames 86...137) followed by the lid close.
    public static let fireDuration: TimeInterval = 51.0 / LookingForEyesTimeline.fps
    public static let closeDuration: TimeInterval = 0.5
    public static let outroDuration: TimeInterval = fireDuration + closeDuration
    /// Gaze / lids ease to centre-open at the start of the outro.
    private static let outroSettle: TimeInterval = 0.4

    /// Video frame whose face shapes (lids, brows, mouth) form the squint.
    private static let squintFrame = 32.0
    private static let squintBaseT = (squintFrame - 1) / LookingForEyesTimeline.fps
    /// Measured pupil scan range of frames 43...93.
    private static let shiftLeft = 32.0, shiftRight = 26.0
    private static let verticalRange = 30.0

    // MARK: Exercise iris fit

    /// The exercise squint raises the lids by this much (face-space px) so the opening is deep
    /// enough for a large iris; the slant, brows and crease stay as in the video.
    public static let squintLift = 62.0
    /// Iris diameter as a fraction of the biggest circle that fits (rest is room to look around).
    public static let irisFill = 0.92
    private static let lidMargin = 2.0

    /// The lid-fold crease follows the raised lid (its y values move up by `squintLift * k`).
    private static func liftedCrease(_ c: [Double], _ k: Double) -> [Double] {
        c.enumerated().map { $1 - ($0 % 3 == 0 ? 0 : squintLift * k) }
    }

    /// The squint frame with the raised lids: the exercise phase's open face.
    private static let openSquint: LookingForEyesPose = {
        var p = LookingForEyesTimeline.pose(at: squintBaseT)
        p.lid = p.lid.map { $0 - squintLift }
        p.crease = liftedCrease(p.crease, 1)
        p.pupilRadiusX = 85.7
        return p
    }()
    /// Largest circle that fits the open squint: where the iris rests, and its size limit.
    private static let restCircle = openSquint.eyeOpening(lidMargin: lidMargin).largestCircle(centeredAtX: openSquint.whiteCX)
    private static let fullOpening = openSquint.eyeOpening(lidMargin: lidMargin)
    /// Radius of the exercise iris.
    public static let exerciseIrisRadius = restCircle.radius * irisFill

    // MARK: Phase

    public static func phase(_ i: Input) -> Phase {
        if i.reduceMotion { return .exercise }
        if let r = i.remaining, r <= outroDuration { return .outro }
        return i.elapsed < introDuration ? .intro : .exercise
    }

    // MARK: Pose

    public static func pose(_ i: Input) -> LookingForEyesPose {
        let sharingan = i.iris == .sharingan
        switch phase(i) {
        case .intro:
            return sharingan ? sharinganVideo(at: i.elapsed) : LookingForEyesTimeline.pose(at: i.elapsed)
        case .exercise:
            if sharingan { return sharinganExercise(i) }
            let target = exercisePose(i, gazeWeight: 1, openness: exerciseOpenness(i))
            if i.reduceMotion || i.elapsed >= introDuration + blendDuration { return target }
            let from = LookingForEyesTimeline.pose(at: introDuration - 1e-9)
            return from.blended(to: target, smooth((i.elapsed - introDuration) / blendDuration))
        case .outro:
            return outroPose(i)
        }
    }

    // MARK: Sharingan iris in the intro, blend and outro

    private static let wideLidMean = mean(LookingForEyesTimeline.pose(at: 0).lid)
    private static let squintLidMean = mean(LookingForEyesTimeline.pose(at: squintBaseT).lid)
    private static func mean(_ a: [Double]) -> Double { a.reduce(0, +) / Double(a.count) }

    /// The video with the exercise's lid lift applied in proportion to how far the face has
    /// squinted (0 = wide-eyed start, 1 = the squint the exercise is built from), and the iris
    /// fitted fully inside the visible opening at the video's gaze position.
    private static func sharinganVideo(at t: TimeInterval) -> LookingForEyesPose {
        let v = LookingForEyesTimeline.pose(at: t)
        let s = max(0, min(1, (mean(v.lid) - wideLidMean) / (squintLidMean - wideLidMean)))
        var p = v
        p.lid = v.lid.map { $0 - squintLift * s }
        p.crease = liftedCrease(v.crease, s)
        return fitIris(p, toward: v.irisCenter)
    }

    /// Places the round iris in the visible opening of `p` as close as it fits to `desired`.
    private static func fitIris(_ p: LookingForEyesPose, toward desired: (x: Double, y: Double)) -> LookingForEyesPose {
        let o = p.eyeOpening(lidMargin: lidMargin)
        let a = o.largestCircle(centeredAtX: p.whiteCX)
        let c = o.fit(radius: exerciseIrisRadius, fill: 1,
                      offset: (desired.x - a.x, desired.y - a.y), anchor: a)
        var r = p
        r.pupilShift = c.x - (p.ringLeft + 185.5)
        r.pupilY = c.y + 85.7 - 84
        r.irisRadius = c.radius
        r.pupilRadiusX = 85.7
        return r
    }

    /// Exercise phase with the video -> squint blend (the lids may still be easing open/shut by `exerciseOpenness`).
    private static func sharinganExercise(_ i: Input) -> LookingForEyesPose {
        let open = exerciseOpenness(i)
        let target = exerciseShape(i, gazeWeight: 1, fit: 1)
        if i.reduceMotion || i.elapsed >= introDuration + blendDuration { return closing(target, openness: open) }
        let k = smooth((i.elapsed - introDuration) / blendDuration)
        let from = sharinganVideo(at: introDuration - 1e-9)
        let shape = from.blended(to: target, k)
        let desired = (x: from.irisCenter.x + (target.irisCenter.x - from.irisCenter.x) * k,
                       y: from.irisCenter.y + (target.irisCenter.y - from.irisCenter.y) * k)
        return closing(fitIris(shape, toward: desired), openness: 1 + (open - 1) * k)
    }

    private static func outroPose(_ i: Input) -> LookingForEyesPose {
        let remaining = max(0, i.remaining ?? 0)
        let u = outroDuration - remaining                       // 0 ... outroDuration
        let settle = smooth(u / outroSettle)
        let open = exerciseOpenness(i) + (1 - exerciseOpenness(i)) * settle
        let closing = smooth(remaining / closeDuration)
        let sharingan = i.iris == .sharingan
        // Sharingan: the fitted iris and lifted lids stay through the outro; only the lids close over it.
        var p = exercisePose(i, gazeWeight: 1 - settle, openness: open * closing, fit: sharingan ? 1 : 1 - settle)
        let f = 86 + min(u, fireDuration) * LookingForEyesTimeline.fps
        let v = LookingForEyesTimeline.pose(at: (f - 1) / LookingForEyesTimeline.fps)
        p.frame = f
        p.pupilRadiusX = sharingan ? 85.7 : v.pupilRadiusX + (85.7 - v.pupilRadiusX) * (1 - settle)
        p.highlightAlpha = v.highlightAlpha
        p.spark = v.spark
        p.fireLevel = v.fireLevel
        p.fireTop = v.fireTop
        p.embers = v.embers
        return p
    }

    /// The squint face with the iris at the exercise gaze and the lids scaled by `openness`.
    /// `fit` 1 = iris sized and placed to be fully visible below the (raised) lids, 0 = the
    /// video's squint and pupil (the outro eases back to it).
    private static func exercisePose(_ i: Input, gazeWeight: Double, openness: Double, fit: Double = 1) -> LookingForEyesPose {
        closing(exerciseShape(i, gazeWeight: gazeWeight, fit: fit), openness: openness)
    }

    /// The squint face with fully open lids (the open state the iris is fitted to).
    private static func exerciseShape(_ i: Input, gazeWeight: Double, fit: Double) -> LookingForEyesPose {
        let video = LookingForEyesTimeline.pose(at: squintBaseT)
        var p = openSquint
        p.lid = zip(video.lid, openSquint.lid).map { $0 + ($1 - $0) * fit }
        p.crease = liftedCrease(video.crease, fit)
        let g = gazeOffset(i)
        let dx = max(-1, min(1, g.x * gazeWeight)), dy = max(-1, min(1, g.y * gazeWeight))
        let offset = (x: dx >= 0 ? dx * shiftRight : dx * shiftLeft, y: dy * verticalRange)

        // video pupil: the raw gaze shift
        let rawShift = offset.x, rawY = video.pupilY + offset.y
        // fitted iris: whole circle inside the opening
        let c = fullOpening.fit(radius: exerciseIrisRadius, fill: 1,
                                                       offset: offset, anchor: restCircle)
        let fitShift = c.x - (p.ringLeft + 185.5), fitY = c.y + 85.7 - 84
        p.pupilShift = rawShift + (fitShift - rawShift) * fit
        p.pupilY = rawY + (fitY - rawY) * fit
        p.irisRadius = 85.7 + (c.radius - 85.7) * fit
        p.pupilRadiusX = video.pupilRadiusX + (85.7 - video.pupilRadiusX) * fit
        return p
    }

    /// Scales the lids toward the eyeball bottom; `openness` 1 = open, 0 = shut. The iris is not touched,
    /// so a closing lid covers it like an eyelid.
    private static func closing(_ pose: LookingForEyesPose, openness: Double) -> LookingForEyesPose {
        var p = pose
        let o = max(0, min(1, openness))
        let closed = p.ringBottom + 8
        p.lid = p.lid.map { closed + ($0 - closed) * o }
        p.lidOpenness = o
        return p
    }

    // MARK: Lids

    /// The step's own lid value: closed holds shut, blink snaps shut and reopens each second.
    public static func steadyOpenness(direction: String, phaseElapsed: TimeInterval) -> Double {
        BreakGazePath.steadyOpenness(direction: direction, phaseElapsed: phaseElapsed)
    }

    private static func exerciseOpenness(_ i: Input) -> Double { BreakGazePath.exerciseOpenness(i) }

    // MARK: Gaze

    public static func gazeOffset(_ i: Input) -> (x: Double, y: Double) { BreakGazePath.gazeOffset(i) }

    private static func smooth(_ u: Double) -> Double { BreakGazePath.smooth(u) }
}
