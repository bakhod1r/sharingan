import Foundation

/// Pure choreography of the "Angry" face on the break screen:
/// intro (the clip's fade-in and first look-around, cut at a centred gaze) ->
/// exercise (angry squint held, pupils follow the exercise gaze) ->
/// outro (the clip's dim-and-shut ending, dark exactly when the break ends).
public enum AngryBreakChoreography {
    public typealias Phase = BreakFacePhase
    public typealias Input = BreakFaceInput

    /// Clip time where the intro is cut: pupils are back at the centre after the first
    /// sweep to the left (frame 227 of 540), eyes fully open under the angry lids.
    public static let introDuration: TimeInterval = 226.0 / AngryEyesTimeline.fps
    /// Intro -> squint ease.
    public static let blendDuration: TimeInterval = 0.35
    /// Clip time where the outro starts: pupils centred again, just before the eyes dim (frame 439).
    public static let outroVideoStart: TimeInterval = 438.0 / AngryEyesTimeline.fps
    /// Clip time where the eyes are gone (frame 523).
    public static let outroVideoEnd: TimeInterval = 522.0 / AngryEyesTimeline.fps
    public static let outroDuration: TimeInterval = outroVideoEnd - outroVideoStart
    /// Gaze / lids ease to centre-open at the start of the outro.
    private static let outroSettle: TimeInterval = 0.4
    /// The last moments fade the remaining glow to exactly zero.
    private static let finalFade: TimeInterval = 0.15

    /// Pupil travel for up / down gazes (px of eye space, the clip never looks vertically).
    private static let upRange = 45.0, downRange = 38.0
    /// Clip frames of the extreme left and right looks (parallax and pupil range come from them).
    // MARK: Exercise iris fit

    /// The exercise squint raises the lids by this much (eye-space px); the slant is unchanged.
    public static let squintLift = 14.0
    /// Iris diameter as a fraction of the biggest circle that fits (rest is room to look around).
    public static let irisFill = 0.95
    private static let lidMargin = 4.0

    private static func opening(_ g: AngryEyeGeometry) -> BreakEyeOpening {
        BreakEyeOpening(cx: g.cx, cy: g.cy, rx: g.radius, ry: g.radius, lidMargin: lidMargin) {
            g.lidY(atU: ($0 - g.cx) / g.radius)
        }
    }

    private static func lifted(_ g: AngryEyeGeometry, _ k: Double) -> AngryEyeGeometry {
        var r = g
        r.lidY0 -= squintLift * k
        return r
    }

    /// Resting iris of each eye on the base squint (centre relative to the eyeball, radius).
    private static let rest: [(dx: Double, dy: Double, radius: Double)] = {
        let b = AngryEyesTimeline.pose(at: outroVideoStart)
        return [b.left, b.right].map { e in
            let g = lifted(e, 1)
            let c = opening(g).largestCircle(centeredAtX: g.cx)
            return (c.x - g.cx, c.y - g.cy, opening(g).clearance(x: c.x, y: c.y) * irisFill)
        }
    }()

    /// Lifts the lid and fits the iris of `g` so the whole circle is visible (`k` 1 = fitted,
    /// 0 = untouched video values; the outro eases between them).
    private static func fitted(_ g: AngryEyeGeometry, eye: Int, offset: (x: Double, y: Double), _ k: Double) -> AngryEyeGeometry {
        guard k > 0 else { return g }
        var r = lifted(g, k)
        let o = opening(lifted(g, 1))
        let a = o.largestCircle(centeredAtX: g.cx)
        let c = o.fit(radius: rest[eye].radius, fill: 1, offset: offset, anchor: a)
        r.pupilX += (c.x - g.pupilX) * k
        r.pupilY += (c.y - g.pupilY) * k
        r.pupilRadius += (c.radius - g.pupilRadius) * k
        return r
    }

    private static let leftLookTime = 150.0 / AngryEyesTimeline.fps
    private static let rightLookTime = 287.0 / AngryEyesTimeline.fps

    // MARK: Phase

