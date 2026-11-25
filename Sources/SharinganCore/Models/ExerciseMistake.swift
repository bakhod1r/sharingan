import Foundation

/// What the user is doing wrong on a camera-validated gaze step.
public enum ExerciseMistake: Equatable, Sendable {
    case wrongDirection(looked: String, target: String)
    case notMoving(target: String)
    case noFace

    /// Gaze magnitude under which the eyes count as "straight ahead".
    public static let centerThreshold = 0.25

    /// The validator's match rule: the detected 8-way label equals the target's.
    public static func gazeMatches(_ gaze: GazeDirection, _ target: GazeDirection) -> Bool {
        gaze.label == target.label
    }

    /// nil when the step is being done right. `tolerance` is kept for API
    /// symmetry; matching is label-based, same as `ExerciseValidator`.
    public static func evaluate(gaze: GazeDirection, faceDetected: Bool,
                                target: GazeDirection, tolerance: Double) -> ExerciseMistake? {
        guard faceDetected else { return .noFace }
        if gazeMatches(gaze, target) { return nil }
        if gaze.magnitude < centerThreshold { return .notMoving(target: target.label) }
        return .wrongDirection(looked: gaze.label, target: target.label)
    }

    public var title: String {
        switch self {
        case .wrongDirection(let looked, _): return "You looked \(looked.uppercased())"
        case .notMoving: return "Move your eyes"
        case .noFace: return "Face the camera"
        }
    }

    public var subtitle: String {
        switch self {
        case .wrongDirection(_, let target): return "Look \(target.uppercased()) — follow the eyes"
        case .notMoving(let target): return "Look \(target.uppercased()) — not straight ahead"
        case .noFace: return "I can't see your eyes"
        }
    }

    /// Direction the warning arrow points (the step's target); nil without a face.
    public func arrow(target: GazeDirection) -> GazeDirection? {
        if case .noFace = self { return nil }
        return target
    }
}
