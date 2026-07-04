import Foundation

/// Bir eslatma: sutkaning muayyan vaqtida yoki interval-li takrorlash.
public struct ReminderItem: Codable, Equatable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case posture
        case water
        case custom

        public var label: String {
            switch self {
            case .posture: return "Posture"
            case .water:   return "Water"
            case .custom: return "Custom"
            }
        }

        public var systemImage: String {
            switch self {
            case .posture: return "figure.stand"
            case .water:  return "drop.fill"
            case .custom:  return "bell.fill"
            }
        }

        public func defaultTickle() -> [String] {
            switch self {
            case .posture: return ["Sit up straight and relax your shoulders."]
            case .water:   return ["Time to drink a glass of water."]
            case .custom:  return ["Custom reminder."]
            }
        }
    }

    public var id: String
    public var kind: Kind
    /// Interval interval (minut), interval-based takrorlash uchun.
    public var intervalMinutes: Int
    /// Bir martalik JSON matni. Bo'sh bo'lsa — default matn.
    public var message: String
    public var enabled: Bool

    public init(id: String = UUID().uuidString,
                kind: Kind,
                intervalMinutes: Int = 30,
                message: String = "",
                enabled: Bool = true) {
        self.id = id
        self.kind = kind
        self.intervalMinutes = max(1, intervalMinutes)
        self.message = message
        self.enabled = enabled
    }

    public var resolvedMessage: String {
        message.isEmpty ? (kind.defaultTickle().first ?? "Reminder") : message
    }

    public var intervalSeconds: TimeInterval { TimeInterval(intervalMinutes) * 60 }
}

public struct ReminderSettings: Codable, Equatable, Sendable {
    public var reminders: [ReminderItem] = [
        .init(kind: .posture, intervalMinutes: 30),
        .init(kind: .water, intervalMinutes: 60),
    ]
    public var enabled: Bool = true
    /// Faqat focus vaqtida ishlasin (break'da o'chadi).
    public var duringFocusOnly: Bool = true

    public init() {}
}