    public static func phase(_ i: Input) -> Phase {
        if i.reduceMotion { return .exercise }
        if let r = i.remaining, r <= outroDuration { return .outro }
        return i.elapsed < introDuration ? .intro : .exercise
    }

    // MARK: Pose

    public static func pose(_ i: Input) -> AngryEyesPose {
        switch phase(i) {
        case .intro:
            return i.iris == .sharingan ? sharinganPose(sharinganVideo(at: i.elapsed)) : AngryEyesTimeline.pose(at: i.elapsed)
        case .exercise:
            if i.iris == .sharingan { return sharinganExercise(i) }
            let target = exercisePose(i, openness: BreakGazePath.exerciseOpenness(i))
            if i.reduceMotion || i.elapsed >= introDuration + blendDuration { return target }
            let from = AngryEyesTimeline.pose(at: introDuration - 1e-9)
            return from.blended(to: target, BreakGazePath.smooth((i.elapsed - introDuration) / blendDuration))
        case .outro:
            return i.iris == .sharingan ? sharinganOutro(i) : outroPose(i)
        }
    }

    private static var base: AngryEyesPose { AngryEyesTimeline.pose(at: outroVideoStart) }

    /// The squint at the outro's first frame, shifted by the gaze, with the lids scaled by `openness`.
    private static func exercisePose(_ i: Input, openness: Double) -> AngryEyesPose {
        let b = base
        let d = gazeDelta(i)
        var p = AngryEyesPose(left: fitted(shifted(b.left, d.left), eye: 0, offset: (d.left.offX, d.left.offY), 1),
                              right: fitted(shifted(b.right, d.right), eye: 1, offset: (d.right.offX, d.right.offY), 1))
        applyLids(&p, openness: openness)
        return p
    }

    private static func outroPose(_ i: Input) -> AngryEyesPose {
        let remaining = min(outroDuration, max(0, i.remaining ?? 0))
        let u = outroDuration - remaining
        let settle = BreakGazePath.smooth(u / outroSettle)
        let w = 1 - settle
        let d = gazeDelta(i)
        let v = AngryEyesTimeline.pose(at: outroVideoStart + u)
        let dl = d.left.scaled(w), dr = d.right.scaled(w)
        var p = AngryEyesPose(
            left: fitted(shifted(v.left, dl), eye: 0, offset: (dl.offX, dl.offY), w),
            right: fitted(shifted(v.right, dr), eye: 1, offset: (dr.offX, dr.offY), w))
        let ex = BreakGazePath.exerciseOpenness(i)
        applyLids(&p, openness: ex + (1 - ex) * settle)
        let fin = BreakGazePath.smooth(remaining / finalFade)
        p.left.brightness *= fin
        p.right.brightness *= fin
        return p
    }

    /// The step's own lid value (shared rhythm: closed holds shut, blink snaps shut each second).
    public static func steadyOpenness(direction: String, phaseElapsed: TimeInterval) -> Double {
        BreakGazePath.steadyOpenness(direction: direction, phaseElapsed: phaseElapsed)
    }

    // MARK: Gaze

    private struct EyeDelta {
        var cx = 0.0, cy = 0.0, radius = 0.0, pupilRadius = 0.0, offX = 0.0, offY = 0.0
        func scaled(_ k: Double) -> EyeDelta {
            EyeDelta(cx: cx * k, cy: cy * k, radius: radius * k, pupilRadius: pupilRadius * k,
                     offX: offX * k, offY: offY * k)
        }
    }

    /// Gaze offsets of both eyes relative to the base pose. Horizontal pupil travel, eyeball
    /// shift and size change are interpolated towards the measured extreme looks of the clip.
    private static func gazeDelta(_ i: Input) -> (left: EyeDelta, right: EyeDelta) {
        let g = BreakGazePath.gazeOffset(i)
        let dx = max(-1, min(1, g.x)), dy = max(-1, min(1, g.y))
        let b = base
        let e = AngryEyesTimeline.pose(at: dx < 0 ? leftLookTime : rightLookTime)
        let k = abs(dx)
        func delta(_ b: AngryEyeGeometry, _ e: AngryEyeGeometry) -> EyeDelta {
            EyeDelta(cx: (e.cx - b.cx) * k, cy: (e.cy - b.cy) * k, radius: (e.radius - b.radius) * k,
                     pupilRadius: (e.pupilRadius - b.pupilRadius) * k,
                     offX: (e.pupilOffsetX - b.pupilOffsetX) * k,
                     offY: dy >= 0 ? dy * downRange : dy * upRange)
        }
        return (delta(b.left, e.left), delta(b.right, e.right))
    }

