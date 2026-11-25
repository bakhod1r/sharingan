import Testing
import Foundation
@testable import SharinganCore

@Suite("Looking-for break choreography")
struct LookingForBreakChoreographyTests {
    typealias C = LookingForBreakChoreography

    private func input(elapsed: Double = 30, remaining: Double? = 100,
                       direction: String = "center", gaze: GazeDirection = .center,
                       phaseElapsed: Double = 5, hold: Double = 4,
                       previous: Double = 1, reduce: Bool = false) -> C.Input {
        C.Input(elapsed: elapsed, remaining: remaining, direction: direction, gaze: gaze,
                phaseElapsed: phaseElapsed, holdSeconds: hold,
                previousOpenness: previous, reduceMotion: reduce)
    }

    private func isClosed(_ p: LookingForEyesPose) -> Bool {
        p.lid.allSatisfy { $0 >= p.ringBottom }
    }

    // MARK: phases

    @Test("phase boundaries")
    func phases() {
        #expect(C.phase(input(elapsed: 0)) == .intro)
        #expect(C.phase(input(elapsed: 5.0)) == .intro)
        #expect(C.phase(input(elapsed: 5.1)) == .exercise)
        #expect(C.phase(input(elapsed: 30, remaining: 2.3)) == .exercise)
        #expect(C.phase(input(elapsed: 30, remaining: 0.5)) == .outro)
        #expect(C.phase(input(elapsed: 30, remaining: 0)) == .outro)
        #expect(C.phase(input(elapsed: 0, remaining: nil)) == .intro)
        // outro wins in a break too short for both
        #expect(C.phase(input(elapsed: 1, remaining: 1.5)) == .outro)
    }

    @Test("intro plays the video from frame 1")
    func introStart() {
        let p = C.pose(input(elapsed: 0, remaining: 100))
        #expect(p == LookingForEyesTimeline.pose(at: 0))
        #expect(p.frame == 1)
        let mid = C.pose(input(elapsed: 3.8, remaining: 100))
        #expect(mid == LookingForEyesTimeline.pose(at: 3.8))
    }

    @Test("exercise holds the angry squint")
    func exerciseSquint() {
        let p = C.pose(input(elapsed: 12))
        let open = LookingForEyesTimeline.pose(at: 0)
        #expect(p.lid[4] > open.lid[4] + 100)        // lids pulled down
        #expect(p.spark == 0 && p.fireLevel == 0)
        #expect(p.lidOpenness == 1)
        #expect(!isClosed(p))
    }

    // MARK: gaze

    @Test("gaze moves the iris in its direction and stays clamped")
    func gazeDirections() {
        let c = C.pose(input(gaze: .center))
        let l = C.pose(input(direction: "left", gaze: .left))
        let r = C.pose(input(direction: "right", gaze: .right))
        let u = C.pose(input(direction: "up", gaze: .up))
        let d = C.pose(input(direction: "down", gaze: .down))
        #expect(l.pupilShift < c.pupilShift - 10)
        #expect(r.pupilShift > c.pupilShift + 10)
        #expect(u.pupilY < c.pupilY - 3)
        #expect(d.pupilY > c.pupilY + 3)
        #expect(l.pupilShift >= -60 && r.pupilShift <= 60)   // fitted iris stays inside the opening
        #expect(u.pupilY >= c.pupilY - 40 && d.pupilY <= c.pupilY + 40)
    }

    @Test("path gazes sweep, and ease to centre at the step end")
    func paths() {
        let hold = 6.0
        var xs = Set<Int>()
        for i in 0..<40 {
            let p = C.pose(input(direction: "circle_cw", phaseElapsed: 0.6 + Double(i) * 0.1, hold: hold))
            xs.insert(Int(p.pupilShift.rounded()))
        }
        #expect(xs.count > 10)
        let c = C.pose(input(gaze: .center))
        let end = C.pose(input(direction: "figure8", phaseElapsed: hold, hold: hold))
        #expect(abs(end.pupilShift - c.pupilShift) < 1)
        #expect(abs(end.pupilY - c.pupilY) < 1)
    }

    // MARK: lids

