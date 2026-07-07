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

    /// Seed the baseline from an already-earned streak (e.g. loaded from disk at
    /// launch) WITHOUT announcing anything. Without this, `lastKnownStreak` starts
    /// at 0 every launch, so the first focus session after a restart re-fires an
    /// already-earned milestone as a fresh notification + TTS.
    public func prime(streak: Int) {
        for b in StreakBadge.earned(forStreak: streak)
        where !unlockedBadges.contains(where: { $0.id == b.id }) {
            unlockedBadges.append(Reward(badge: b))
        }
        lastKnownStreak = max(lastKnownStreak, streak)
    }

    /// So'nggi streak qiymatini tekshirib, yangi milestone'lar uchun reward o'rnatadi.
    /// Faqat yangi yetilgan (ilgari ochilmagan) badge uchun reward qaytaradi — shu
    /// bilan chaqiruvchi har pomidoroда emas, faqat yangi badge'да e'lon qiladi.
    @discardableResult
    public func evaluate(streak: Int) -> Reward? {
        let previouslyEarned = Set(StreakBadge.earned(forStreak: lastKnownStreak).map { $0.id })
        let nowEarned = StreakBadge.earned(forStreak: streak)
        let newlyUnlocked = nowEarned.filter { !previouslyEarned.contains($0.id) }

        // Track all unlocked (doimiy)
        for b in nowEarned where !unlockedBadges.contains(where: { $0.id == b.id }) {
            unlockedBadges.append(Reward(badge: b))
        }

        lastKnownStreak = streak

        // Only surface (and return) a genuinely new milestone; otherwise leave any
        // existing pendingReward untouched and return nil so nothing re-announces.
        guard let topNew = newlyUnlocked.last else { return nil }
        let reward = Reward(badge: topNew)
        pendingReward = reward
        return reward
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