import Foundation

/// How often a habit is expected. Persisted as a single string
/// ("daily", "weekdays:2,4,6", "perWeek:3"); unknown strings degrade to `.daily`
/// instead of dropping the task.
public enum HabitSchedule: Codable, Equatable, Hashable, Sendable {
    case daily
    /// Specific days; values are `Calendar` weekday numbers (1 = Sunday … 7).
    case weekdays(Set<Int>)
    /// Any N days of each calendar week (1...7).
    case timesPerWeek(Int)

    public var stringValue: String {
        switch self {
        case .daily: return "daily"
        case .weekdays(let days): return "weekdays:" + days.sorted().map(String.init).joined(separator: ",")
        case .timesPerWeek(let n): return "perWeek:\(n)"
        }
    }

    public init(string: String) {
        let parts = string.split(separator: ":", maxSplits: 1).map(String.init)
        switch parts.first {
        case "weekdays":
            let days = Set((parts.count == 2 ? parts[1] : "").split(separator: ",")
                .compactMap { Int($0) }.filter { (1...7).contains($0) })
            self = days.isEmpty ? .daily : .weekdays(days)
        case "perWeek":
            if parts.count == 2, let n = Int(parts[1]), (1...7).contains(n) {
                self = .timesPerWeek(n)
            } else {
                self = .daily
            }
        default:
            self = .daily
        }
    }

    public init(from decoder: Decoder) throws {
        self = HabitSchedule(string: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(stringValue)
    }

    /// Short human label for subtitles.
    public var label: String {
        switch self {
        case .daily: return "Every day"
        case .weekdays(let days):
            let syms = Calendar.current.shortWeekdaySymbols
            let order = (0..<7).map { (Calendar.current.firstWeekday - 1 + $0) % 7 + 1 }
            return order.filter(days.contains).map { syms[$0 - 1] }.joined(separator: ", ")
        case .timesPerWeek(let n): return "\(n)× per week"
        }
    }
}

/// What makes a habit day count as done.
/// Persisted as "pomodoro:3" / "manual"; unknown strings degrade to `.manual`.
public enum HabitCompletionMode: Codable, Equatable, Hashable, Sendable {
    /// Done automatically once the day's task-level focus count reaches `target`.
    case pomodoro(target: Int)
    /// The user ticks the day by hand.
    case manual

    public var stringValue: String {
        switch self {
        case .pomodoro(let t): return "pomodoro:\(t)"
        case .manual: return "manual"
        }
    }

    public init(string: String) {
        let parts = string.split(separator: ":", maxSplits: 1).map(String.init)
        if parts.first == "pomodoro", parts.count == 2, let t = Int(parts[1]), t >= 1 {
            self = .pomodoro(target: t)
        } else {
            self = .manual
        }
    }

    public init(from decoder: Decoder) throws {
        self = HabitCompletionMode(string: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(stringValue)
    }
}

/// Habit configuration of a task. `nil` on `TaskItem.habit` = ordinary task.
/// Local only: never synced to CloudKit.
public struct TaskHabit: Codable, Equatable, Hashable, Sendable {
    public var schedule: HabitSchedule
    public var mode: HabitCompletionMode
    /// Start of the day tracking began; earlier days are `.beforeStart`.
    public var startDay: Date

    public init(schedule: HabitSchedule = .daily,
                mode: HabitCompletionMode = .manual,
                startDay: Date) {
        self.schedule = schedule
        self.mode = mode
        self.startDay = startDay
    }

    /// Stable string for hashing/diffing in persistence.
    public var stringValue: String {
        "\(schedule.stringValue)|\(mode.stringValue)|\(startDay.timeIntervalSince1970)"
    }
}
