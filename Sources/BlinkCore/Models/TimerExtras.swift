import Foundation

public enum TimerMode: String, Codable, CaseIterable, Sendable {
    case countdown
    case countUp

    public var label: String {
        switch self {
        case .countdown: return "Countdown"
        case .countUp:   return "Count up"
        }
    }
}

public enum TimeDisplayFormat: String, Codable, CaseIterable, Sendable {
    case minutesSeconds   // 25:00
    case hoursMinutesSeconds // 0:25:00
    case compact          // 25:00, but 1:05:00 once >= 1h

    public var label: String {
        switch self {
        case .minutesSeconds:     return "Minutes:Seconds (25:00)"
        case .hoursMinutesSeconds: return "Hours:Minutes:Seconds (0:25:00)"
        case .compact:            return "Compact (auto)"
        }
    }

    /// Formats a duration (seconds) according to the style.
    public func string(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        switch self {
        case .minutesSeconds:
            return String(format: "%02d:%02d", s / 60, sec)
        case .hoursMinutesSeconds:
            return String(format: "%d:%02d:%02d", h, m, sec)
        case .compact:
            return h > 0
                ? String(format: "%d:%02d:%02d", h, m, sec)
                : String(format: "%02d:%02d", m, sec)
        }
    }
}

public struct RepeatConfig: Codable, Equatable, Sendable {
    public var enabled: Bool = false
    public var count: Int = 1
    public var delaySeconds: TimeInterval = 0

    public init() {}
    public init(enabled: Bool, count: Int = 1, delaySeconds: TimeInterval = 0) {
        self.enabled = enabled
        self.count = max(1, count)
        self.delaySeconds = max(0, delaySeconds)
    }

    public var delaysTotal: TimeInterval {
        guard enabled else { return 0 }
        return TimeInterval(max(0, count - 1)) * delaySeconds
    }
}