    private static func shifted(_ g: AngryEyeGeometry, _ d: EyeDelta) -> AngryEyeGeometry {
        var r = g
        r.cx += d.cx
        r.cy += d.cy
        r.radius += d.radius
        r.pupilRadius += d.pupilRadius
        r.pupilX += d.cx + d.offX
        r.pupilY += d.cy + d.offY
        return r
    }

    // MARK: Sharingan iris in the intro, blend and outro

    /// Both eyes in their open state (lids lifted, iris fitted fully inside the opening) plus how far
    /// each lid is closed over that state (1 = open). A closing lid then covers the iris like an eyelid.
    private struct SharinganEyes {
        var left: AngryEyeGeometry, right: AngryEyeGeometry
        var leftOpen = 1.0, rightOpen = 1.0
        func blended(to o: SharinganEyes, _ k: Double) -> SharinganEyes {
            SharinganEyes(left: left.blended(to: o.left, k), right: right.blended(to: o.right, k),
                          leftOpen: leftOpen + (o.leftOpen - leftOpen) * k,
                          rightOpen: rightOpen + (o.rightOpen - rightOpen) * k)
        }
    }

    private static func baseEye(_ eye: Int) -> AngryEyeGeometry { eye == 0 ? base.left : base.right }

    private static func shutY(_ g: AngryEyeGeometry) -> Double {
        g.cy + g.radius + abs(g.lidSlope) + abs(g.lidK) + abs(g.lidQ) + 12
    }

    /// Lid openness of a video eye against the exercise squint: 1 while the lid is at or above the
    /// squint's, falling to 0 as it closes (the clip's fade-in and its final shut).
    private static func videoOpenness(_ g: AngryEyeGeometry, eye: Int) -> Double {
        let b = baseEye(eye).lidY0
        guard g.lidY0 > b else { return 1 }
        return max(0, min(1, (shutY(g) - g.lidY0) / (shutY(g) - b)))
    }

    /// The open state of video eye `g`: the lid lifted like the exercise's (never lower than the
    /// squint), then the iris placed as close as it fits to `desired` (or the gaze `offset` from the
    /// biggest circle).
    private static func openEye(_ g: AngryEyeGeometry, eye: Int, desired: (x: Double, y: Double)?,
                                offset: (x: Double, y: Double) = (0, 0)) -> AngryEyeGeometry {
        var r = g
        r.lidY0 = min(g.lidY0, baseEye(eye).lidY0) - squintLift
        return fitIris(r, eye: eye, desired: desired, offset: offset)
    }

    private static func fitIris(_ r: AngryEyeGeometry, eye: Int, desired: (x: Double, y: Double)?,
                                offset: (x: Double, y: Double) = (0, 0)) -> AngryEyeGeometry {
        let o = opening(r)
        let a = o.largestCircle(centeredAtX: r.cx)
        let off = desired.map { (x: $0.x - a.x, y: $0.y - a.y) } ?? offset
        let c = o.fit(radius: rest[eye].radius, fill: 1, offset: off, anchor: a)
        var e = r
        e.pupilX = c.x
        e.pupilY = c.y
        e.pupilRadius = c.radius
        return e
    }

    private static func sharinganVideo(at t: TimeInterval) -> SharinganEyes {
        let v = AngryEyesTimeline.pose(at: t)
        return SharinganEyes(
            left: openEye(v.left, eye: 0, desired: (v.left.pupilX, v.left.pupilY)),
            right: openEye(v.right, eye: 1, desired: (v.right.pupilX, v.right.pupilY)),
            leftOpen: videoOpenness(v.left, eye: 0), rightOpen: videoOpenness(v.right, eye: 1))
    }

