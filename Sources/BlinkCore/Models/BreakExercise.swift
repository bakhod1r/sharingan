import Foundation

public struct BreakExerciseStep: Equatable, Sendable, Codable {
    public var direction: String
    public var holdSeconds: Double
    public var instruction: String

    public init(direction: String, holdSeconds: Double, instruction: String = "") {
        self.direction = direction
        self.holdSeconds = max(0.5, holdSeconds)
        self.instruction = instruction.isEmpty
            ? "Ko'zingni \(directionLabel(direction)) qarating"
            : instruction
    }

    public var targetGaze: GazeDirection {
        switch direction.lowercased() {
        case "up", "yuqori", "y":           return .up
        case "down", "past", "p":           return .down
        case "left", "chap", "l":           return .left
        case "right", "o'ng", "ong", "r":   return .right
        case "up_left", "upleft":           return .upLeft
        case "up_right", "upright":        return .upRight
        case "down_left", "downleft":      return .downLeft
        case "down_right", "downright":     return .downRight
        default:                            return .center
        }
    }

    private func directionLabel(_ key: String) -> String {
        switch key.lowercased() {
        case "up":       return "yuqoriga"
        case "down":     return "pastga"
        case "left":     return "chapga"
        case "right":    return "o'ngga"
        case "center":   return "markazga"
        case "up_left":  return "yuqori chapga"
        case "up_right": return "yuqori o'ngga"
        case "down_left": return "past chapga"
        case "down_right": return "past o'ngga"
        default:         return "\(key) tomon"
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
                  instruction: "6 metr (~20 fut) uzoqdagi narsaga 20 soniya qarang"),
            .init(direction: "center", holdSeconds: 5,
                  instruction: "Ko'zingni yum, nafas ol"),
        ]
    )

    public static let gaze = BreakExercise(
        name: "Gaze mashqi",
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
        ]
    )

    public static let blink = BreakExercise(
        name: "Blink mashqi",
        steps: [
            .init(direction: "blink",       holdSeconds: 8,
                  instruction: "8 marta tez ko'zingni yum och"),
            .init(direction: "center",      holdSeconds: 4,
                  instruction: "Endi yuming sokin 4 soniya"),
        ]
    )

    public static let defaultSequence: [BreakExercise] = [.twentyRule, .gaze, .blink]

    public static func library() -> [BreakExercise] { defaultSequence }
}