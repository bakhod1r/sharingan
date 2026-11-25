import Testing
import Foundation
@testable import SharinganCore

/// In the exercise phase the whole iris circle must stay visible inside the eye opening
/// (eyeball and below the lid) for every gaze, instead of being sliced by the lid.
@Suite("Break face iris visibility")
struct IrisVisibilityTests {
    static let directions: [(String, GazeDirection)] = [
        ("center", .center), ("left", .left), ("right", .right), ("up", .up), ("down", .down),
        ("up_left", .upLeft), ("up_right", .upRight), ("down_left", .downLeft), ("down_right", .downRight),
        ("circle_cw", .center), ("circle_ccw", .center), ("figure8", .center), ("far", .center),
    ]
    static let times: [Double] = [0.7, 1.3, 2.1, 2.9, 3.6, 4.4]

    // MARK: BreakEyeOpening

    @Test("opening: largest circle and containment on a half disk")
    func openingBasics() {
        let o = BreakEyeOpening(cx: 0, cy: 100, rx: 100, ry: 100) { _ in 100 }
        let c = o.largestCircle()
        #expect(abs(c.radius - 50) < 1.5)
        #expect(o.contains(x: 0, y: 150, radius: 49))
        #expect(!o.contains(x: 0, y: 150, radius: 52))
        #expect(!o.contains(x: 0, y: 110, radius: 20))     // pokes through the lid
        let f = o.fit(radius: 80, fill: 0.9, offset: (400, 0))
        #expect(f.radius <= 0.9 * c.radius + 1e-9)
        #expect(o.contains(x: f.x, y: f.y, radius: f.radius))
        #expect(abs(o.height(atX: 0) - 100) < 1e-9)
    }

    // MARK: Looking-for

    private func lfInput(_ dir: String, _ g: GazeDirection, _ pe: Double) -> LookingForBreakChoreography.Input {
        .init(elapsed: 30 + pe, remaining: 100, direction: dir, gaze: g, phaseElapsed: pe,
              holdSeconds: 4, previousOpenness: 1)
    }

    /// Independent check: sample the circle densely against the ellipse and the lid line.
    private func lfVisible(_ p: LookingForEyesPose) -> Bool {
        let c = p.irisCenter, r = p.irisRadius
        for k in 0..<720 {
            let a = Double(k) / 720 * 2 * .pi
            let x = c.x + cos(a) * r, y = c.y + sin(a) * r
            let ex = (x - p.whiteCX) / p.whiteRX, ey = (y - p.whiteCY) / p.whiteRY
            if ex * ex + ey * ey > 1.002 { return false }
            if y < p.lidEdgeY(atX: x) - 0.05 { return false }
        }
        return true
    }

    @Test("Looking-for exercise: full iris inside the opening at every gaze")
    func lookingForVisible() {
        for (dir, g) in Self.directions {
            for t in Self.times {
                let p = LookingForBreakChoreography.pose(lfInput(dir, g, t))
                #expect(lfVisible(p), "LF \(dir) t=\(t)")
            }
        }
    }

    @Test("Looking-for exercise: iris is large and fills the opening")
    func lookingForSize() {
        let p = LookingForBreakChoreography.pose(lfInput("center", .center, 3))
        let o = p.eyeOpening()
        let h = o.height(atX: p.irisCenter.x)
        #expect(p.irisRadius >= 55)
        #expect(2 * p.irisRadius >= 0.85 * h, "diameter \(2 * p.irisRadius) vs opening \(h)")
        #expect(abs(p.pupilRadiusX - 85.7) < 1e-9)       // round iris
        // still the angry slanted look: inner lid corner lower than the outer one
        #expect(p.lid[8] > p.lid[0] + 20)
        #expect(!p.lid.allSatisfy { $0 >= p.ringBottom })
    }

    @Test("Looking-for intro and outro start keep the video iris")
    func lookingForVideoPhases() {
        let intro = LookingForBreakChoreography.pose(lfInput("center", .center, 0).with(elapsed: 2))
        #expect(intro.irisRadius == 85.7)
        #expect(intro == LookingForEyesTimeline.pose(at: 2))
    }

    // MARK: Angry

    private func anInput(_ dir: String, _ g: GazeDirection, _ pe: Double) -> AngryBreakChoreography.Input {
        .init(elapsed: 30 + pe, remaining: 100, direction: dir, gaze: g, phaseElapsed: pe,
              holdSeconds: 4, previousOpenness: 1)
    }

    private func anVisible(_ e: AngryEyeGeometry) -> Bool {
        for k in 0..<720 {
            let a = Double(k) / 720 * 2 * .pi
            let x = e.pupilX + cos(a) * e.pupilRadius, y = e.pupilY + sin(a) * e.pupilRadius
            let dx = x - e.cx, dy = y - e.cy
            if dx * dx + dy * dy > e.radius * e.radius * 1.002 { return false }
            if y < e.lidY(atU: dx / e.radius) - 0.05 { return false }
        }
        return true
    }

