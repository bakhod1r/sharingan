import Foundation

/// One camera frame reduced to what the attention guard needs. Pure value —
/// no Vision types — so the whole decision chain is unit-testable.
public struct AttentionSample: Equatable, Sendable {
    public var faceDetected: Bool
    /// Head rotation around the vertical axis, degrees (0 = facing the camera).
    public var yaw: Double
    /// Head rotation around the horizontal axis, degrees.
    public var pitch: Double
    public var gaze: GazeDirection
    public var eyesClosed: Bool
    public var at: Date
    /// Last keyboard/mouse event system-wide. Hands on the keys = working,
    /// whatever the camera thinks (typing while looking at the keyboard).
    public var lastInputAt: Date?

    public init(faceDetected: Bool = true, yaw: Double = 0, pitch: Double = 0,
                gaze: GazeDirection = .center, eyesClosed: Bool = false, at: Date,
                lastInputAt: Date? = nil) {
        self.lastInputAt = lastInputAt
        self.faceDetected = faceDetected
        self.yaw = yaw
        self.pitch = pitch
        self.gaze = gaze
        self.eyesClosed = eyesClosed
        self.at = at
    }
}

public enum AttentionSensitivity: String, Codable, CaseIterable, Sendable {
    case gentle, medium, strict

    public var label: String {
        switch self {
        case .gentle: return "Gentle"
        case .medium: return "Medium"
        case .strict: return "Strict"
        }
    }

    /// Default on-screen envelope (no calibration): head yaw/pitch in degrees,
    /// pupil gaze as a fraction of the eye opening.
    public var yawLimit: Double {
        switch self { case .gentle: return 30; case .medium: return 22; case .strict: return 15 }
    }
    /// Wide on purpose: glancing down at the keyboard or notes tilts the head
    /// 20–30°. Symmetric because Vision's pitch sign isn't relied on — an
    /// extreme tilt (ceiling, lap/phone) still trips it.
    public var pitchLimit: Double {
        switch self { case .gentle: return 40; case .medium: return 34; case .strict: return 26 }
    }
    public var gazeLimit: Double {
        switch self { case .gentle: return 0.8; case .medium: return 0.6; case .strict: return 0.45 }
    }

    /// Extra room added around a calibrated envelope.
    var angleSlack: Double {
        switch self { case .gentle: return 8; case .medium: return 4; case .strict: return 1 }
    }
    var gazeSlack: Double {
        switch self { case .gentle: return 0.2; case .medium: return 0.1; case .strict: return 0.03 }
    }
    /// Calibration only sees the screen; add room for keyboard/desk glances.
    var keyboardPitchSlack: Double { 20 }
}

/// The user's own "looking at the screen" envelope, measured by looking at
/// five points (centre + corners). Per-Mac: it depends on where the camera sits.
public struct AttentionCalibration: Codable, Equatable, Sendable {
    public var yawMin: Double
    public var yawMax: Double
    public var pitchMin: Double
    public var pitchMax: Double
    public var gazeXMin: Double
    public var gazeXMax: Double
    public var gazeYMin: Double
    public var gazeYMax: Double
    public var createdAt: Date

    /// Minimum face frames for a usable envelope.
    public static let minimumSamples = 5
    static let angleMargin = 5.0
    static let gazeMargin = 0.1

    public init(yawMin: Double, yawMax: Double, pitchMin: Double, pitchMax: Double,
                gazeXMin: Double, gazeXMax: Double, gazeYMin: Double, gazeYMax: Double,
                createdAt: Date = Date()) {
        self.yawMin = yawMin; self.yawMax = yawMax
        self.pitchMin = pitchMin; self.pitchMax = pitchMax
        self.gazeXMin = gazeXMin; self.gazeXMax = gazeXMax
        self.gazeYMin = gazeYMin; self.gazeYMax = gazeYMax
        self.createdAt = createdAt
    }