    private static func sharinganExerciseEyes(_ i: Input) -> SharinganEyes {
        let b = base
        let d = gazeDelta(i)
        return SharinganEyes(
            left: openEye(shifted(b.left, d.left), eye: 0, desired: nil, offset: (d.left.offX, d.left.offY)),
            right: openEye(shifted(b.right, d.right), eye: 1, desired: nil, offset: (d.right.offX, d.right.offY)))
    }

    /// Closes each lid by its own openness (the iris is untouched).
    private static func sharinganPose(_ s: SharinganEyes, extraOpen: Double = 1, frame: Double = 0) -> AngryEyesPose {
        func close(_ e: AngryEyeGeometry, _ o: Double) -> AngryEyeGeometry {
            var r = e
            r.lidY0 += (shutY(e) - e.lidY0) * (1 - max(0, min(1, o)))
            return r
        }
        let lo = s.leftOpen * extraOpen, ro = s.rightOpen * extraOpen
        var p = AngryEyesPose(left: close(s.left, lo), right: close(s.right, ro))
        p.lidOpen = min(max(0, min(1, lo)), max(0, min(1, ro)))
        return p
    }

    private static func sharinganExercise(_ i: Input) -> AngryEyesPose {
        let open = BreakGazePath.exerciseOpenness(i)
        let target = sharinganExerciseEyes(i)
        var p: AngryEyesPose
        if i.reduceMotion || i.elapsed >= introDuration + blendDuration {
            p = sharinganPose(target, extraOpen: open)
        } else {
            let k = BreakGazePath.smooth((i.elapsed - introDuration) / blendDuration)
            var s = sharinganVideo(at: introDuration - 1e-9).blended(to: target, k)
            // refit the iris on the blended lids so it never pokes through while they ease
            s.left = fitIris(s.left, eye: 0, desired: (s.left.pupilX, s.left.pupilY))
            s.right = fitIris(s.right, eye: 1, desired: (s.right.pupilX, s.right.pupilY))
            p = sharinganPose(s, extraOpen: 1 + (open - 1) * k)
        }
        p.openness = p.lidOpen
        return p
    }

    private static func sharinganOutro(_ i: Input) -> AngryEyesPose {
        let remaining = min(outroDuration, max(0, i.remaining ?? 0))
        let u = outroDuration - remaining
        let settle = BreakGazePath.smooth(u / outroSettle)
        let w = 1 - settle
        let d = gazeDelta(i)
        let v = AngryEyesTimeline.pose(at: outroVideoStart + u)
        let dl = d.left.scaled(w), dr = d.right.scaled(w)
        let gl = shifted(v.left, dl), gr = shifted(v.right, dr)
        let s = SharinganEyes(
            left: openEye(gl, eye: 0, desired: nil, offset: (dl.offX, dl.offY)),
            right: openEye(gr, eye: 1, desired: nil, offset: (dr.offX, dr.offY)),
            leftOpen: videoOpenness(gl, eye: 0), rightOpen: videoOpenness(gr, eye: 1))
        let ex = BreakGazePath.exerciseOpenness(i)
        var p = sharinganPose(s, extraOpen: ex + (1 - ex) * settle)
        let fin = BreakGazePath.smooth(remaining / finalFade)
        p.left.brightness *= fin
        p.right.brightness *= fin
        return p
    }

    // MARK: Lids

    /// Slides the angled upper lid down over the eyeball; fully shut at `openness` 0.
    private static func applyLids(_ p: inout AngryEyesPose, openness: Double) {
        let o = max(0, min(1, openness))
        p.openness = o
        p.lidOpen = o
        guard o < 1 else { return }
        func close(_ e: inout AngryEyeGeometry) {
            let shut = e.cy + e.radius + abs(e.lidSlope) + abs(e.lidK) + abs(e.lidQ) + 12
            e.lidY0 += (shut - e.lidY0) * (1 - o)
        }
        close(&p.left)
        close(&p.right)
    }
}
