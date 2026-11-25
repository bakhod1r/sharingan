import Testing
import Foundation
@testable import SharinganCore

@Suite("Angry-eyes timeline")
struct AngryEyesTimelineTests {
    typealias T = AngryEyesTimeline

    @Test("clip is 540 frames at 60 fps, 9 seconds")
    func duration() {
        #expect(T.fps == 60)
        #expect(T.frameCount == 540)
        #expect(abs(T.duration - 9.0) < 1e-9)
    }

    @Test("starts and ends dark")
    func darkEnds() {
        let a = T.pose(at: 0)
        #expect(a.left.brightness < 0.05 && a.right.brightness < 0.05)
        for t in [8.8, 8.95, 9.0, 12.0] {
            let p = T.pose(at: t)
            #expect(p.left.brightness < 0.05 && p.right.brightness < 0.05, "t=\(t)")
            #expect(p.isDark)
        }
        #expect(!T.pose(at: 3).isDark)
    }

    @Test("fully visible through the look-around")
    func visible() {
        for t in stride(from: 1.0, through: 7.3, by: 0.1) {
            let p = T.pose(at: t)
            #expect(p.left.brightness > 0.9 && p.right.brightness > 0.9, "t=\(t)")
        }
    }

    @Test("eyeballs are circles of about 175-190 px, mirrored about the 540 axis")
    func geometry() {
        for t in stride(from: 1.0, through: 7.3, by: 0.25) {
            let p = T.pose(at: t)
            #expect((165...195).contains(p.left.radius), "t=\(t)")
            #expect((165...195).contains(p.right.radius), "t=\(t)")
            #expect(abs((p.left.cx + p.right.cx) / 2 - 540) < 25, "t=\(t)")
            #expect(abs(p.left.pupilRadius / p.left.radius - 0.5) < 0.04, "t=\(t)")
        }
    }

    @Test("the angry lid slants down towards the nose in both eyes")
    func lidSlant() {
        let p = T.pose(at: 3.0)
        #expect(p.left.lidSlope > 40)      // lid gets lower to the right (inner corner)
        #expect(p.right.lidSlope < -40)    // mirror image
    }

    @Test("pupils scan left, then right (measured: t 2.5 s left, 4.8 s right)")
    func scan() {
        let center = T.pose(at: 1.0)
        let left = T.pose(at: 2.5)
        let right = T.pose(at: 4.8)
        #expect(left.left.pupilOffsetX < center.left.pupilOffsetX - 50)
        #expect(left.right.pupilOffsetX < center.right.pupilOffsetX - 50)
        #expect(right.left.pupilOffsetX > center.left.pupilOffsetX + 30)
        #expect(right.right.pupilOffsetX > center.right.pupilOffsetX + 30)
    }

    @Test("frame 61 (t = 1 s) matches the measurement")
    func frame61() {
        let p = T.pose(at: 60.0 / 60.0)
        #expect(abs(p.left.lidY0 - 125) < 3)
        #expect(abs(p.left.radius - 178) < 3)
        #expect(abs(p.left.cx - 313) < 4)
        #expect(abs(p.left.pupilRadius - 89) < 3)
    }

    @Test("pupil sits at a natural centre at the intro cut and the outro start")
    func centreMoments() {
        for t in [AngryBreakChoreography.introDuration, AngryBreakChoreography.outroVideoStart] {
            let p = T.pose(at: t)
            #expect(abs(p.left.pupilOffsetX) < 15, "t=\(t)")
            #expect(abs(p.right.pupilOffsetX) < 15, "t=\(t)")
        }
    }

    @Test("eyes appear from the lower crescent and close with a rising lower lid")
    func appearAndClose() {
        let early = T.pose(at: 0.5)
        #expect(early.left.lidY0 > 250)                  // upper lid still covers most of the ball
        let late = T.pose(at: 8.3)
        #expect(late.left.lowerY0 < late.left.cy + late.left.radius - 40)  // lower lid cuts the bottom
    }

    @Test("time is clamped, not wrapped")
    func clamped() {
        #expect(T.pose(at: -3) == T.pose(at: 0))
        #expect(T.pose(at: 99) == T.pose(at: T.duration))
    }

    @Test("no jump between consecutive 1/60 s samples")
    func continuity() {
        var worst = 0.0, worstBright = 0.0
        var prev = T.pose(at: 0)
        var f = 1
        while f <= 540 {
            let p = T.pose(at: Double(f) / 60)
            for (a, b) in [(prev.left, p.left), (prev.right, p.right)] {
                worst = max(worst, abs(a.cx - b.cx), abs(a.cy - b.cy), abs(a.radius - b.radius),
                            abs(a.pupilX - b.pupilX), abs(a.pupilY - b.pupilY), abs(a.lidY0 - b.lidY0))
                worstBright = max(worstBright, abs(a.brightness - b.brightness))
            }
            prev = p
            f += 1
        }
        #expect(worst < 14, "worst geometry step \(worst)")
        #expect(worstBright < 0.2, "worst brightness step \(worstBright)")
    }
}