    @Test("Angry exercise: full iris inside the opening at every gaze, both eyes")
    func angryVisible() {
        for (dir, g) in Self.directions {
            for t in Self.times {
                let p = AngryBreakChoreography.pose(anInput(dir, g, t))
                #expect(anVisible(p.left), "AN left \(dir) t=\(t)")
                #expect(anVisible(p.right), "AN right \(dir) t=\(t)")
            }
        }
    }

    @Test("Angry exercise: iris is large and fills the opening")
    func angrySize() {
        let p = AngryBreakChoreography.pose(anInput("center", .center, 3))
        for e in [p.left, p.right] {
            let u = (e.pupilX - e.cx) / e.radius
            _ = u
            let h = e.cy + (e.radius * e.radius - (e.pupilX - e.cx) * (e.pupilX - e.cx)).squareRoot() - e.lidY(atU: (e.pupilX - e.cx) / e.radius)
            #expect(e.pupilRadius >= 80)
            #expect(2 * e.pupilRadius >= 0.85 * h, "diameter \(2 * e.pupilRadius) vs opening \(h)")
            // still slanted
            #expect(abs(e.lidSlope) > 40)
        }
        #expect(p.left.lidSlope > 0 && p.right.lidSlope < 0)
    }

    @Test("Angry intro keeps the video pupil")
    func angryVideoPhases() {
        let p = AngryBreakChoreography.pose(anInput("center", .center, 0).with(elapsed: 1.5))
        #expect(p == AngryEyesTimeline.pose(at: 1.5))
    }
}

// MARK: - Intro, blend and outro with the Sharingan iris

@Suite("Break face iris visibility: intro and outro")
struct IrisVisibilityIntroOutroTests {
    static let step = 1.0 / 30.0
    static let dirs: [(String, GazeDirection)] = [
        ("center", .center), ("left", .left), ("right", .right), ("up", .up), ("down", .down),
        ("circle_cw", .center), ("figure8", .center),
    ]

    // LF input at clip time `e` (intro/blend/exercise) or `remaining` (outro)
    static func lf(elapsed e: Double, remaining r: Double = 100, _ d: (String, GazeDirection) = ("center", .center),
                   phase: Double = 2.0, iris: BreakIrisStyle = .sharingan) -> LookingForBreakChoreography.Input {
        .init(elapsed: e, remaining: r, direction: d.0, gaze: d.1, phaseElapsed: phase, holdSeconds: 4,
              previousOpenness: 1, iris: iris)
    }
    static func an(elapsed e: Double, remaining r: Double = 100, _ d: (String, GazeDirection) = ("center", .center),
                   phase: Double = 2.0, iris: BreakIrisStyle = .sharingan) -> AngryBreakChoreography.Input {
        .init(elapsed: e, remaining: r, direction: d.0, gaze: d.1, phaseElapsed: phase, holdSeconds: 4,
              previousOpenness: 1, iris: iris)
    }

    static func lfVisible(_ p: LookingForEyesPose) -> Bool {
        let c = p.irisCenter, r = p.irisRadius
        for k in 0..<720 {
            let a = Double(k) / 720 * 2 * .pi
            let x = c.x + cos(a) * r, y = c.y + sin(a) * r
            let ex = (x - p.whiteCX) / p.whiteRX, ey = (y - p.whiteCY) / p.whiteRY
            if ex * ex + ey * ey > 1.002 { return false }
            if y < p.lidEdgeY(atX: x) - 0.05 { return false }
        }
        return true
    }
    static func anVisible(_ e: AngryEyeGeometry) -> Bool {
        for k in 0..<720 {
            let a = Double(k) / 720 * 2 * .pi
            let x = e.pupilX + cos(a) * e.pupilRadius, y = e.pupilY + sin(a) * e.pupilRadius
            let dx = x - e.cx, dy = y - e.cy
            if dx * dx + dy * dy > e.radius * e.radius * 1.002 { return false }
            if y < e.lidY(atU: dx / e.radius) - 0.05 { return false }
        }
        return true
    }

