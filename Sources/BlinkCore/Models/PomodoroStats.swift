import Foundation

/// Kunlik pomodoro tushirish tarixi — SwiftCharts grafik uchun.
public struct DailyCount: Codable, Equatable, Sendable, Identifiable {
    public var id: Date { day }
    public var day: Date
    public var count: Int

    public init(day: Date, count: Int) {
        self.day = day
        self.count = count
    }
}

public struct PomodoroStats: Codable, Equatable, Sendable {
    public var completedFocus: Int = 0
    public var completedToday: Int = 0
    public var streakDays: Int = 0
    public var streak: StreakStore = .init()
    public var history: [DailyCount] = []
    /// Day (start-of-day) the stored `completedToday` counter belongs to, used to
    /// roll it over when a new day begins. `nil` for pre-migration data.
    public var lastCountedDay: Date?

    public init() {}

    public mutating func registerFocusCompletion(on date: Date = Date()) {
        completedFocus += 1

        let day = Calendar.current.startOfDay(for: date)
        // Roll `completedToday` over at the day boundary instead of accumulating
        // yesterday's count forever.
        if let last = lastCountedDay, !Calendar.current.isDate(last, inSameDayAs: day) {
            completedToday = 0
        }
        lastCountedDay = day
        completedToday += 1

        streak.registerFocus(on: date)
        streakDays = streak.currentStreak

        if let idx = history.firstIndex(where: { Calendar.current.isDate($0.day, inSameDayAs: day) }) {
            history[idx].count += 1
        } else {
            history.append(DailyCount(day: day, count: 1))
            trimHistory()
        }
    }

    /// Zeroes `completedToday` only when the stored counter is from an earlier
    /// day (call cheaply on launch / periodically). Same-day calls are a no-op,
    /// so a legitimate running count is never wiped.
    public mutating func resetTodayIfNeeded(now: Date = Date()) {
        let today = Calendar.current.startOfDay(for: now)
        if let last = lastCountedDay, !Calendar.current.isDate(last, inSameDayAs: today) {
            completedToday = 0
            lastCountedDay = today
        }
    }

    /// Day-aware read of today's completions — returns 0 if the stored counter
    /// belongs to a previous day, so UI stays correct across midnight without a
    /// mutation.
    public func completedTodayCount(now: Date = Date()) -> Int {
        guard let last = lastCountedDay,
              Calendar.current.isDate(last, inSameDayAs: Calendar.current.startOfDay(for: now))
        else { return 0 }
        return completedToday
    }

    /// Faqat oxirgi `days` kun saqlanadi (default 90).
    private mutating func trimHistory(_ days: Int = 90) {
        let cutoff = Calendar.current.date(byAdding: .day,
                                            value: -days,
                                            to: Calendar.current.startOfDay(for: Date())) ?? Date()
        history = history.filter { $0.day >= cutoff }
        history.sort { $0.day < $1.day }
    }

    /// Oxirgi N kunlik to'ldirilgan array (0 count bilan to'ldirilgan).
    public func recentDays(_ n: Int = 30) -> [DailyCount] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let all = history
        var result: [DailyCount] = []
        for i in stride(from: n - 1, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            if let found = all.first(where: { cal.isDate($0.day, inSameDayAs: day) }) {
                result.append(found)
            } else {
                result.append(DailyCount(day: day, count: 0))
            }
        }
        return result
    }

    public var last7Days: [DailyCount] { recentDays(7) }
    public var last30Days: [DailyCount] { recentDays(30) }
    public var weeklyAverage: Double {
        let counts = last7Days.map { $0.count }
        guard counts.count == 7 else { return 0 }
        return Double(counts.reduce(0, +)) / 7.0
    }
}