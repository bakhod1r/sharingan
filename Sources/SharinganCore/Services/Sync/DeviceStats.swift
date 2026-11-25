import Foundation

/// One Mac's own pomodoro counts, as published to the other Macs.
///
/// Why per-device counts instead of syncing the `PomodoroStats` blob: the blob
/// is a bundle of counters that only make sense as a running total on the Mac
/// that earned them, so any last-writer-wins or max-merge of it would erase one
/// Mac's work. A record per device (recordName = device id) has exactly one
/// writer, so there is nothing to conflict; every Mac sums the records it holds.
///
/// Each Mac credits only the sessions it OWNS (a mirrored follower never
/// credits — see `PomodoroTimer.phaseComplete`), so one real pomodoro is in
/// exactly one device's counts and the sum is the true fleet total.
public struct DeviceDailyStats: Codable, Equatable, Sendable, SyncableRecord {
    public var deviceID: String
    public var deviceName: String
    /// Completed focus sessions per calendar day (this Mac only).
    public var days: [DailyCount]
    /// Completed focus sessions bucketed by hour of day (24 entries).
    public var hourCounts: [Int]

    public init(deviceID: String, deviceName: String,
                days: [DailyCount], hourCounts: [Int]) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.days = days.sorted { $0.day < $1.day }
        self.hourCounts = hourCounts.count == 24 ? hourCounts : Array(repeating: 0, count: 24)
    }

    public init(from stats: PomodoroStats, deviceID: String, deviceName: String) {
        self.init(deviceID: deviceID, deviceName: deviceName,
                  days: stats.history, hourCounts: stats.hourCounts)
    }

    public static func recordName(forDevice id: String) -> String { "stats|\(id)" }
    public var recordName: String { Self.recordName(forDevice: deviceID) }
    public var contentHash: String { SyncShadow.hash(self) }
}

extension PomodoroStats {
    /// This Mac's counters folded together with the other Macs' published
    /// counts, for DISPLAY. The local counters themselves are never touched —
    /// crediting, long-break cadence and goal detection keep reading `self`.
    /// With no remote devices this returns `self` unchanged, so sync-off
    /// behaviour is byte-identical to before.
    public func combined(with remotes: [DeviceDailyStats],
                         now: Date = Date()) -> PomodoroStats {
        guard !remotes.isEmpty else { return self }
        let cal = Calendar.current
        var out = self

        var byDay: [Date: Int] = [:]
        for d in history { byDay[cal.startOfDay(for: d.day), default: 0] += d.count }
        var remoteTotal = 0
        for remote in remotes {
            for d in remote.days {
                byDay[cal.startOfDay(for: d.day), default: 0] += d.count
                remoteTotal += d.count
            }
        }
        out.history = byDay.map { DailyCount(day: $0.key, count: $0.value) }
            .sorted { $0.day < $1.day }

        out.completedFocus = completedFocus + remoteTotal
        for remote in remotes {
            for h in 0..<24 { out.hourCounts[h] += remote.hourCounts[h] }
        }

        let today = cal.startOfDay(for: now)
        out.completedToday = byDay[today] ?? 0
        out.lastCountedDay = today

        // Streak from the combined history: consecutive active days ending
        // today, or yesterday while today has no session yet (a streak is not
        // broken until a whole day has passed without one).
        let active = Set(byDay.filter { $0.value > 0 }.keys)
        var cursor = active.contains(today) ? today
            : cal.date(byAdding: .day, value: -1, to: today) ?? today
        var run = 0
        while active.contains(cursor) {
            run += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        out.streak.currentStreak = run
        out.streak.longestStreak = max(streak.longestStreak, Self.longestRun(in: active, calendar: cal))
        out.streak.lastCompletedDay = active.max() ?? streak.lastCompletedDay
        out.streakDays = run
        return out
    }

    private static func longestRun(in days: Set<Date>, calendar cal: Calendar) -> Int {
        var best = 0
        for d in days {
            // Only count from the first day of a run.
            if let prev = cal.date(byAdding: .day, value: -1, to: d), days.contains(prev) { continue }
            var len = 0, cur = d
            while days.contains(cur) {
                len += 1
                guard let next = cal.date(byAdding: .day, value: 1, to: cur) else { break }
                cur = next
            }
            best = max(best, len)
        }
        return best
    }
}
