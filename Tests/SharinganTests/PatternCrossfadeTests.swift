import XCTest
@testable import SharinganCore

final class PatternCrossfadeTests: XCTestCase {
    private func started(_ old: SharinganStyle = .classic, _ new: SharinganStyle = .mangekyou,
                         speed: PatternTransitionSpeed = .normal) -> StyleCrossfade {
        var x = StyleCrossfade()
        x.change(oldLeft: old, oldRight: old, newLeft: new, newRight: new,
                 at: 100, transition: speed, reduceMotion: false)
        return x
    }

    func testDurationAtLeastEightTenths() {
        for s in PatternTransitionSpeed.allCases where s != .off {
            XCTAssertGreaterThanOrEqual(StyleCrossfade.duration(for: s), 0.8)
            XCTAssertGreaterThanOrEqual(StyleCrossfade.duration(for: s), s.closeSeconds + s.openSeconds)
        }
        XCTAssertEqual(StyleCrossfade.duration(for: .off), 0)
    }

    func testBlendZeroAtChangeOneAtEnd() {
        let x = started()
        let d = StyleCrossfade.duration(for: .normal)
        XCTAssertEqual(x.blend(at: 100, transition: .normal), 0, accuracy: 1e-9)
        XCTAssertEqual(x.blend(at: 100 + d, transition: .normal), 1, accuracy: 1e-9)
        XCTAssertEqual(x.blend(at: 200, transition: .normal), 1, accuracy: 1e-9)
        XCTAssertEqual(x.previousLeft, .classic)
    }

    func testMonotonicSmallStepsAndNoBlankFrame() {
        for speed in [PatternTransitionSpeed.fast, .normal, .slow] {
            let x = started(speed: speed)
            let d = StyleCrossfade.duration(for: speed)
            var last = 0.0
            var t = 100.0
            while t <= 100 + d + 0.1 {
                let b = x.blend(at: t, transition: speed)
                XCTAssertGreaterThanOrEqual(b, last - 1e-12)
                XCTAssertLessThanOrEqual(b - last, 0.1)
                let o = StyleCrossfade.opacities(blend: b)
                XCTAssertGreaterThanOrEqual(o.previous + o.current, 0.9)
                last = b
                t += 1.0 / 30
            }
        }
    }

    func testOffAndReduceMotionAreInstant() {
        var x = StyleCrossfade()
        x.change(oldLeft: .classic, oldRight: .classic, newLeft: .mangekyou, newRight: .mangekyou,
                 at: 5, transition: .off, reduceMotion: false)
        XCTAssertNil(x.previousLeft)
        XCTAssertEqual(x.blend(at: 5, transition: .off), 1)
        x.change(oldLeft: .classic, oldRight: .classic, newLeft: .mangekyou, newRight: .mangekyou,
                 at: 5, transition: .normal, reduceMotion: true)
        XCTAssertNil(x.previousLeft)
        XCTAssertEqual(x.blend(at: 5, transition: .normal), 1)
    }

    func testRetriggerPicksDominantStyle() {
        var x = started(.classic, .mangekyou)
        let d = StyleCrossfade.duration(for: .normal)
        // late: new (mangekyou) dominant -> becomes previous
        x.change(oldLeft: .mangekyou, oldRight: .mangekyou, newLeft: .itachi, newRight: .itachi,
                 at: 100 + d * 0.8, transition: .normal, reduceMotion: false)
        XCTAssertEqual(x.previousLeft, .mangekyou)
        XCTAssertEqual(x.blend(at: 100 + d * 0.8, transition: .normal), 0, accuracy: 1e-9)

        // early: previous (classic) still dominant -> stays previous
        var y = started(.classic, .mangekyou)
        y.change(oldLeft: .mangekyou, oldRight: .mangekyou, newLeft: .itachi, newRight: .itachi,
                 at: 100 + d * 0.2, transition: .normal, reduceMotion: false)
        XCTAssertEqual(y.previousLeft, .classic)
    }

    func testEyesIndependent() {
        var x = StyleCrossfade()
        x.change(oldLeft: .classic, oldRight: .itachi, newLeft: .mangekyou, newRight: .itachi,
                 at: 1, transition: .normal, reduceMotion: false)
        XCTAssertEqual(x.previousLeft, .classic)
        XCTAssertNil(x.previousRight)
    }

    func testSameStyleNoCrossfade() {
        var x = StyleCrossfade()
        x.change(oldLeft: .classic, oldRight: .classic, newLeft: .classic, newRight: .classic,
                 at: 1, transition: .normal, reduceMotion: false)
        XCTAssertNil(x.previousLeft)
        XCTAssertEqual(x.blend(at: 1, transition: .normal), 1)
    }
}

final class SmoothMotionTests: XCTestCase {
    func testSpinContinuousAcrossRestartMidBurst() {
        var s = ActivationSpin(start: 0)
        let now = 0.7   // mid-burst
        let before = s.angle(at: now)
        s.restart(at: now, now: now)
        XCTAssertEqual(s.angle(at: now), before, accuracy: 1e-9)
        // and stays continuous (no jump) afterwards at 60 fps
        var last = s.angle(at: now)
        var t = now
        while t < now + 2 {
            t += 1.0 / 60
            let a = s.angle(at: t)
            XCTAssertGreaterThanOrEqual(a, last - 1e-9)
            XCTAssertLessThan(a - last, 360 * 3 * 1.875 / 1.6 / 60 + 1e-6)
            last = a
        }
    }

    func testSpinAccumulatesAcrossManyRestarts() {
        var s = ActivationSpin(start: 0)
        s.restart(at: 5, now: 5)           // full burst done: 1080
        XCTAssertEqual(s.angle(at: 5), 1080, accuracy: 1e-9)
        s.restart(at: 10, now: 10)
        XCTAssertEqual(s.angle(at: 10), 2160, accuracy: 1e-9)
    }

    func testResetClearsBase() {
        var s = ActivationSpin(start: 0)
        s.restart(at: 5, now: 5)
        s.reset(start: 20)
        XCTAssertEqual(s.angle(at: 19), 0)
    }

    func testCrossfadeIsSmootherstep() {
        XCTAssertEqual(StyleCrossfade.smooth(0.5), 0.5, accuracy: 1e-12)
        XCTAssertEqual(StyleCrossfade.smooth(0.1), 0.00856, accuracy: 1e-5)
    }

    func testGazeGlideFramesAt60fpsAreSmall() {
        func off(_ tp: Double) -> Double {
            var i = BreakFaceInput(elapsed: 30 + tp, remaining: 100, direction: "center",
                                   gaze: .center, phaseElapsed: tp, holdSeconds: 10,
                                   previousGaze: .up)
            i.reduceMotion = false
            let o = BreakGazePath.gazeOffset(i, sway: false)
            return (o.x * o.x + o.y * o.y).squareRoot()
        }
        var last = off(0)
        var first = true
        var t = 1.0 / 60
        while t < 0.45 {
            let v = off(t)
            XCTAssertLessThan(abs(v - last), 0.06)
            if first { XCTAssertLessThan(abs(last - v), 0.02, "soft start"); first = false }
            last = v; t += 1.0 / 60
        }
    }
}
