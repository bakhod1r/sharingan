import Testing
import Foundation
@testable import SharinganCore

/// Real-work postures that must NOT trip the red alert: glancing down at the
/// keyboard, typing without looking at the screen, reading notes on the desk.
/// Head turned sideways (talking, phone off to the side) must still alert.
@Suite("Attention work postures")
struct AttentionWorkPostureTests {
    private let t0 = Date(timeIntervalSince1970: 2_000_000)

    private func sample(_ t: Double, yaw: Double = 0, pitch: Double = 0,
                        gaze: GazeDirection = .center, closed: Bool = false,
                        face: Bool = true, inputAgo: Double? = nil) -> AttentionSample {
        AttentionSample(faceDetected: face, yaw: yaw, pitch: pitch, gaze: gaze,
                        eyesClosed: closed, at: t0.addingTimeInterval(t),
                        lastInputAt: inputAgo.map { t0.addingTimeInterval(t - $0) })
    }

    /// 1 Hz like the real focus guard.
    private func run(_ m: inout AttentionMonitor, _ range: ClosedRange<Int>,
                     _ make: (Double) -> AttentionSample) -> Bool {
        var alerted = false
        for t in range where m.ingest(make(Double(t))).isAlerting { alerted = true }
        return alerted
    }

    private func monitor() -> AttentionMonitor {
        AttentionMonitor(policy: AttentionPolicy(grace: 2, smoothingWindow: 3))
    }

    @Test func typingWhileLookingAtKeyboardNeverAlerts() {
        var m = monitor()
        // Head well down, eyes down, eyelids half shut — but keys are being hit.
        let alerted = run(&m, 0...20) {
            sample($0, pitch: 45, gaze: GazeDirection(dx: 0, dy: 1), closed: true, inputAgo: 0.5)
        }
        #expect(!alerted)
    }

    @Test func typingWithFaceLostNeverAlerts() {
        var m = monitor()
        // Steep look down: Vision loses the face entirely while typing.
        #expect(!run(&m, 0...20) { sample($0, face: false, inputAgo: 1) })
    }

    @Test func keyboardGlanceWithoutTypingIsTolerated() {
        var m = monitor()
        // Hunting for a key: moderate head tilt + eyes down, no input yet.
        let alerted = run(&m, 0...6) {
            sample($0, pitch: 28, gaze: GazeDirection(dx: 0.1, dy: 0.95))
        }
        #expect(!alerted)
    }

    @Test func pitchToleranceWorksInEitherSign() {
        // Vision's pitch sign convention isn't relied on.
        var a = monitor(), b = monitor()
        #expect(!run(&a, 0...6) { sample($0, pitch: 28) })
        #expect(!run(&b, 0...6) { sample($0, pitch: -28) })
    }

    @Test func headTurnedSidewaysStillAlerts() {
        var m = monitor()
        #expect(run(&m, 0...6) { sample($0, yaw: 45) })
    }

    @Test func lookingUpAtTheCeilingStillAlertsWhenExtreme() {
        var m = monitor()
        #expect(run(&m, 0...6) { sample($0, pitch: 60) })
    }

    @Test func eyesSidewaysStillAlerts() {
        var m = monitor()
        #expect(run(&m, 0...6) { sample($0, gaze: GazeDirection(dx: 0.95, dy: 0)) })
    }

    @Test func staleInputDoesNotSuppress() {
        var m = monitor()
        // Last key press long ago; now head turned away.
        #expect(run(&m, 0...6) { sample($0, yaw: 45, inputAgo: 30) })
    }

    @Test func typingClearsAnActiveAlert() {
        var m = monitor()
        #expect(run(&m, 0...5) { sample($0, yaw: 45) })
        // Back at work: typing again (even before the head pose settles).
        _ = m.ingest(sample(6, yaw: 45, inputAgo: 0.2))
        #expect(m.ingest(sample(7, yaw: 45, inputAgo: 0.2)) == .attentive)
    }

    @Test func calibratedEnvelopeStillAllowsKeyboardGlance() {
        let calib = AttentionCalibration(yawMin: -10, yawMax: 10, pitchMin: -6, pitchMax: 6,
                                         gazeXMin: -0.4, gazeXMax: 0.4,
                                         gazeYMin: -0.3, gazeYMax: 0.3)
        var m = AttentionMonitor(policy: AttentionPolicy(grace: 2, calibration: calib,
                                                         smoothingWindow: 3))
        #expect(!run(&m, 0...6) { sample($0, pitch: 25, gaze: GazeDirection(dx: 0, dy: 0.9)) })
        var side = AttentionMonitor(policy: AttentionPolicy(grace: 2, calibration: calib,
                                                            smoothingWindow: 3))
        #expect(run(&side, 0...6) { sample($0, yaw: 30) })
    }
}
