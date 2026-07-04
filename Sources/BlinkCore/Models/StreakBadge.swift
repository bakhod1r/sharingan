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

    /// Statik milesstonelar — foydalanuvchi yetganda ochiladi.
    public static let milestones: [StreakBadge] = [
        .init(id: "first",    title: "Birinchi qadam",  subtitle: "Ilk pomodoro",        days: 1,  emoji: "✨"),
        .init(id: "week",     title: "Bir hafta",       subtitle: "7 ketma-ket kun",     days: 7,  emoji: "🔥"),
        .init(id: "fortnight",title: "Ikki hafta",     subtitle: "14 kun",              days: 14, emoji: "⚡"),
        .init(id: "month",    title: "Bir oy",          subtitle: "30 kun",              days: 30, emoji: "🏆"),
        .init(id: "quarter",  title: "Chorak",         subtitle: "90 kun",              days: 90, emoji: "💎"),
        .init(id: "year",     title: "Yil",             subtitle: "365 kun",             days: 365,emoji: "👑"),
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