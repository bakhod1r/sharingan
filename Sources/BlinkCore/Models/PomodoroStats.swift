import Foundation

public struct PomodoroStats: Codable, Equatable, Sendable {
    public var completedFocus: Int = 0
    public var completedToday: Int = 0
    public var streakDays: Int = 0

    public init() {}

    public mutating func registerFocusCompletion() {
        completedFocus += 1
        completedToday += 1
    }

    public mutating func resetTodayIfNeeded() {
        completedToday = 0
    }
}