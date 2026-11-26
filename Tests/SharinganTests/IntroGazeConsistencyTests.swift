import Testing
import Foundation
@testable import SharinganCore

/// The face's eyes must look where the current step says, also while the intro clip plays
/// (camera mode shows "Look right" from the first second; the clip used to scan on its own
/// for 5 s (Looking-for) / 7.5 s (Angry), leaving the iris centred or wandering).
/// The intro clip's lids, brows, fire and brightness stay as recorded; only the iris follows the step gaze.
/// These copy the clip's iris onto a choreographed pose so the rest can be compared exactly.
extension LookingForEyesPose {
    func withIris(of o: LookingForEyesPose) -> LookingForEyesPose {
        var r = self
        r.pupilShift = o.pupilShift; r.pupilY = o.pupilY; r.irisRadius = o.irisRadius
        return r
    }
}
extension AngryEyesPose {
    func withPupils(of o: AngryEyesPose) -> AngryEyesPose {
        var r = self
        r.left.pupilX = o.left.pupilX; r.left.pupilY = o.left.pupilY
        r.right.pupilX = o.right.pupilX; r.right.pupilY = o.right.pupilY
        r.left.pupilRadius = o.left.pupilRadius; r.right.pupilRadius = o.right.pupilRadius
        return r
    }
}

@Suite struct IntroGazeConsistency {
    private func input(_ t: Double, _ iris: BreakIrisStyle, _ dir: String, _ gaze: GazeDirection) -> BreakFaceInput {
        BreakFaceInput(elapsed: t, remaining: 100, direction: dir, gaze: gaze,
                       phaseElapsed: 3, holdSeconds: 4, previousOpenness: 1, iris: iris)
    }
    private let looks: [(String, GazeDirection, Double)] = [("right", .right, 1), ("left", .left, -1)]

    @Test(arguments: [BreakIrisStyle.sharingan, .original])
    func lookingForIrisFollowsStepDuringIntro(iris: BreakIrisStyle) {
        // pupilShift is relative to the (swaying) face, so it compares across clip times.
        let centre = LookingForBreakChoreography.pose(input(30, iris, "center", .center)).pupilShift
        for (d, g, sign) in looks {
            for t in stride(from: LookingForBreakChoreography.introGazeRamp, to: LookingForBreakChoreography.introDuration, by: 0.1) {
                let x = LookingForBreakChoreography.pose(input(t, iris, d, g)).pupilShift
                #expect((x - centre) * sign > 15, "LF \(iris) \(d) t=\(t) shift=\(x) centre=\(centre)")
            }
        }
    }

    @Test(arguments: [BreakIrisStyle.sharingan, .original])
    func angryPupilsFollowStepDuringIntro(iris: BreakIrisStyle) {
        for (d, g, sign) in looks {
            let end = AngryBreakChoreography.introGazeStart + AngryBreakChoreography.introGazeRamp
            for t in stride(from: end, to: AngryBreakChoreography.introDuration, by: 0.1) {
                let p = AngryBreakChoreography.pose(input(t, iris, d, g))
                #expect(p.left.pupilOffsetX * sign > 15 && p.right.pupilOffsetX * sign > 15,
                        "Angry \(iris) \(d) t=\(t) L=\(p.left.pupilOffsetX) R=\(p.right.pupilOffsetX)")
            }
        }
    }

    @Test(arguments: [BreakIrisStyle.sharingan, .original])
    func irisDoesNotJumpAtIntroEnd(iris: BreakIrisStyle) {
        let lf = LookingForBreakChoreography.introDuration, an = AngryBreakChoreography.introDuration
        let a = LookingForBreakChoreography.pose(input(lf - 1e-4, iris, "right", .right)).irisCenter
        let b = LookingForBreakChoreography.pose(input(lf + 1e-4, iris, "right", .right)).irisCenter
        #expect(abs(a.x - b.x) < 1 && abs(a.y - b.y) < 1)
        let c = AngryBreakChoreography.pose(input(an - 1e-4, iris, "right", .right)).left.pupilX
        let d = AngryBreakChoreography.pose(input(an + 1e-4, iris, "right", .right)).left.pupilX
        #expect(abs(c - d) < 1)
    }
}
