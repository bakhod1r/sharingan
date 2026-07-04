import Foundation

public struct BreakExerciseStep: Equatable, Sendable, Codable {
    public var direction: String
    public var holdSeconds: Double
    public var instruction: String

    public init(direction: String, holdSeconds: Double, instruction: String = "") {
        self.direction = direction
        self.holdSeconds = max(0.5, holdSeconds)
        self.instruction = instruction.isEmpty
            ? "Look \(Self.directionLabel(direction))"
            : instruction
    }

    public var targetGaze: GazeDirection {
        switch direction.lowercased() {
        case "up", "y":           return .up
        case "down", "p":         return .down
        case "left", "l":         return .left
        case "right", "r":        return .right
        case "up_left", "upleft": return .upLeft
        case "up_right", "upright": return .upRight
        case "down_left", "downleft": return .downLeft
        case "down_right", "downright": return .downRight
        default:                            return .center
        }
    }

    private static func directionLabel(_ key: String) -> String {
        switch key.lowercased() {
        case "up":       return "up"
        case "down":     return "down"
        case "left":     return "left"
        case "right":    return "right"
        case "center":   return "center"
        case "up_left":  return "up and to the left"
        case "up_right": return "up and to the right"
        case "down_left": return "down and to the left"
        case "down_right": return "down and to the right"
        default:         return key
        }
    }
}

public struct BreakExercise: Equatable, Sendable, Codable {
    public var name: String
    public var steps: [BreakExerciseStep]

    public init(name: String, steps: [BreakExerciseStep]) {
        self.name = name
        self.steps = steps
    }

    public static let twentyRule = BreakExercise(
        name: "20-20-20",
        steps: [
            .init(direction: "far", holdSeconds: 20,
                  instruction: "Look at something 20 feet away for 20 seconds"),
            .init(direction: "center", holdSeconds: 5,
                  instruction: "Close your eyes and breathe"),
        ]
    )

    public static let gaze = BreakExercise(
        name: "Gaze exercise",
        steps: [
            .init(direction: "right",       holdSeconds: 4),
            .init(direction: "center",      holdSeconds: 2),
            .init(direction: "left",        holdSeconds: 4),
            .init(direction: "center",      holdSeconds: 2),
            .init(direction: "up",          holdSeconds: 4),
            .init(direction: "center",      holdSeconds: 2),
            .init(direction: "down",        holdSeconds: 4),
            .init(direction: "center",      holdSeconds: 2),
            .init(direction: "up_right",    holdSeconds: 4),
            .init(direction: "down_left",   holdSeconds: 4),
            .init(direction: "up_left",     holdSeconds: 4),
            .init(direction: "down_right",  holdSeconds: 4),
            .init(direction: "center",      holdSeconds: 2),
            .init(direction: "circle_cw",   holdSeconds: 6,
                  instruction: "Roll your eyes slowly clockwise"),
            .init(direction: "circle_ccw",  holdSeconds: 6,
                  instruction: "Now roll them counter-clockwise"),
            .init(direction: "figure8",     holdSeconds: 6,
                  instruction: "Trace a figure 8 with your eyes"),
        ]
    )

    public static let blink = BreakExercise(
        name: "Blink exercise",
        steps: [
            .init(direction: "blink",       holdSeconds: 8,
                  instruction: "Blink quickly 8 times"),
            .init(direction: "center",      holdSeconds: 4,
                  instruction: "Now keep your eyes softly closed for 4 seconds"),
        ]
    )

    public static let defaultSequence: [BreakExercise] = [.twentyRule, .gaze, .blink]

    public static func library() -> [BreakExercise] { defaultSequence }
}