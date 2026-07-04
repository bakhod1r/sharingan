import Foundation

/// TTS instruction text for a single break step and its rotation pool.
public struct TTSInstruction: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var direction: String
    public var text: String
    public var kalibTexts: [String]

    public init(id: String, direction: String, text: String, kalibTexts: [String] = []) {
        self.id = id
        self.direction = direction
        self.text = text
        self.kalibTexts = kalibTexts
    }

    public static let defaults: [TTSInstruction] = [
        .init(id: "far", direction: "far",
              text: "Look at something 20 feet away for 20 seconds",
              kalibTexts: ["Focus on the distance", "Keep breathing softly"]),
        .init(id: "center", direction: "center",
              text: "Look straight ahead and breathe"),
        .init(id: "up", direction: "up",
              text: "Look up"),
        .init(id: "down", direction: "down",
              text: "Look down"),
        .init(id: "left", direction: "left",
              text: "Look left"),
        .init(id: "right", direction: "right",
              text: "Look right"),
        .init(id: "up_left", direction: "up_left",
              text: "Look up and to the left"),
        .init(id: "up_right", direction: "up_right",
              text: "Look up and to the right"),
        .init(id: "down_left", direction: "down_left",
              text: "Look down and to the left"),
        .init(id: "down_right", direction: "down_right",
              text: "Look down and to the right"),
        .init(id: "blink", direction: "blink",
              text: "Blink quickly several times"),
    ]
}

public struct TTSAnnouncementsSettings: Codable, Equatable, Sendable {
    public var enabled: Bool = true
    /// Rotation interval in seconds during a step hold. 0 disables kalib.
    public var kalibIntervalSeconds: TimeInterval = 20
    public var instructions: [TTSInstruction] = TTSInstruction.defaults
    /// Generic rotation reminders (step-independent).
    public var globalKalib: [String] = [
        "Close your eyes and breathe",
        "Look further away",
        "Relax your shoulders",
        "Sit up straight"
    ]

    public init() {}

    public func instruction(forDirection direction: String) -> TTSInstruction? {
        instructions.first { $0.direction.lowercased() == direction.lowercased() }
    }

    public mutating func updateInstruction(text: String, forDirection direction: String) {
        if let idx = instructions.firstIndex(where: { $0.direction.lowercased() == direction.lowercased() }) {
            instructions[idx].text = text
        } else {
            instructions.append(TTSInstruction(id: UUID().uuidString,
                                                direction: direction,
                                                text: text))
        }
    }

    public mutating func updateKalibTexts(_ texts: [String], forDirection direction: String) {
        if let idx = instructions.firstIndex(where: { $0.direction.lowercased() == direction.lowercased() }) {
            instructions[idx].kalibTexts = texts
        }
    }
}