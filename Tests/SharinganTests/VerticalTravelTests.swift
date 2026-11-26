import Testing
import Foundation
@testable import SharinganCore

/// Up / down gazes carry the iris to the edge of the visible opening, like left / right do,
/// and the iris keeps one size in every direction.
@Suite("Break face vertical travel")
struct VerticalTravelTests {
    static let styles: [BreakIrisStyle] = [.sharingan, .original]
    static let dirs: [(String, GazeDirection)] = [
        ("center", .center), ("up", .up), ("down", .down), ("left", .left), ("right", .right),
        ("up_left", .upLeft), ("up_right", .upRight), ("down_left", .downLeft), ("down_right", .downRight),
    ]
    static let tol = 3.0

    private func input(_ d: String, _ g: GazeDirection, _ iris: BreakIrisStyle) -> BreakFaceInput {
        .init(elapsed: 30, remaining: 100, direction: d, gaze: g, phaseElapsed: 3, holdSeconds: 4,
              previousOpenness: 1, reduceMotion: true, iris: iris)
    }

    // MARK: BreakEyeOpening

    @Test("verticalTravel on a half disk: up stops at the lid, down at the eyeball bottom")
    func verticalTravelGeometry() {
        let o = BreakEyeOpening(cx: 0, cy: 100, rx: 100, ry: 100, lidMargin: 2) { _ in 100 }
        let c = BreakEyeOpening.Circle(x: 0, y: 150, radius: 20)
        // up: top may reach lid + margin (y 102) -> centre y 122 -> travel 28
        #expect(abs(o.verticalTravel(from: c, toward: -1) - 28) < 0.1)
        // down: bottom may reach the eyeball bottom (y 200) -> centre y 180 -> travel 30
        #expect(abs(o.verticalTravel(from: c, toward: 1) - 30) < 0.1)
        #expect(o.verticalTravel(from: .init(x: 0, y: 101, radius: 20), toward: 1) == 0)  // does not fit
    }

    @Test("rise moves by a fraction of the travel and respects the cap")
    func riseFraction() {
        let o = BreakEyeOpening(cx: 0, cy: 100, rx: 100, ry: 100, lidMargin: 2) { _ in 100 }
        let c = BreakEyeOpening.Circle(x: 0, y: 150, radius: 20)
        #expect(abs(o.rise(c, look: -1).y - 122) < 0.01)
        #expect(abs(o.rise(c, look: 1).y - 180) < 0.1)
        #expect(abs(o.rise(c, look: -0.5).y - 136) < 0.01)
        #expect(o.rise(c, look: 0) == c)
        #expect(abs(o.rise(c, look: -1, cap: 10).y - 140) < 0.01)
        #expect(o.rise(c, look: 1).radius == 20 && o.rise(c, look: 1).x == 0)
    }

    // MARK: Angry

    private func anOpening(_ e: AngryEyeGeometry) -> BreakEyeOpening {
        BreakEyeOpening(cx: e.cx, cy: e.cy, rx: e.radius, ry: e.radius, lidMargin: 4) {
            e.lidY(atU: ($0 - e.cx) / e.radius)
        }
    }

    @Test("Angry: up reaches the lid edge, down the eyeball bottom, iris fully visible")
    func angryEdges() {
        for iris in Self.styles {
            for (name, g) in [("up", GazeDirection.up), ("down", .down)] {
                let p = AngryBreakChoreography.pose(input(name, g, iris))
                for e in [p.left, p.right] {
                    let o = anOpening(e)
                    #expect(o.contains(x: e.pupilX, y: e.pupilY, radius: e.pupilRadius), "\(iris) \(name) visible")
                    let extra = name == "up" ? (x: 0.0, y: -Self.tol) : (x: 0.0, y: Self.tol)
                    #expect(!o.contains(x: e.pupilX, y: e.pupilY + extra.y, radius: e.pupilRadius),
                            "\(iris) \(name) is not at the edge")
                }
            }
        }
    }

    @Test("Angry: both eyes move the same vertical distance, and far more than before")
    func angryTravelSize() {
        for iris in Self.styles {
            let c = AngryBreakChoreography.pose(input("center", .center, iris))
            // down is bounded by the eyeball bottom (the resting iris already sits low), up by the lifted lid
            for (name, g, sign, minR) in [("up", GazeDirection.up, -1.0, 1.4), ("down", .down, 1.0, 0.9)] {
                let p = AngryBreakChoreography.pose(input(name, g, iris))
                let dl = (p.left.pupilY - c.left.pupilY) * sign, dr = (p.right.pupilY - c.right.pupilY) * sign
                #expect(abs(dl - dr) < 0.5, "\(iris) \(name) eyes differ \(dl) vs \(dr)")
                #expect(dl >= minR * p.left.pupilRadius, "\(iris) \(name) travel \(dl) r=\(p.left.pupilRadius)")
            }
        }
    }

    @Test("Angry: iris radius identical for every direction and eye")
    func angryRadius() {
        for iris in Self.styles {
            let c = AngryBreakChoreography.pose(input("center", .center, iris))
            for (name, g) in Self.dirs {
                let p = AngryBreakChoreography.pose(input(name, g, iris))
                #expect(abs(p.left.pupilRadius - c.left.pupilRadius) < 0.01, "\(iris) \(name) L \(p.left.pupilRadius)")
                #expect(abs(p.right.pupilRadius - c.right.pupilRadius) < 0.01, "\(iris) \(name) R \(p.right.pupilRadius)")
                let o = anOpening(p.left)
                #expect(o.contains(x: p.left.pupilX, y: p.left.pupilY, radius: p.left.pupilRadius), "\(iris) \(name) visible")
            }
        }
    }

    // MARK: Looking-for

    @Test("Looking-for: up reaches the lid edge, down the eyeball bottom, iris fully visible")
    func lookingForEdges() {
        for iris in Self.styles {
            for (name, g, s) in [("up", GazeDirection.up, -1.0), ("down", .down, 1.0)] {
                let p = LookingForBreakChoreography.pose(input(name, g, iris))
                let o = p.eyeOpening(lidMargin: 2)
                let c = p.irisCenter
                #expect(o.contains(x: c.x, y: c.y, radius: p.irisRadius), "\(iris) \(name) visible")
                #expect(!o.contains(x: c.x, y: c.y + s * Self.tol, radius: p.irisRadius), "\(iris) \(name) not at the edge")
            }
        }
    }

    @Test("Looking-for: travel is large and the iris radius never changes")
    func lookingForTravelAndRadius() {
        for iris in Self.styles {
            let c = LookingForBreakChoreography.pose(input("center", .center, iris))
            for (name, g) in Self.dirs {
                let p = LookingForBreakChoreography.pose(input(name, g, iris))
                #expect(abs(p.irisRadius - c.irisRadius) < 0.01, "\(iris) \(name) r=\(p.irisRadius)")
                let o = p.eyeOpening(lidMargin: 2)
                #expect(o.contains(x: p.irisCenter.x, y: p.irisCenter.y, radius: p.irisRadius), "\(iris) \(name) visible")
            }
            let up = LookingForBreakChoreography.pose(input("up", .up, iris))
            let down = LookingForBreakChoreography.pose(input("down", .down, iris))
            #expect(c.irisCenter.y - up.irisCenter.y >= 1.0 * c.irisRadius, "\(iris) up \(c.irisCenter.y - up.irisCenter.y)")
            #expect(down.irisCenter.y - c.irisCenter.y >= 0.75 * c.irisRadius, "\(iris) down \(down.irisCenter.y - c.irisCenter.y)")
        }
    }
}
