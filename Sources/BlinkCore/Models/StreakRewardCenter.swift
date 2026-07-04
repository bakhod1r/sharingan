import Foundation

@MainActor
public final class StreakRewardCenter: ObservableObject {
    public static let shared = StreakRewardCenter()

    public struct Reward: Identifiable, Equatable, Sendable {
        public var id: String { badge.id }
        public var badge: StreakBadge
        public var achievedDate: Date

        public init(badge: StreakBadge, achievedDate: Date = Date()) {
            self.badge = badge
            self.achievedDate = achievedDate
        }
    }

    @Published public private(set) var pendingReward: Reward?
    public private(set) var unlockedBadges: [Reward] = []

    private var lastKnownStreak: Int = 0

    public init() {}

    /// So'nggi streak qiymatini tekshirib, yangi milestone'lar uchun reward o'rnatadi.
    /// Faqat yangi yetilgan ( ilgari ochilmagan ) badge'lar uchun reward chiqaradi.
    public func evaluate(streak: Int) {
        let previouslyEarned = Set(StreakBadge.earned(forStreak: lastKnownStreak).map { $0.id })
        let nowEarned = StreakBadge.earned(forStreak: streak)
        let newlyUnlocked = nowEarned.filter { !previouslyEarned.contains($0.id) }

        // Track all unlocked (doimiy)
        for b in nowEarned where !unlockedBadges.contains(where: { $0.id == b.id }) {
            unlockedBadges.append(Reward(badge: b))
        }

        // Eng katta yangi milestone'ni ko'rsatish uchun
        if let topNew = newlyUnlocked.last {
            pendingReward = Reward(badge: topNew)
        }
        lastKnownStreak = streak
    }

    public func dismiss() {
        pendingReward = nil
    }

    /// Test'lar uchun holatni qayta o'rnatish.
    public func resetForTesting() {
        pendingReward = nil
        unlockedBadges.removeAll()
        lastKnownStreak = 0
    }
}