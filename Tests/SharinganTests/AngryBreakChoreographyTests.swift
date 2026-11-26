import Testing
import Foundation
@testable import SharinganCore

@Suite("Angry break choreography")
struct AngryBreakChoreographyTests {
    typealias C = AngryBreakChoreography

    private func input(elapsed: Double = 30, remaining: Double? = 100,
                       direction: String = "center", gaze: GazeDirection = .center,
                       phaseElapsed: Double = 5, hold: Double = 4,
                       previous: Double = 1, reduce: Bool = false) -> C.Input {
        C.Input(elapsed: elapsed, remaining: remaining, direction: direction, gaze: gaze,
                phaseElapsed: phaseElapsed, holdSeconds: hold,
                previousOpenness: previous, reduceMotion: reduce)
    }

    private func isClosed(_ e: AngryEyeGeometry) -> Bool {
        // every point of the slanted lid line is at or below the bottom of the eyeball
        let bottom = e.cy + e.radius
        return min(e.lidY(atU: -1), e.lidY(atU: 1), e.lidY0) >= bottom - 0.5
    }

    // MARK: phases

    @Test("phase boundaries")
    func phases() {
        #expect(C.phase(input(elapsed: 0)) == .intro)
        #expect(C.phase(input(elapsed: C.introDuration - 0.01)) == .intro)
        #expect(C.phase(input(elapsed: C.introDuration + 0.01)) == .exercise)
        #expect(C.phase(input(elapsed: 30, remaining: C.outroDuration + 0.5)) == .exercise)
        #expect(C.phase(input(elapsed: 30, remaining: C.outroDuration - 0.01)) == .outro)
        #expect(C.phase(input(elapsed: 30, remaining: 0)) == .outro)
        #expect(C.phase(input(elapsed: 0, remaining: nil)) == .intro)
        #expect(C.phase(input(elapsed: 1, remaining: 1.0)) == .outro)   // outro wins in a short break
    }

    @Test("intro length is a centre-gaze cut of the video, at most 6 s")
    func introLength() {
        #expect(C.introDuration > 3 && C.introDuration <= 6)
        #expect(C.outroDuration > 1 && C.outroDuration < 2.5)
    }

    @Test("intro plays the video from its start")
    func introStart() {
        #expect(C.pose(input(elapsed: 0)).withPupils(of: AngryEyesTimeline.pose(at: 0)) == AngryEyesTimeline.pose(at: 0))
        let clip = AngryEyesTimeline.pose(at: 2.5)
        #expect(C.pose(input(elapsed: 2.5)).withPupils(of: clip) == clip)   // only the pupils follow the step gaze
    }

    @Test("exercise holds the angry squint at full brightness")
    func exerciseSquint() {
        let p = C.pose(input(elapsed: 40))
        #expect(p.openness == 1)
        #expect(p.left.brightness > 0.95 && p.right.brightness > 0.95)
        #expect(p.left.lidSlope > 40 && p.right.lidSlope < -40)
        #expect(!isClosed(p.left))
        #expect(p.left.lowerY0 > p.left.cy + p.left.radius)   // lower lid out of the way
    }

    // MARK: gaze

