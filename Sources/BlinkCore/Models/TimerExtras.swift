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