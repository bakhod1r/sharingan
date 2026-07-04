import Foundation

public struct StreakBadge: Equatable, Sendable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var days: Int
    public var emoji: String

    public init(id: String, title: String, subtitle: String, days: Int, emoji: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.days = days
        self.emoji = emoji
    }

    /// Static milestones — unlocked as the user's streak grows.
    public static let milestones: [StreakBadge] = [
        .init(id: "first",    title: "First step",  subtitle: "First pomodoro",   days: 1,  emoji: "✨"),
        .init(id: "week",     title: "One week",    subtitle: "7 days in a row",  days: 7,  emoji: "🔥"),
        .init(id: "fortnight",title: "Two weeks",   subtitle: "14 days",          days: 14, emoji: "⚡"),
        .init(id: "month",    title: "One month",   subtitle: "30 days",          days: 30, emoji: "🏆"),
        .init(id: "quarter",  title: "A quarter",   subtitle: "90 days",          days: 90, emoji: "💎"),
        .init(id: "year",     title: "One year",    subtitle: "365 days",         days: 365,emoji: "👑"),
    ]

    /// Berilgan streak uzunligi uchun barcha ochilgan badge'lar.
    public static func earned(forStreak streak: Int) -> [StreakBadge] {
        milestones.filter { streak >= $0.days }
    }

    /// Keyingi (ochilmagan) milestone — rag'bat uchun.
    public static func next(forStreak streak: Int) -> StreakBadge? {
        milestones.first { $0.days > streak }
    }
}