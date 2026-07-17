import Foundation

/// Rule-based burnout screening over the recent session log — pure and
/// unit-tested. Each rule that fires adds a human-readable reason; two or more
/// firing raises the warning level (one alone is just a heads-up not surfaced
/// as an alarm).
public enum BurnoutDetector {
    public struct Result: Equatable, Sendable {
        public var reasons: [String]
        public var isWarning: Bool { reasons.count >= 2 }
        public init(reasons: [String]) { self.reasons = reasons }
    }

    /// Thresholds, named so the rules read clearly.
    public static let heavyDayPomodoros = 8
    public static let hugeDayPomodoros = 12
    public static let heavyStreakDays = 5
    public static let lateNightHour = 23
    public static let lateNightDays = 3

    public static func evaluate(sessions: [SessionRecord],
                                now: Date = Date()) -> Result {
        let cal = Calendar.current
        let focus = sessions.filter { $0.phase == .focus && $0.completed }

        // Completed focus per day.
        var perDay: [Date: Int] = [:]
        for s in focus { perDay[cal.startOfDay(for: s.start), default: 0] += 1 }

        var reasons: [String] = []

        // 1. A huge single day.
        if let peak = perDay.values.max(), peak >= hugeDayPomodoros {
            reasons.append("A \(peak)-pomodoro day — that's a lot in one sitting.")
        }

        // 2. Consecutive heavy days.
        let heavyDays = Set(perDay.filter { $0.value >= heavyDayPomodoros }.keys)
        if longestConsecutiveRun(days: heavyDays, cal: cal) >= heavyStreakDays {
            reasons.append("\(heavyStreakDays)+ heavy days in a row without letting up.")
        }

        // 3. Skipping breaks.
        let breaks = sessions.filter { $0.phase.isBreak }
        if breaks.count >= 4 {
            let skipped = breaks.filter { !$0.completed }.count
            if Double(skipped) / Double(breaks.count) > 0.5 {
                reasons.append("You're skipping more than half of your breaks.")
            }
        }

        // 4. Repeated late-night focus.
        let lateDays = Set(focus
            .filter { cal.component(.hour, from: $0.start) >= lateNightHour }
            .map { cal.startOfDay(for: $0.start) })
        if lateDays.count >= lateNightDays {
            reasons.append("Late-night focus on \(lateDays.count) recent days.")
        }

        return Result(reasons: reasons)
    }

    /// Longest run of consecutive calendar days present in the set.
    static func longestConsecutiveRun(days: Set<Date>, cal: Calendar) -> Int {
        guard !days.isEmpty else { return 0 }
        var longest = 0
        for day in days {
            // Only count from the start of a run (previous day absent).
            let prev = cal.date(byAdding: .day, value: -1, to: day)!
            if days.contains(prev) { continue }
            var run = 1
            var cursor = day
            while let next = cal.date(byAdding: .day, value: 1, to: cursor),
                  days.contains(next) {
                run += 1; cursor = next
            }
            longest = max(longest, run)
        }
        return longest
    }
}