    /// Min/max of the face-detected samples plus a small margin. Gaze comes
    /// from open-eye frames only. Nil when there is too little data.
    public static func from(samples: [AttentionSample]) -> AttentionCalibration? {
        let faces = samples.filter(\.faceDetected)
        let open = faces.filter { !$0.eyesClosed }
        guard faces.count >= minimumSamples, !open.isEmpty else { return nil }
        let yaws = faces.map(\.yaw), pitches = faces.map(\.pitch)
        let gx = open.map(\.gaze.dx), gy = open.map(\.gaze.dy)
        return AttentionCalibration(
            yawMin: yaws.min()! - angleMargin, yawMax: yaws.max()! + angleMargin,
            pitchMin: pitches.min()! - angleMargin, pitchMax: pitches.max()! + angleMargin,
            gazeXMin: gx.min()! - gazeMargin, gazeXMax: gx.max()! + gazeMargin,
            gazeYMin: gy.min()! - gazeMargin, gazeYMax: gy.max()! + gazeMargin,
            createdAt: samples.last?.at ?? Date())
    }
}

public struct AttentionPolicy: Equatable, Sendable {
    /// Continuous off-screen time before the alert fires.
    public var grace: TimeInterval
    /// Continuous on-screen time before the alert clears (hysteresis).
    public var recovery: TimeInterval
    /// Face missing this long counts as away (leaning / reaching is fine briefly).
    public var noFaceGrace: TimeInterval
    public var sensitivity: AttentionSensitivity
    public var calibration: AttentionCalibration?
    /// Median window in samples. Size it to the sample rate: 5 at ~10 fps,
    /// 3 at the focus guard's 1 Hz (a 5-sample median there lags ~3 s).
    public var smoothingWindow: Int

    public init(grace: TimeInterval = 2, recovery: TimeInterval = 0.5,
                noFaceGrace: TimeInterval = 5,
                sensitivity: AttentionSensitivity = .medium,
                calibration: AttentionCalibration? = nil,
                smoothingWindow: Int = 5) {
        self.smoothingWindow = max(1, smoothingWindow)
        self.grace = grace
        self.recovery = recovery
        self.noFaceGrace = noFaceGrace
        self.sensitivity = sensitivity
        self.calibration = calibration
    }

    /// Keyboard/mouse activity this recent counts as attentive outright.
    public var inputGrace: TimeInterval = 3

    public func hasRecentInput(_ s: AttentionSample) -> Bool {
        guard let last = s.lastInputAt else { return false }
        return s.at.timeIntervalSince(last) <= inputGrace
    }

    /// True when the (already smoothed) sample points at the screen. Gaze is
    /// ignored while the eyes are closed — a blink reads as a wild pupil offset.
    public func isOnScreen(_ s: AttentionSample) -> Bool {
        guard s.faceDetected else { return false }
        let a = sensitivity.angleSlack, g = sensitivity.gazeSlack
        // Eyes DOWN (+dy) is never "away": that's the keyboard / notes. Only
        // sideways and upward gaze count against attention.
        if let c = calibration {
            let p = a + sensitivity.keyboardPitchSlack
            guard s.yaw >= c.yawMin - a, s.yaw <= c.yawMax + a,
                  s.pitch >= c.pitchMin - p, s.pitch <= c.pitchMax + p else { return false }
            if s.eyesClosed { return true }
            return s.gaze.dx >= c.gazeXMin - g && s.gaze.dx <= c.gazeXMax + g
                && s.gaze.dy >= c.gazeYMin - g
        }
        guard abs(s.yaw) <= sensitivity.yawLimit,
              abs(s.pitch) <= sensitivity.pitchLimit else { return false }
        if s.eyesClosed { return true }
        return abs(s.gaze.dx) <= sensitivity.gazeLimit
            && s.gaze.dy >= -sensitivity.gazeLimit
    }
}

public enum AttentionState: Equatable, Sendable {
    case attentive
    case drifting(since: Date)
    case away(since: Date)
    case noFace(since: Date)

    /// Away / no-face: the red alert is up and the timer is paused.
    public var isAlerting: Bool {
        switch self {
        case .away, .noFace: return true
        case .attentive, .drifting: return false
        }
    }
}
