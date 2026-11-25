import Testing
import Foundation
@testable import SharinganCore

@Suite("Looking-for-eyes timeline")
struct LookingForEyesTimelineTests {

    private func pose(frame: Double) -> LookingForEyesPose {
        LookingForEyesTimeline.pose(at: (frame - 1) / LookingForEyesTimeline.fps)
    }

    @Test("clip is 152 frames at 30 fps")
    func duration() {
        #expect(LookingForEyesTimeline.frameCount == 152)
        #expect(LookingForEyesTimeline.fps == 30)
        #expect(abs(LookingForEyesTimeline.duration - 152.0 / 30.0) < 1e-9)
    }

    @Test("time wraps modulo duration")
    func wraps() {
        let d = LookingForEyesTimeline.duration
        #expect(LookingForEyesTimeline.pose(at: 0.5) == LookingForEyesTimeline.pose(at: 0.5 + d))
        #expect(LookingForEyesTimeline.pose(at: 0.5) == LookingForEyesTimeline.pose(at: 0.5 - d))
    }

    @Test("shape arrays have the expected sizes")
    func shapes() {
        let p = pose(frame: 1)
        #expect(p.lid.count == 9)
        #expect(p.brow.count == 27)
        #expect(p.crease.count == 27)
        #expect(p.mouth.count == 13)
    }

    @Test("frame 1 is the wide-open curious face")
    func openFace() {
        let p = pose(frame: 1)
        #expect(abs(p.ringBottom - 453) <= 1)
        #expect(abs(p.axis - 539) <= 2)
        #expect(p.highlightAlpha == 1)
        #expect(p.fireLevel == 0)
        #expect(p.spark == 0)
    }

    @Test("frame 40 is the angry squint, eyeball dropped behind the lid")
    func squint() {
        let p = pose(frame: 40)
        #expect(abs(p.ringBottom - 509) <= 2)
        #expect(p.lid[8] > p.lid[2])
        #expect(p.highlightAlpha == 1)
    }

    @Test("the face sways left then right while scanning")
    func scan() {
        #expect(pose(frame: 53).axis < pose(frame: 40).axis - 40)
        #expect(pose(frame: 73).axis > pose(frame: 40).axis + 30)
    }

    @Test("blue sparks run 87-111, highlight fades out by frame 93 and returns at 135")
    func sparks() {
        #expect(pose(frame: 90).spark > 0.5)
        #expect(pose(frame: 90).highlightAlpha < 1)
        #expect(pose(frame: 100).highlightAlpha == 0)
        #expect(pose(frame: 136).highlightAlpha == 1)
        #expect(pose(frame: 60).spark == 0)
    }

    @Test("fire peaks near frame 124 and is gone by 140")
    func fire() {
        #expect(pose(frame: 124).fireLevel > 0.9)
        #expect(pose(frame: 118).fireLevel > 0.3)
        #expect(pose(frame: 131).fireTop < pose(frame: 118).fireTop)
        #expect(pose(frame: 140).fireLevel == 0)
        #expect(pose(frame: 100).fireLevel == 0)
    }

    @Test("frown face after frame 101: mouth lower and wider than the smirk")
    func frown() {
        let smirk = pose(frame: 40), frown = pose(frame: 110)
        #expect(frown.mouth[1] > smirk.mouth[1])
        #expect(frown.ringBottom > smirk.ringBottom)
    }

    @Test("no frame-to-frame jump larger than 25 px, including the loop seam")
    func continuity() {
        for f in 1...152 {
            let a = pose(frame: Double(f)), b = pose(frame: Double(f % 152 + 1))
            #expect(abs(a.ringBottom - b.ringBottom) < 25, "ringBottom jump at \(f)")
            #expect(abs(a.axis - b.axis) < 30, "axis jump at \(f)")
        }
    }

    @Test("end of clip lands back on the open face")
    func loopSeam() {
        let end = LookingForEyesTimeline.pose(at: LookingForEyesTimeline.duration - 1e-6)
        #expect(abs(end.ringBottom - pose(frame: 1).ringBottom) < 5)
    }
}
