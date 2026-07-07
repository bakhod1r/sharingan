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
    /// Completed focus sessions bucketed by hour of day (24 entries) — powers the
    /// "best focus hours" chart.
    public var hourCounts: [Int] = Array(repeating: 0, count: 24)

    public init() {}

    // Defensive decoding so adding fields (lastCountedDay, hourCounts) never
    // fails an older saved stats blob — which would silently reset the user's
    // history and streak.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        completedFocus = try c.decodeIfPresent(Int.self, forKey: .completedFocus) ?? 0
        completedToday = try c.decodeIfPresent(Int.self, forKey: .completedToday) ?? 0
        streakDays = try c.decodeIfPresent(Int.self, forKey: .streakDays) ?? 0
        streak = try c.decodeIfPresent(StreakStore.self, forKey: .streak) ?? .init()
        history = try c.decodeIfPresent([DailyCount].self, forKey: .history) ?? []
        lastCountedDay = try c.decodeIfPresent(Date.self, forKey: .lastCountedDay)
        let hc = try c.decodeIfPresent([Int].self, forKey: .hourCounts) ?? []
        hourCounts = hc.count == 24 ? hc : Array(repeating: 0, count: 24)
    }

    /// Hour (0–23) with the most completed focus sessions, if any.
    public var bestFocusHour: Int? {
        guard let peak = hourCounts.max(), peak > 0 else { return nil }
        return hourCounts.firstIndex(of: peak)
    }

    public mutating func registerFocusCompletion(on date: Date = Date()) {
        completedFocus += 1

        let hour = Calendar.current.component(.hour, from: date)
        if hourCounts.count == 24 { hourCounts[hour] += 1 }

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

    // MARK: - Weekly report

    /// Sum of completed focus sessions over a rolling day window, `start` (days
    /// ago, inclusive) to `end` (exclusive). e.g. 0..<7 is the last 7 days.
    public func total(fromDaysAgo start: Int, toDaysAgo end: Int,
                      now: Date = Date()) -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var sum = 0
        for i in start..<end {
            guard let day = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            sum += history.first(where: { cal.isDate($0.day, inSameDayAs: day) })?.count ?? 0
        }
        return sum
    }

    /// Completed focus sessions in the last 7 days.
    public func thisWeekTotal(now: Date = Date()) -> Int { total(fromDaysAgo: 0, toDaysAgo: 7, now: now) }
    /// Completed focus sessions in the 7 days before that.
    public func lastWeekTotal(now: Date = Date()) -> Int { total(fromDaysAgo: 7, toDaysAgo: 14, now: now) }

    /// Week-over-week change as a fraction (e.g. 0.2 = +20%). Returns nil when
    /// there is no prior-week baseline to compare against.
    public func weekOverWeekChange(now: Date = Date()) -> Double? {
        let last = lastWeekTotal(now: now)
        guard last > 0 else { return nil }
        return Double(thisWeekTotal(now: now) - last) / Double(last)
    }
}