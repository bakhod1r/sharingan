import Testing
import Foundation
@testable import SharinganCore

@Suite("Break gaze transition: glide to center, then out")
struct BreakGazeTransitionTests {
    private func off(_ dir: String, from: GazeDirection, to: GazeDirection, tp: Double,
                     hold: Double = 4, reduce: Bool = false) -> (x: Double, y: Double) {
        BreakGazePath.gazeOffset(BreakFaceInput(
            elapsed: 30 + tp, remaining: 100, direction: dir, gaze: to, phaseElapsed: tp,
            holdSeconds: hold, reduceMotion: reduce, previousGaze: from))
    }
    private func close(_ a: (x: Double, y: Double), _ x: Double, _ y: Double, _ tol: Double = 0.02) -> Bool {
        abs(a.x - x) < tol && abs(a.y - y) < tol
    }

    @Test("up to down: starts up, center at 0.4 s, down by 0.9 s")
    func upDown() {
        #expect(close(off("down", from: .up, to: .down, tp: 0), 0, -1))
        #expect(close(off("down", from: .up, to: .down, tp: 0.4), 0, 0))
        #expect(close(off("down", from: .up, to: .down, tp: 0.9), 0, 1))
    }

    @Test("no frame jumps and the path crosses center")
    func continuous() {
        var prev = off("down", from: .up, to: .down, tp: 0)
        var minMag = 9.0
        var t = 1.0 / 30
        while t <= 1.2 {
            let o = off("down", from: .up, to: .down, tp: t)
            #expect(abs(o.x - prev.x) < 0.12 && abs(o.y - prev.y) < 0.12, "t=\(t)")
            minMag = min(minMag, (o.x * o.x + o.y * o.y).squareRoot())
            prev = o; t += 1.0 / 30
        }
        #expect(minMag < 0.02)
    }

    @Test("center to right: no return leg")
    func centerRight() {
        #expect(close(off("right", from: .center, to: .right, tp: 0), 0, 0))
        #expect(close(off("right", from: .center, to: .right, tp: 0.5), 1, 0))
    }

    @Test("same gaze holds")
    func same() {
        for tp in [0.0, 0.2, 0.6, 2] {
            #expect(close(off("right", from: .right, to: .right, tp: tp), 1, 0, 0.03))
        }
    }

    @Test("path after up: up, center at 0.4 s, then circles")
    func pathAfterUp() {
        #expect(close(off("circle_cw", from: .up, to: .center, tp: 0), 0, -1))
        #expect(close(off("circle_cw", from: .up, to: .center, tp: 0.4), 0, 0))
        let later = off("circle_cw", from: .up, to: .center, tp: 2.0)
        #expect((later.x * later.x + later.y * later.y).squareRoot() > 0.5)
    }

    @Test("closed target glides back to center")
    func toCenter() {
        #expect(close(off("closed", from: .left, to: .center, tp: 0), -1, 0))
        #expect(close(off("closed", from: .left, to: .center, tp: 0.4), 0, 0))
    }

    @Test("reduce motion snaps")
    func reduce() {
        #expect(close(off("down", from: .up, to: .down, tp: 0, reduce: true), 0, 1, 1e-9))
    }

    @Test("Looking-for and Angry irises glide: higher at start than at 0.9 s, near center pose at 0.4 s")
    func choreography() {
        for iris in [BreakIrisStyle.sharingan, .original] {
            func lf(_ tp: Double) -> LookingForEyesPose {
                LookingForBreakChoreography.pose(.init(
                    elapsed: 30 + tp, remaining: 100, direction: "down", gaze: .down, phaseElapsed: tp,
                    holdSeconds: 4, previousOpenness: 1, iris: iris, previousGaze: .up))
            }
            func an(_ tp: Double) -> AngryEyesPose {
                AngryBreakChoreography.pose(.init(
                    elapsed: 30 + tp, remaining: 100, direction: "down", gaze: .down, phaseElapsed: tp,
                    holdSeconds: 4, previousOpenness: 1, iris: iris, previousGaze: .up))
            }
            let lfCenter = LookingForBreakChoreography.pose(.init(
                elapsed: 30, remaining: 100, direction: "center", gaze: .center, phaseElapsed: 5,
                holdSeconds: 4, previousOpenness: 1, reduceMotion: true, iris: iris))
            let anCenter = AngryBreakChoreography.pose(.init(
                elapsed: 30, remaining: 100, direction: "center", gaze: .center, phaseElapsed: 5,
                holdSeconds: 4, previousOpenness: 1, reduceMotion: true, iris: iris))
            #expect(lf(0).irisCenter.y < lf(0.9).irisCenter.y - 20, "\(iris)")
            #expect(abs(lf(0.4).irisCenter.y - lfCenter.irisCenter.y) < 6, "\(iris)")
            for (n, get) in [("L", { (p: AngryEyesPose) in p.left }), ("R", { $0.right })] {
                #expect(get(an(0)).pupilY < get(an(0.9)).pupilY - 20, "\(iris) \(n)")
                #expect(abs(get(an(0.4)).pupilY - get(anCenter).pupilY) < 6, "\(iris) \(n)")
            }
        }
    }
}
