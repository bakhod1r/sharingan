import Testing
import Foundation
@testable import SharinganCore

@Suite("Iris slides all the way left / right")
struct SlideTravelTests {
    private static let styles: [BreakIrisStyle] = [.sharingan, .original]

    private func lfIn(_ g: GazeDirection, _ iris: BreakIrisStyle) -> LookingForBreakChoreography.Input {
        .init(elapsed: 30, remaining: 100, direction: "d", gaze: g, phaseElapsed: 2, holdSeconds: 4,
              previousOpenness: 1, iris: iris)
    }
    private func anIn(_ g: GazeDirection, _ iris: BreakIrisStyle) -> AngryBreakChoreography.Input {
        .init(elapsed: 30, remaining: 100, direction: "d", gaze: g, phaseElapsed: 2, holdSeconds: 4,
              previousOpenness: 1, iris: iris)
    }

    /// Farthest the circle could slide from (x, y) toward `s` (±1) and still fit, by brute force.
    private func maxSlide(_ o: BreakEyeOpening, x: Double, y: Double, r: Double, _ s: Double) -> Double {
        var d = 0.0
        while o.contains(x: x + s * (d + 0.25), y: y, radius: r) { d += 0.25 }
        return d
    }

    @Test("Looking-for: iris reaches the edge of the opening on left and right")
    func lookingFor() {
        for iris in Self.styles {
            let c = LookingForBreakChoreography.pose(lfIn(.center, iris))
            let o = c.eyeOpening(lidMargin: 2)
            for (g, s) in [(GazeDirection.left, -1.0), (.right, 1.0)] {
                let p = LookingForBreakChoreography.pose(lfIn(g, iris))
                let travel = abs(p.irisCenter.x - c.irisCenter.x)
                let most = maxSlide(o, x: c.irisCenter.x, y: c.irisCenter.y, r: c.irisRadius, s)
                print("LF \(iris) \(g.dx): travel \(travel) of max \(most)")
                #expect(travel >= 0.85 * most, "LF \(iris) \(g)")
                #expect(!o.contains(x: p.irisCenter.x + s * 5, y: p.irisCenter.y, radius: p.irisRadius), "LF edge \(iris) \(g)")
                #expect(SharinganTestHelpers.lfVisible(p))
            }
        }
    }

    private func opening(_ g: AngryEyeGeometry) -> BreakEyeOpening {
        BreakEyeOpening(cx: g.cx, cy: g.cy, rx: g.radius, ry: g.radius, lidMargin: 4) {
            g.lidY(atU: ($0 - g.cx) / g.radius)
        }
    }

    @Test("Angry: both irises reach the edge together")
    func angry() {
        for iris in Self.styles {
            let c = AngryBreakChoreography.pose(anIn(.center, iris))
            for (g, s) in [(GazeDirection.left, -1.0), (.right, 1.0)] {
                let p = AngryBreakChoreography.pose(anIn(g, iris))
                var travels: [Double] = []
                for (e, ce) in [(p.left, c.left), (p.right, c.right)] {
                    let travel = abs((e.pupilX - e.cx) - (ce.pupilX - ce.cx))
                    travels.append(travel)
                    let o = opening(e)
                    let most = maxSlide(opening(ce), x: ce.pupilX, y: ce.pupilY, r: ce.pupilRadius, s)
                    print("AN \(iris) \(g.dx): travel \(travel) of own max \(most)")
                    #expect(SharinganTestHelpers.anVisible(e))
                    #expect(travel > 20)
                    _ = o
                }
                // both eyes slide equally (the smaller common reach)
                #expect(abs(travels[0] - travels[1]) < 1.0, "AN sync \(iris) \(g)")
                // and at least one eye is at its edge
                let touching = [(p.left, c.left), (p.right, c.right)].contains { e, ce in
                    let o = opening(e)
                    return !o.contains(x: e.pupilX + s * 5, y: e.pupilY, radius: e.pupilRadius)
                }
                #expect(touching, "AN edge \(iris) \(g)")
            }
        }
    }

    @Test("MoveEyes mapping: full gaze goes much wider than before, centre stays, symmetric")
    func moveEyes() {
        // diamond-ish opening: half-height 0.4 at the middle falling linearly to 0 at the tips
        let h: (Double) -> Double = { 0.8 * (0.5 - abs($0 - 0.5)) }
        let r = 0.26
        let right = MoveEyeTravel.uScreen(dx: 1, irisUnitR: r, halfHeight: h)
        let left = MoveEyeTravel.uScreen(dx: -1, irisUnitR: r, halfHeight: h)
        #expect(MoveEyeTravel.uScreen(dx: 0, irisUnitR: r, halfHeight: h) == 0.5)
        #expect(abs((right - 0.5) + (left - 0.5)) < 1e-9)
        #expect(right - 0.5 > 0.22)                       // old travel was 0.20
        #expect(h(right) >= 0.8 * r - 1e-9)               // iris still mostly visible there
        #expect(h(right + 0.01) < 0.8 * r)                // ...and it is as far as that allows
        let half = MoveEyeTravel.uScreen(dx: 0.5, irisUnitR: r, halfHeight: h)
        #expect(abs((half - 0.5) - (right - 0.5) / 2) < 1e-9)
    }
}

enum SharinganTestHelpers {
    static func lfVisible(_ p: LookingForEyesPose) -> Bool { IrisVisibilityIntroOutroTests.lfVisible(p) }
    static func anVisible(_ e: AngryEyeGeometry) -> Bool { IrisVisibilityIntroOutroTests.anVisible(e) }
}
