import Testing
import Foundation
@testable import SharinganCore

@Suite("Attention monitor")
struct AttentionMonitorTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func face(_ t: Double, yaw: Double = 0, pitch: Double = 0,
                      gaze: GazeDirection = .center, closed: Bool = false) -> AttentionSample {
        AttentionSample(faceDetected: true, yaw: yaw, pitch: pitch, gaze: gaze,
                        eyesClosed: closed, at: t0.addingTimeInterval(t))
    }
    private func noFace(_ t: Double) -> AttentionSample {
        AttentionSample(faceDetected: false, at: t0.addingTimeInterval(t))
    }
    /// Feeds `frames` at 10 fps from `start`, returns the last state.
    private func feed(_ m: inout AttentionMonitor, from start: Double, to end: Double,
                      _ make: (Double) -> AttentionSample) -> AttentionState {
        var s = m.state
        var t = start
        while t <= end + 1e-9 { s = m.ingest(make(t)); t += 0.1 }
        return s
    }

    /// Focus guard samples once per second: alert must still fire close to
    /// `grace` (not grace + a 5-frame median lag) and clear within ~1 sample.
    @Test func oneHertzCadenceAlertsNearGraceAndRecoversFast() {
        var m = AttentionMonitor(policy: AttentionPolicy(grace: 2, smoothingWindow: 3))
        for t in 0...3 { m.ingest(face(Double(t))) }
        // Looks away from t=4. Median of 3 flips on the 2nd off sample (t=5),
        // but the off streak is dated from its first raw off sample (t=4).
        #expect(!m.ingest(face(4, yaw: 40)).isAlerting)
        #expect(!m.ingest(face(5, yaw: 40)).isAlerting)
        #expect(m.ingest(face(6, yaw: 40)).isAlerting)
        // Looks back: cleared by the second on-screen sample (recovery 0.5 s).
        _ = m.ingest(face(7))
        _ = m.ingest(face(8))
        #expect(m.ingest(face(9)) == .attentive)
    }

    @Test func oneHertzSingleOutlierIgnored() {
        var m = AttentionMonitor(policy: AttentionPolicy(grace: 2, smoothingWindow: 3))
        for t in 0...3 { m.ingest(face(Double(t))) }
        #expect(m.ingest(face(4, yaw: 50)) == .attentive)
        #expect(m.ingest(face(5)) == .attentive)
    }

    @Test func baselineIsAttentive() {
        var m = AttentionMonitor()
        let s = feed(&m, from: 0, to: 3) { face($0) }
        #expect(s == .attentive)
    }

    @Test func shortGlanceDriftsThenRecovers() {
        var m = AttentionMonitor()
        _ = feed(&m, from: 0, to: 1) { face($0) }
        let s = feed(&m, from: 1.1, to: 2.0) { face($0, yaw: 40) }
        if case .drifting = s {} else { Issue.record("expected drifting, got \(s)") }
        #expect(!s.isAlerting)
        #expect(feed(&m, from: 2.1, to: 3.0) { face($0) } == .attentive)
    }

    @Test func longLookAwayAlerts() {
        var m = AttentionMonitor()
        _ = feed(&m, from: 0, to: 1) { face($0) }
        let s = feed(&m, from: 1.1, to: 4.0) { face($0, yaw: 40) }
        #expect(s.isAlerting)
        if case .away = s {} else { Issue.record("expected away, got \(s)") }
    }

    @Test func recoveryNeedsContinuousOnScreen() {
        var m = AttentionMonitor()
        _ = feed(&m, from: 0, to: 4) { face($0, yaw: 40) }
        #expect(m.state.isAlerting)
        // A short on-screen blip (< recovery) does not clear the alert.
        let blip = feed(&m, from: 4.1, to: 4.3) { face($0) }
        #expect(blip.isAlerting)
        // Sustained on-screen clears it.
        #expect(feed(&m, from: 4.4, to: 6.0) { face($0) } == .attentive)
    }

    @Test func noFaceHasLongerGrace() {
        var m = AttentionMonitor()
        _ = feed(&m, from: 0, to: 1) { face($0) }
        // 4 s without a face: still not alerting (grace 5 s).
        #expect(!feed(&m, from: 1.1, to: 5.0) { noFace($0) }.isAlerting)
        let s = feed(&m, from: 5.1, to: 7.0) { noFace($0) }
        if case .noFace = s {} else { Issue.record("expected noFace, got \(s)") }
        #expect(s.isAlerting)
    }

    @Test func blinkIgnoresGaze() {
        var m = AttentionMonitor()
        _ = feed(&m, from: 0, to: 1) { face($0) }
        // Eyes closed with a wild gaze offset for 4 s: head is fine → attentive.
        let s = feed(&m, from: 1.1, to: 5.0) { face($0, gaze: .upRight, closed: true) }
        #expect(s == .attentive)
    }

    @Test func singleOutlierFrameIsFiltered() {
        var m = AttentionMonitor()
        _ = feed(&m, from: 0, to: 1) { face($0) }
        let s = m.ingest(face(1.1, yaw: 80))
        #expect(s == .attentive)
    }

    @Test func gazeAwayAlertsWithoutHeadTurn() {
        var m = AttentionMonitor()
        let s = feed(&m, from: 0, to: 4) { face($0, gaze: GazeDirection(dx: 0.95, dy: 0)) }
        #expect(s.isAlerting)
    }

    @Test func calibrationWidensEnvelope() {
        let samples = (0..<10).map { i in face(Double(i) * 0.1, yaw: i % 2 == 0 ? -30 : 30) }
        let cal = AttentionCalibration.from(samples: samples)
        #expect(cal != nil)
        let plain = AttentionPolicy(sensitivity: .medium)
        let calibrated = AttentionPolicy(sensitivity: .medium, calibration: cal)
        let probe = face(0, yaw: 33)
        #expect(!plain.isOnScreen(probe))
        #expect(calibrated.isOnScreen(probe))
        #expect(!calibrated.isOnScreen(face(0, yaw: 45)))
    }

    @Test func calibrationNeedsEnoughSamples() {
        #expect(AttentionCalibration.from(samples: [face(0), face(0.1)]) == nil)
        #expect(AttentionCalibration.from(samples: (0..<10).map { _ in noFace(0) }) == nil)
    }

    @Test func sensitivityPresets() {
        let s = face(0, yaw: 25)
        #expect(AttentionPolicy(sensitivity: .gentle).isOnScreen(s))
        #expect(!AttentionPolicy(sensitivity: .medium).isOnScreen(s))
        #expect(!AttentionPolicy(sensitivity: .strict).isOnScreen(face(0, yaw: 16)))
        #expect(AttentionSensitivity.allCases.map(\.label) == ["Gentle", "Medium", "Strict"])
        #expect(AttentionSensitivity.strict.gazeLimit == 0.45)
    }

    @Test func resetClearsAlert() {
        var m = AttentionMonitor()
        _ = feed(&m, from: 0, to: 4) { face($0, yaw: 40) }
        #expect(m.state.isAlerting)
        m.reset()
        #expect(m.state == .attentive)
        // Off-screen timer restarts after reset.
        let s = m.ingest(face(5, yaw: 40))
        #expect(!s.isAlerting)
    }
}
