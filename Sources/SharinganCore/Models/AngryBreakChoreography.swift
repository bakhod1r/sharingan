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

    // MARK: Exercise iris fit

    /// The exercise squint raises the lids by this much (eye-space px); the slant is unchanged.
    public static let squintLift = 14.0
    /// Iris radius of an eye: `irisWidthFraction` of the resting eye-white width (capped by what fits).
    /// Taken from the resting eyeball, not the gaze-shifted one, so it is the same in every direction.
    private static func irisRadius(eye: Int) -> Double { BreakEyeOpening.irisWidthFraction * baseEye(eye).radius }
    /// Extra lid lift (eye-space px) at a full up gaze: the upper lid follows the eyes upward.
    private static let upLidLift = 30.0
    /// Idle gaze sway (|dy| < 0.05) leaves the lids untouched.
    private static let gazeDeadZone = 0.05
    private static func extraLift(_ lookY: Double) -> Double { upLidLift * min(1, max(0, -lookY - gazeDeadZone) / (1 - gazeDeadZone)) }
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

    /// Lifts the lid and fits the iris of `g` so the whole circle is visible (`k` 1 = fitted,
    /// 0 = untouched video values; the outro eases between them).
    private static func fitted(_ g: AngryEyeGeometry, eye: Int, look: (x: Double, y: Double), _ k: Double,
                               cap: (x: Double, y: Double) = (.infinity, .infinity)) -> AngryEyeGeometry {
        var g = g
        g.pupilRadius = irisRadius(eye: eye)                // the clip's pupil, at the common size
        guard k > 0 else { return g }
        let extra = extraLift(look.y)
        var r = lifted(g, k)
        r.lidY0 -= extra * k
        let c = place(liftedFull(g, lookY: 0), liftedFull(g, lookY: look.y), eye: eye, look: look, cap: cap)
        r.pupilX += (c.x - g.pupilX) * k
        r.pupilY += (c.y - g.pupilY) * k
        r.pupilRadius += (c.radius - g.pupilRadius) * k
        return r
    }

    /// The open state of `g` on the exercise squint (lid lifted by the squint and the up gaze).
    private static func liftedFull(_ g: AngryEyeGeometry, lookY: Double) -> AngryEyeGeometry {
        var full = lifted(g, 1)
        full.lidY0 -= extraLift(lookY)
        return full
    }

    /// The iris at its resting spot (largest circle of the gaze-free opening `rest`), then carried
    /// vertically by `lookY` (-1...1) of its travel to the edge of the gaze's opening `full`
    /// (lid lifted for an up gaze), at most `cap.y`.
    private static func level(rest: AngryEyeGeometry, full: AngryEyeGeometry, eye: Int, lookY: Double,
                              cap: Double) -> (opening: BreakEyeOpening, circle: BreakEyeOpening.Circle) {
        let o0 = opening(rest)
        let a = o0.largestCircle(centeredAtX: rest.cx)
        let start = o0.fit(radius: irisRadius(eye: eye), fill: 1, anchor: a)
        let o = opening(full)
        return (o, o.rise(start, look: lookY, cap: cap))
    }

    /// Iris of `full` for a gaze: first the vertical move (so diagonals keep their up/down travel),
    /// then a horizontal slide by `look.x` (-1...1) of the travel to the opening's edge, at most `cap.x`.
    private static func place(_ rest: AngryEyeGeometry, _ full: AngryEyeGeometry, eye: Int,
                              look: (x: Double, y: Double), cap: (x: Double, y: Double)) -> BreakEyeOpening.Circle {
        let l = level(rest: rest, full: full, eye: eye, lookY: look.y, cap: cap.y)
        return l.opening.slide(l.circle, look: look.x, cap: cap.x)
    }

    /// Vertical travel of the iris of `full` toward the side of `lookY` (0 = no vertical look).
    private static func verticalReach(_ rest: AngryEyeGeometry, _ full: AngryEyeGeometry, eye: Int, lookY: Double) -> Double {
        guard lookY != 0 else { return .infinity }
        let l = level(rest: rest, full: full, eye: eye, lookY: 0, cap: .infinity)
        return l.opening.verticalTravel(from: l.circle, toward: lookY)
    }

    /// Horizontal travel of the iris of `full` (already carried vertically) toward the side of `look.x`.
    private static func horizontalReach(_ rest: AngryEyeGeometry, _ full: AngryEyeGeometry, eye: Int,
                                        look: (x: Double, y: Double), vcap: Double) -> Double {
        guard look.x != 0 else { return .infinity }
        let l = level(rest: rest, full: full, eye: eye, lookY: look.y, cap: vcap)
        return l.opening.horizontalTravel(from: l.circle, toward: look.x)
    }

    /// The smaller of the two eyes' reach: both irises move by the same distance, vertically and sideways.
    private static func commonReach(_ l: AngryEyeGeometry, _ r: AngryEyeGeometry, _ d: (left: EyeDelta, right: EyeDelta),
                                    open: Bool) -> (x: Double, y: Double) {
        func geoms(_ g: AngryEyeGeometry, _ e: Int, _ lookY: Double) -> (AngryEyeGeometry, AngryEyeGeometry) {
            open ? (openFull(g, eye: e, lookY: 0), openFull(g, eye: e, lookY: lookY))
                 : (liftedFull(g, lookY: 0), liftedFull(g, lookY: lookY))
        }
        let (rl, fl) = geoms(l, 0, d.left.lookY), (rr, fr) = geoms(r, 1, d.right.lookY)
        let vcap = min(verticalReach(rl, fl, eye: 0, lookY: d.left.lookY),
                       verticalReach(rr, fr, eye: 1, lookY: d.right.lookY))
        let hcap = min(horizontalReach(rl, fl, eye: 0, look: (d.left.lookX, d.left.lookY), vcap: vcap),
                       horizontalReach(rr, fr, eye: 1, look: (d.right.lookX, d.right.lookY), vcap: vcap))
        return (hcap, vcap)
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
            return introPose(i, at: i.elapsed)
        case .exercise:
            if i.iris == .sharingan { return sharinganExercise(i) }
            let target = exercisePose(i, openness: BreakGazePath.exerciseOpenness(i))
            if i.reduceMotion || i.elapsed >= introDuration + blendDuration { return target }
            let from = introPose(i, at: introDuration - 1e-9)
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
        let gl = shifted(b.left, d.left), gr = shifted(b.right, d.right)
        let cap = commonReach(gl, gr, d, open: false)
        var p = AngryEyesPose(left: fitted(gl, eye: 0, look: (d.left.lookX, d.left.lookY), 1, cap: cap),
                              right: fitted(gr, eye: 1, look: (d.right.lookX, d.right.lookY), 1, cap: cap))
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
        let gl = shifted(v.left, dl), gr = shifted(v.right, dr)
        let cap = commonReach(gl, gr, (dl, dr), open: false)
        var p = AngryEyesPose(
            left: fitted(gl, eye: 0, look: (dl.lookX, dl.lookY), w, cap: cap),
            right: fitted(gr, eye: 1, look: (dr.lookX, dr.lookY), w, cap: cap))
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
        var cx = 0.0, cy = 0.0, radius = 0.0, pupilRadius = 0.0, lookX = 0.0, lookY = 0.0
        func scaled(_ k: Double) -> EyeDelta {
            EyeDelta(cx: cx * k, cy: cy * k, radius: radius * k, pupilRadius: pupilRadius * k,
                     lookX: lookX * k, lookY: lookY * k)
        }
    }

    /// Gaze of both eyes relative to the base pose. Eyeball shift and size change are interpolated
    /// towards the measured extreme looks of the clip; the iris moves by `lookY` / `lookX` (-1...1)
    /// of the way to the edge of the opening (up / down / sideways).
    private static func gazeDelta(_ i: Input) -> (left: EyeDelta, right: EyeDelta) {
        let g = BreakGazePath.gazeOffset(i)
        let dx = max(-1, min(1, g.x)), dy = max(-1, min(1, g.y))
        let b = base
        let e = AngryEyesTimeline.pose(at: dx < 0 ? leftLookTime : rightLookTime)
        let k = abs(dx)
        func delta(_ b: AngryEyeGeometry, _ e: AngryEyeGeometry) -> EyeDelta {
            EyeDelta(cx: (e.cx - b.cx) * k, cy: (e.cy - b.cy) * k, radius: (e.radius - b.radius) * k,
                     pupilRadius: (e.pupilRadius - b.pupilRadius) * k,
                     lookX: dx, lookY: dy)
        }
        return (delta(b.left, e.left), delta(b.right, e.right))
    }

    private static func shifted(_ g: AngryEyeGeometry, _ d: EyeDelta) -> AngryEyeGeometry {
        var r = g
        r.cx += d.cx
        r.cy += d.cy
        r.radius += d.radius
        r.pupilRadius += d.pupilRadius
        r.pupilX += d.cx
        r.pupilY += d.cy
        return r
    }

    // MARK: Intro

    /// The clip fades in over its first second; the pupils hand over to the step gaze while it
    /// brightens (start) and are fully on it `introGazeStart + introGazeRamp` seconds in.
    public static let introGazeStart: TimeInterval = 0.5
    public static let introGazeRamp: TimeInterval = 0.5

    /// The clip at `t` (fade, lids, brows) with the pupils following the step's gaze.
    private static func introPose(_ i: Input, at t: TimeInterval) -> AngryEyesPose {
        let w = BreakGazePath.introFollow(t, start: introGazeStart, ramp: introGazeRamp)
        if i.iris == .sharingan { return sharinganPose(sharinganVideo(i, at: t, follow: w)) }
        var p = AngryEyesTimeline.pose(at: t)
        p.left.pupilRadius = irisRadius(eye: 0)             // the clip's pupil, at the common size
        p.right.pupilRadius = irisRadius(eye: 1)
        guard w > 0 else { return p }
        let target = exercisePose(i, openness: 1)
        func follow(_ e: inout AngryEyeGeometry, _ g: AngryEyeGeometry) {
            e.pupilX += (e.cx + (g.pupilX - g.cx) - e.pupilX) * w
            e.pupilY += (e.cy + (g.pupilY - g.cy) - e.pupilY) * w
        }
        follow(&p.left, target.left)
        follow(&p.right, target.right)
        return p
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
                                offset: (x: Double, y: Double) = (0, 0),
                                cap: (x: Double, y: Double) = (.infinity, .infinity)) -> AngryEyeGeometry {
        let r = openFull(g, eye: eye, lookY: desired == nil ? offset.y : 0, lifted: desired == nil)
        let rest = openFull(g, eye: eye, lookY: 0, lifted: desired == nil)
        return fitIris(r, eye: eye, desired: desired, offset: offset, cap: cap, rest: rest)
    }

    /// `g` with the lid at the exercise's open state (never lower than the squint's), plus the up-gaze lift.
    private static func openFull(_ g: AngryEyeGeometry, eye: Int, lookY: Double, lifted up: Bool = true) -> AngryEyeGeometry {
        var r = g
        r.lidY0 = min(g.lidY0, baseEye(eye).lidY0) - squintLift - (up ? extraLift(lookY) : 0)
        return r
    }

    /// `offset.x` is the sideways look (-1...1) when `desired` is nil; `desired` is a target centre.
    private static func fitIris(_ r: AngryEyeGeometry, eye: Int, desired: (x: Double, y: Double)?,
                                offset: (x: Double, y: Double) = (0, 0),
                                cap: (x: Double, y: Double) = (.infinity, .infinity),
                                rest: AngryEyeGeometry? = nil) -> AngryEyeGeometry {
        let o = opening(r)
        let a = o.largestCircle(centeredAtX: r.cx)
        let c: BreakEyeOpening.Circle
        if let d = desired {
            c = o.fit(radius: irisRadius(eye: eye), fill: 1, offset: (d.x - a.x, d.y - a.y), anchor: a)
        } else {
            let l = level(rest: rest ?? r, full: r, eye: eye, lookY: offset.y, cap: cap.y)
            c = l.opening.slide(l.circle, look: offset.x, cap: cap.x)
        }
        var e = r
        e.pupilX = c.x
        e.pupilY = c.y
        e.pupilRadius = c.radius
        return e
    }

    private static func sharinganVideo(_ i: Input, at t: TimeInterval, follow w: Double) -> SharinganEyes {
        let v = AngryEyesTimeline.pose(at: t)
        let tg = w > 0 ? sharinganExerciseEyes(i) : nil
        func desired(_ e: AngryEyeGeometry, _ g: AngryEyeGeometry?) -> (x: Double, y: Double) {
            guard let g else { return (e.pupilX, e.pupilY) }
            return (e.pupilX + (e.cx + (g.pupilX - g.cx) - e.pupilX) * w,
                    e.pupilY + (e.cy + (g.pupilY - g.cy) - e.pupilY) * w)
        }
        return SharinganEyes(
            left: openEye(v.left, eye: 0, desired: desired(v.left, tg?.left)),
            right: openEye(v.right, eye: 1, desired: desired(v.right, tg?.right)),
            leftOpen: videoOpenness(v.left, eye: 0), rightOpen: videoOpenness(v.right, eye: 1))
    }

    private static func sharinganExerciseEyes(_ i: Input) -> SharinganEyes {
        let b = base
        let d = gazeDelta(i)
        let gl = shifted(b.left, d.left), gr = shifted(b.right, d.right)
        let cap = commonReach(gl, gr, d, open: true)
        return SharinganEyes(
            left: openEye(gl, eye: 0, desired: nil, offset: (d.left.lookX, d.left.lookY), cap: cap),
            right: openEye(gr, eye: 1, desired: nil, offset: (d.right.lookX, d.right.lookY), cap: cap))
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
            var s = sharinganVideo(i, at: introDuration - 1e-9, follow: 1).blended(to: target, k)
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
        let cap = commonReach(gl, gr, (dl, dr), open: true)
        let s = SharinganEyes(
            left: openEye(gl, eye: 0, desired: nil, offset: (dl.lookX, dl.lookY), cap: cap),
            right: openEye(gr, eye: 1, desired: nil, offset: (dr.lookX, dr.lookY), cap: cap),
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