    @Test("gaze moves the pupil in its direction and stays clamped")
    func gazeDirections() {
        let c = C.pose(input(gaze: .center))
        let l = C.pose(input(direction: "left", gaze: .left))
        let r = C.pose(input(direction: "right", gaze: .right))
        let u = C.pose(input(direction: "up", gaze: .up))
        let d = C.pose(input(direction: "down", gaze: .down))
        for (a, b) in [(l.left, c.left), (l.right, c.right)] { #expect(a.pupilOffsetX < b.pupilOffsetX - 8) }
        for (a, b) in [(r.left, c.left), (r.right, c.right)] { #expect(a.pupilOffsetX > b.pupilOffsetX + 4) }
        for (a, b) in [(u.left, c.left), (u.right, c.right)] { #expect(a.pupilOffsetY < b.pupilOffsetY - 2) }
        for (a, b) in [(d.left, c.left), (d.right, c.right)] { #expect(a.pupilOffsetY > b.pupilOffsetY + 2) }
        for p in [l, r, u, d] {
            for e in [p.left, p.right] {
                #expect(abs(e.pupilOffsetX) <= 115 && abs(e.pupilOffsetY) <= 140)
                // the pupil never leaves the eyeball
                #expect(hypot(e.pupilOffsetX, e.pupilOffsetY) + e.pupilRadius <= e.radius + 10)
            }
        }
    }

    @Test("diagonal gaze combines both axes")
    func diagonals() {
        let c = C.pose(input(gaze: .center)).left
        let ul = C.pose(input(direction: "up_left", gaze: .upLeft)).left
        #expect(ul.pupilX < c.pupilX - 5 && ul.pupilY < c.pupilY - 2)
        let dr = C.pose(input(direction: "down_right", gaze: .downRight)).left
        #expect(dr.pupilX > c.pupilX + 5 && dr.pupilY > c.pupilY + 1)
    }

    @Test("path gazes sweep, and ease to centre at the step end")
    func paths() {
        let hold = 6.0
        var xs = Set<Int>()
        for i in 0..<40 {
            let p = C.pose(input(direction: "circle_cw", phaseElapsed: 0.6 + Double(i) * 0.1, hold: hold))
            xs.insert(Int(p.left.pupilX.rounded()))
        }
        #expect(xs.count > 10)
        let c = C.pose(input(gaze: .center, reduce: true))   // no idle sway: the exact centre
        let end = C.pose(input(direction: "figure8", phaseElapsed: hold, hold: hold))
        #expect(abs(end.left.pupilX - c.left.pupilX) < 1)
        #expect(abs(end.left.pupilY - c.left.pupilY) < 1)
    }

    // MARK: lids

    @Test("blink snaps shut and reopens each second")
    func blink() {
        func o(_ t: Double) -> Double { C.pose(input(direction: "blink", phaseElapsed: t)).openness }
        #expect(abs(o(1.0) - 1) < 1e-9)
        #expect(o(1.12) < 0.01)
        #expect(o(1.5) > 0.99)
        #expect(isClosed(C.pose(input(direction: "blink", phaseElapsed: 1.12)).left))
    }

    @Test("closed step shuts the lids, easing from the previous openness")
    func closedStep() {
        let p = C.pose(input(direction: "closed", phaseElapsed: 2))
        #expect(p.openness == 0)
        #expect(isClosed(p.left) && isClosed(p.right))
        #expect(C.pose(input(direction: "closed", phaseElapsed: 0, previous: 1)).openness == 1)
    }

    // MARK: reduce motion

    @Test("reduce motion: no intro, no outro, no sway; closed and blink still honoured")
    func reduceMotion() {
        #expect(C.phase(input(elapsed: 0, reduce: true)) == .exercise)
        #expect(C.phase(input(elapsed: 30, remaining: 0.2, reduce: true)) == .exercise)
        let a = C.pose(input(elapsed: 1, reduce: true))
        let b = C.pose(input(elapsed: 2, remaining: 0.1, reduce: true))
        #expect(a == b)
        #expect(a.left.brightness > 0.95)
        #expect(C.pose(input(direction: "closed", reduce: true)).openness == 0)
        #expect(C.pose(input(direction: "blink", phaseElapsed: 1.12, reduce: true)).openness == 1)
    }

    // MARK: outro

    @Test("outro: gaze centres, brightness fades, eyes are dark exactly at the end")
    func outro() {
        let mid = C.pose(input(remaining: C.outroDuration * 0.75, direction: "right", gaze: .right))
        // the gaze has faded into the clip's own centred pupil (the fitted iris eased back out)
        let video = AngryEyesTimeline.pose(at: C.outroVideoStart + C.outroDuration * 0.25)
        #expect(abs(mid.left.pupilOffsetX - video.left.pupilOffsetX) < 25)
        let early = C.pose(input(remaining: C.outroDuration - 0.01))
        #expect(early.left.brightness > 0.9)
        let end = C.pose(input(remaining: 0))
        #expect(end.isDark)
        #expect(end.left.brightness == 0 && end.right.brightness == 0)
    }

    @Test("brightness never rises during the outro")
    func outroMonotonic() {
        let bs = stride(from: C.outroDuration, through: 0, by: -1.0 / 60).map { C.pose(input(remaining: $0)).left.brightness }
        #expect(zip(bs, bs.dropFirst()).allSatisfy { $0 + 1e-9 >= $1 })
    }

    // MARK: continuity

    private func maxStep(_ poses: [AngryEyesPose]) -> Double {
        var worst = 0.0
        for (a, b) in zip(poses, poses.dropFirst()) {
            for (x, y) in [(a.left, b.left), (a.right, b.right)] {
                worst = max(worst, abs(x.cx - y.cx), abs(x.cy - y.cy), abs(x.radius - y.radius),
                            abs(x.lidY0 - y.lidY0), abs(x.pupilX - y.pupilX), abs(x.pupilY - y.pupilY))
            }
        }
        return worst
    }

    @Test("no jump at the intro to exercise blend")
    func introToExercise() {
        let ps = stride(from: C.introDuration - 1.0 / 120, through: C.introDuration + 1.0, by: 1.0 / 120).map { C.pose(input(elapsed: $0)) }
        #expect(maxStep(ps) < 8)
    }

    @Test("no jump from exercise into the outro")
    func exerciseToOutro() {
        for dir in [("right", GazeDirection.right), ("left", .left), ("down", .down), ("center", .center)] {
            let ps = stride(from: C.outroDuration + 0.5, through: C.outroDuration - 0.5, by: -1.0 / 120).map {
                C.pose(input(remaining: $0, direction: dir.0, gaze: dir.1))
            }
            #expect(maxStep(ps) < 5, "direction \(dir.0)")
        }
    }

    // MARK: vertical gaze travel

    @Test("up and down move both irises clearly from centre, (both iris styles)")
    func verticalTravel() {
        for iris in [BreakIrisStyle.sharingan, .original] {
            func pose(_ d: String, _ g: GazeDirection) -> AngryEyesPose {
                C.pose(.init(elapsed: 30, remaining: 100, direction: d, gaze: g, phaseElapsed: 3,
                             holdSeconds: 4, previousOpenness: 1, reduceMotion: true, iris: iris))
            }
            let c = pose("center", .center), l = pose("left", .left)
            let u = pose("up", .up), d = pose("down", .down)
            for (name, get) in [("left eye", { (p: AngryEyesPose) in p.left }), ("right eye", { $0.right })] {
                let e = get(c)
                let left = e.pupilX - get(l).pupilX
                let up = e.pupilY - get(u).pupilY
                let down = get(d).pupilY - e.pupilY
                #expect(up >= 22, "\(iris) \(name) up \(up)")
                #expect(down >= 22, "\(iris) \(name) down \(down)")
            }
        }
    }
}
