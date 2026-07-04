import Foundation

public struct PomodoroStats: Codable, Equatable, Sendable {
    public var completedFocus: Int = 0
    public var completedToday: Int = 0
    public var streakDays: Int = 0
    public var streak: StreakStore = .init()

    public init() {}

    public mutating func registerFocusCompletion(on date: Date = Date()) {
        completedFocus += 1
        completedToday += 1
        streak.registerFocus(on: date)
        streakDays = streak.currentStreak
    }

    public mutating func resetTodayIfNeeded() {
        completedToday = 0
    }
}