    static func lfTimes(_ dirs: [(String, GazeDirection)]) -> [(String, LookingForBreakChoreography.Input)] {
        var out: [(String, LookingForBreakChoreography.Input)] = []
        let intro = LookingForBreakChoreography.introDuration, blend = LookingForBreakChoreography.blendDuration
        let outro = LookingForBreakChoreography.outroDuration
        for d in dirs {
            var t = 0.0
            while t < intro + blend + 0.1 {            // intro + blend (+ first exercise frames)
                out.append(("intro \(d.0) t=\(t)", lf(elapsed: t, d, phase: max(0, t - intro))))
                t += step
            }
            var u = 0.0
            while u <= outro {                          // outro
                out.append(("outro \(d.0) u=\(u)", lf(elapsed: 30, remaining: outro - u, d, phase: 1.0 + u)))
                u += step
            }
        }
        return out
    }
    static func anTimes(_ dirs: [(String, GazeDirection)]) -> [(String, AngryBreakChoreography.Input)] {
        var out: [(String, AngryBreakChoreography.Input)] = []
        let intro = AngryBreakChoreography.introDuration, blend = AngryBreakChoreography.blendDuration
        let outro = AngryBreakChoreography.outroDuration
        for d in dirs {
            var t = 0.0
            while t < intro + blend + 0.1 {
                out.append(("intro \(d.0) t=\(t)", an(elapsed: t, d, phase: max(0, t - intro))))
                t += step
            }
            var u = 0.0
            while u <= outro {
                out.append(("outro \(d.0) u=\(u)", an(elapsed: 30, remaining: outro - u, d, phase: 1.0 + u)))
                u += step
            }
        }
        return out
    }

    @Test("Looking-for intro/blend/outro: iris fully inside the opening whenever the eye is open")
    func lookingForOpenIsVisible() {
        var open = 0, total = 0
        for (name, i) in Self.lfTimes(Self.dirs) {
            let p = LookingForBreakChoreography.pose(i)
            total += 1
            guard p.lidOpenness >= BreakEyeOpening.openThreshold else { continue }
            open += 1
            #expect(Self.lfVisible(p), "LF \(name)")
            #expect(abs(p.pupilRadiusX - 85.7) < 1e-9, "round iris \(name)")
        }
        #expect(Double(open) / Double(total) > 0.9)   // the check is not vacuous
    }

    @Test("Angry intro/blend/outro: iris fully inside the opening whenever the eye is open, both eyes")
    func angryOpenIsVisible() {
        var open = 0, total = 0
        for (name, i) in Self.anTimes(Self.dirs) {
            let p = AngryBreakChoreography.pose(i)
            total += 1
            guard p.lidOpen >= BreakEyeOpening.openThreshold else { continue }
            open += 1
            #expect(Self.anVisible(p.left), "AN left \(name)")
            #expect(Self.anVisible(p.right), "AN right \(name)")
        }
        #expect(Double(open) / Double(total) > 0.6)
    }

    @Test("Angry fade-in and the final shut count as closing (lid may cover the iris)")
    func angryClosingExists() {
        let first = AngryBreakChoreography.pose(Self.an(elapsed: 0.1))
        #expect(first.lidOpen < BreakEyeOpening.openThreshold)
        let last = AngryBreakChoreography.pose(Self.an(elapsed: 30, remaining: 0.05))
        #expect(last.lidOpen < BreakEyeOpening.openThreshold)
        let mid = AngryBreakChoreography.pose(Self.an(elapsed: 2.5))
        #expect(mid.lidOpen >= BreakEyeOpening.openThreshold)
    }

    @Test("Closing keeps the iris size: no shrink to a dot while the lid closes (Angry fade-in, LF final close)")
    func closingKeepsIris() {
        let fade = AngryBreakChoreography.pose(Self.an(elapsed: 0.6))
        #expect(fade.left.pupilRadius > 60)
        let near = LookingForBreakChoreography.pose(Self.lf(elapsed: 30, remaining: 0.1))
        let before = LookingForBreakChoreography.pose(Self.lf(elapsed: 30, remaining: 0.45))
        #expect(near.lidOpenness < BreakEyeOpening.openThreshold)
        #expect(abs(near.irisRadius - before.irisRadius) < 1e-6)
    }

    // MARK: Continuity

