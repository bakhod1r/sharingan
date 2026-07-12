import Foundation

public struct StreakStore: Codable, Equatable, Sendable {
    public var currentStreak: Int = 0
    public var longestStreak: Int = 0
    public var lastCompletedDay: Date?

    public init() {}

    /// Register a focus completion occurring on the given date (kept to day
    /// granularity). Returns the updated streak.
    public mutating func registerFocus(on date: Date = Date(),
                                       calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: date)
        if let last = lastCompletedDay {
            let lastDay = calendar.startOfDay(for: last)
            let dayDiff = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
            if dayDiff == 0 {
                // Same day — streak unchanged, lastCompleted refreshed.
            } else if dayDiff == 1 {
                currentStreak += 1
            } else {
                currentStreak = 1
            }
        } else {
            currentStreak = 1
        }
        lastCompletedDay = today
        if currentStreak > longestStreak { longestStreak = currentStreak }
    }

    /// Returns true if the user has completed at least one focus today.
    public func completedToday(on date: Date = Date(),
                               calendar: Calendar = .current) -> Bool {
        guard let last = lastCompletedDay else { return false }
        return calendar.isDateInToday(last) || calendar.isDate(last, inSameDayAs: date)
    }
}