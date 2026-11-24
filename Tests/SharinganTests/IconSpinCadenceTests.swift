import Testing
import Foundation
@testable import SharinganCore

@Suite("Icon spin cadence")
struct IconSpinCadenceTests {

    let cadence = IconSpinCadence.standard

    @Test("a burst turns exactly one tomoe step (120°)")
    func burstTurnsOneStep() {
        #expect(cadence.burstOffsets.last == 120)
    }

    @Test("every burst frame sits on the 5° grid the icon cache is keyed by")
    func framesOnGrid() {
        #expect(cadence.burstOffsets.allSatisfy { $0.truncatingRemainder(dividingBy: 5) == 0 })
    }

    @Test("offsets only move forward and never repeat a frame")
    func strictlyIncreasing() {
        let o = cadence.burstOffsets
        #expect(zip(o, o.dropFirst()).allSatisfy { $0 < $1 })
        #expect(o.first! > 0)
    }

    @Test("ease-in-out: the middle of the burst moves faster than its ends")
    func easesInAndOut() {
        let o = [0] + cadence.burstOffsets
        let steps = zip(o, o.dropFirst()).map { $1 - $0 }
        let mid = steps[steps.count / 2]
        #expect(mid > steps.first!)
        #expect(mid > steps.last!)
    }

    @Test("bursts are rare: animated frames stay under 20% of a 12 fps continuous spin")
    func cheapDutyCycle() {
        let cycle = cadence.restSeconds + Double(cadence.burstOffsets.count) * cadence.frameInterval
        let framesPerSecond = Double(cadence.burstOffsets.count) / cycle
        #expect(framesPerSecond < 12 * 0.2)
    }
}