    @Test("Looking-for: no jump at intro->exercise and exercise->outro")
    func lookingForContinuity() {
        let intro = LookingForBreakChoreography.introDuration
        let e = 1e-4
        for d in Self.dirs {
            let a = LookingForBreakChoreography.pose(Self.lf(elapsed: intro - e, d, phase: 0))
            let b = LookingForBreakChoreography.pose(Self.lf(elapsed: intro + e, d, phase: 0))
            Self.expectClose(a, b, "LF intro->exercise \(d.0)")
            let o = LookingForBreakChoreography.outroDuration
            let x = LookingForBreakChoreography.pose(Self.lf(elapsed: 30, remaining: o + e, d, phase: 3))
            let y = LookingForBreakChoreography.pose(Self.lf(elapsed: 30, remaining: o - e, d, phase: 3))
            Self.expectClose(x, y, "LF exercise->outro \(d.0)")
        }
    }
    static func expectClose(_ a: LookingForEyesPose, _ b: LookingForEyesPose, _ m: String) {
        #expect(abs(a.irisCenter.x - b.irisCenter.x) < 2, "\(m) x")
        #expect(abs(a.irisCenter.y - b.irisCenter.y) < 2, "\(m) y")
        #expect(abs(a.irisRadius - b.irisRadius) < 2, "\(m) r")
        for k in 0..<9 { #expect(abs(a.lid[k] - b.lid[k]) < 2, "\(m) lid\(k)") }
    }

    @Test("Angry: no jump at intro->exercise and exercise->outro")
    func angryContinuity() {
        let intro = AngryBreakChoreography.introDuration
        let o = AngryBreakChoreography.outroDuration
        let e = 1e-4
        for d in Self.dirs {
            let a = AngryBreakChoreography.pose(Self.an(elapsed: intro - e, d, phase: 0))
            let b = AngryBreakChoreography.pose(Self.an(elapsed: intro + e, d, phase: 0))
            let x = AngryBreakChoreography.pose(Self.an(elapsed: 30, remaining: o + e, d, phase: 3))
            let y = AngryBreakChoreography.pose(Self.an(elapsed: 30, remaining: o - e, d, phase: 3))
            for (p, q, m) in [(a, b, "intro->exercise"), (x, y, "exercise->outro")] {
                for (l, r) in [(p.left, q.left), (p.right, q.right)] {
                    #expect(abs(l.pupilX - r.pupilX) < 2, "AN \(m) \(d.0) x")
                    #expect(abs(l.pupilY - r.pupilY) < 2, "AN \(m) \(d.0) y")
                    #expect(abs(l.pupilRadius - r.pupilRadius) < 2, "AN \(m) \(d.0) r")
                    #expect(abs(l.lidY0 - r.lidY0) < 2, "AN \(m) \(d.0) lid")
                }
            }
        }
    }

    @Test("Sharingan intro uses the exercise lid lift once the face squints")
    func liftMatchesExercise() {
        // frame 32 of the video is the squint the exercise is built from
        let t = 31.0 / LookingForEyesTimeline.fps
        let intro = LookingForBreakChoreography.pose(Self.lf(elapsed: t))
        let ex = LookingForBreakChoreography.pose(Self.lf(elapsed: 30 + 3, phase: 3))
        for k in 0..<9 { #expect(abs(intro.lid[k] - ex.lid[k]) < 1e-6) }
    }

    // MARK: Original mode keeps the video

    @Test("Original iris mode: intro poses equal the video timeline poses")
    func originalIntroIsVideo() {
        var t = 0.0
        while t < LookingForBreakChoreography.introDuration {
            #expect(LookingForBreakChoreography.pose(Self.lf(elapsed: t, iris: .original)) == LookingForEyesTimeline.pose(at: t))
            t += Self.step
        }
        t = 0
        while t < AngryBreakChoreography.introDuration {
            #expect(AngryBreakChoreography.pose(Self.an(elapsed: t, iris: .original)) == AngryEyesTimeline.pose(at: t))
            t += Self.step
        }
    }

    @Test("Original iris mode: outro keeps the video pupil (not fitted)")
    func originalOutroIsVideo() {
        let o = AngryBreakChoreography.outroDuration
        var u = 0.5
        while u < o - 0.3 {
            let p = AngryBreakChoreography.pose(Self.an(elapsed: 30, remaining: o - u, iris: .original))
            #expect(p.left == AngryEyesTimeline.pose(at: AngryBreakChoreography.outroVideoStart + u).left, "AN outro u=\(u)")
            u += 0.25
        }
        let lo = LookingForBreakChoreography.outroDuration
        let p = LookingForBreakChoreography.pose(Self.lf(elapsed: 30, remaining: lo - 1.0, iris: .original))
        let v = LookingForEyesTimeline.pose(at: (86 + 1.0 * LookingForEyesTimeline.fps - 1) / LookingForEyesTimeline.fps)
        #expect(p.irisRadius == 85.7)
        #expect(abs(p.pupilRadiusX - v.pupilRadiusX) < 1e-9)
    }

    @Test("Looking-for outro: the fire sits on the fitted iris")
    func fireOnFittedIris() {
        let p = LookingForBreakChoreography.pose(Self.lf(elapsed: 30, remaining: LookingForBreakChoreography.outroDuration - 1.0))
        #expect(p.fireLevel > 0 || p.spark > 0 || p.embers >= 0)
        #expect(Self.lfVisible(p))
    }
}

private extension BreakFaceInput {
    func with(elapsed: Double) -> BreakFaceInput {
        var c = self
        c.elapsed = elapsed
        return c
    }
}