    @Test("blink snaps shut and reopens each second")
    func blink() {
        func o(_ t: Double) -> Double { C.pose(input(direction: "blink", phaseElapsed: t)).lidOpenness }
        #expect(abs(o(1.0) - 1) < 1e-9)
        #expect(o(1.12) < 0.01)
        #expect(o(1.5) > 0.99)
        #expect(isClosed(C.pose(input(direction: "blink", phaseElapsed: 1.12))))
    }

    @Test("closed step shuts the lids, easing from the previous openness")
    func closedStep() {
        let p = C.pose(input(direction: "closed", phaseElapsed: 2))
        #expect(p.lidOpenness == 0)
        #expect(isClosed(p))
        let start = C.pose(input(direction: "closed", phaseElapsed: 0, previous: 1))
        #expect(start.lidOpenness == 1)
    }

    // MARK: reduce motion

    @Test("reduce motion: no intro, no outro, no sway; closed and blink still honoured")
    func reduceMotion() {
        #expect(C.phase(input(elapsed: 0, reduce: true)) == .exercise)
        #expect(C.phase(input(elapsed: 30, remaining: 0.2, reduce: true)) == .exercise)
        let a = C.pose(input(elapsed: 1, reduce: true))
        let b = C.pose(input(elapsed: 2, remaining: 0.1, reduce: true))
        #expect(a == b)
        #expect(a.fireLevel == 0 && a.spark == 0)
        #expect(C.pose(input(direction: "closed", reduce: true)).lidOpenness == 0)
        #expect(C.pose(input(direction: "blink", phaseElapsed: 1.12, reduce: true)).lidOpenness == 1)
    }

    // MARK: outro

    @Test("outro: spark then fire, centred gaze, lids shut exactly at the end")
    func outro() {
        let start = C.pose(input(remaining: C.outroDuration))
        #expect(start.spark == 0 && start.fireLevel == 0)
        var sawSpark = false, sawFire = false
        var r = C.outroDuration
        while r > 0.5 {
            let p = C.pose(input(remaining: r, direction: "right", gaze: .right))
            sawSpark = sawSpark || p.spark > 0.5
            sawFire = sawFire || p.fireLevel > 0.9
            r -= 1.0 / 30
        }
        #expect(sawSpark && sawFire)
        let mid = C.pose(input(remaining: 1.2, direction: "right", gaze: .right))
        let video = LookingForEyesTimeline.pose(at: 31.0 / 30)       // the clip's own squint pupil
        #expect(abs(mid.pupilShift - video.pupilShift) < 0.5)
        let half = C.pose(input(remaining: 0.25))
        #expect(half.lidOpenness > 0 && half.lidOpenness < 1)
        let end = C.pose(input(remaining: 0))
        #expect(end.lidOpenness == 0)
        #expect(isClosed(end))
        #expect(end.fireLevel == 0)
    }

    // MARK: continuity

    private func maxStep(_ poses: [LookingForEyesPose]) -> Double {
        var worst = 0.0
        for (a, b) in zip(poses, poses.dropFirst()) {
            worst = max(worst, abs(a.lid[4] - b.lid[4]), abs(a.ringBottom - b.ringBottom),
                        abs(a.pupilShift - b.pupilShift), abs(a.pupilY - b.pupilY),
                        abs(a.axis - b.axis))
        }
        return worst
    }

    @Test("no jump at the intro to exercise blend")
    func introToExercise() {
        let ps = stride(from: C.introDuration - 1.0 / 120, through: 5.6, by: 1.0 / 120).map { C.pose(input(elapsed: $0)) }
        #expect(maxStep(ps) < 8)
    }

    @Test("no jump from exercise into the outro")
    func exerciseToOutro() {
        for dir in [("right", GazeDirection.right), ("left", .left), ("down", .down)] {
            let ps = stride(from: 2.6, through: 1.6, by: -1.0 / 120).map {
                C.pose(input(remaining: $0, direction: dir.0, gaze: dir.1))
            }
            #expect(maxStep(ps) < 3, "direction \(dir.0)")
        }
    }

    @Test("closing is monotonic over the last half second")
    func closingMonotonic() {
        let os = stride(from: 0.5, through: 0, by: -1.0 / 60).map { C.pose(input(remaining: $0)).lidOpenness }
        #expect(zip(os, os.dropFirst()).allSatisfy { $0 >= $1 })
    }
}
