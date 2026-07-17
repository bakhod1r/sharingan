import Foundation

/// Pure analytics over `[SessionRecord]` — no I/O, fully unit-tested. All
/// scores are 0–100 Ints, and `nil` when there is nothing to score (an empty
/// day is "no data", never "0/100").
public enum AnalyticsEngine {

    // MARK: - Focus Score

    /// Daily Focus Score: how much and how well you focused today.
    /// Weights: minutes vs goal 40, completion ratio 25, break compliance 20,
    /// deep blocks (longest run of consecutive completed pomodoros) 15.
    /// `dailyGoal` ≤ 0 falls back to 8 pomodoros' worth of `focusMinutes`.
    public static func focusScore(sessions: [SessionRecord], dailyGoal: Int,
                                  focusMinutes: Int) -> Int? {
        let focus = sessions.filter { $0.phase == .focus }
        guard !focus.isEmpty else { return nil }

        let goalPomodoros = dailyGoal > 0 ? dailyGoal : 8
        let goalSeconds = Double(goalPomodoros * max(1, focusMinutes) * 60)
        let focusSeconds = focus.reduce(0) { $0 + $1.seconds }
        let volume = min(1, focusSeconds / goalSeconds)

        let completedCount = focus.filter(\.completed).count
        let completion = Double(completedCount) / Double(focus.count)

        let breaks = sessions.filter { $0.phase.isBreak }
        let breakCompliance = breaks.isEmpty
            ? 1.0
            : Double(breaks.filter(\.completed).count) / Double(breaks.count)

        // Longest run of consecutive completed focus sessions, in start order.
        var longestRun = 0, run = 0
        for s in focus.sorted(by: { $0.start < $1.start }) {
            run = s.completed ? run + 1 : 0
            longestRun = max(longestRun, run)
        }
        let deepBlocks = min(1, Double(longestRun) / 4)

        let score = volume * 40 + completion * 25 + breakCompliance * 20
            + deepBlocks * 15
        return Int(score.rounded())
    }

    // MARK: - Consistency Score

    /// How closely today followed the plan and the usual rhythm.
    /// Weights: planned-task ratio 40 (no plan ⇒ neutral 0.7), start-hour
    /// regularity vs the median first-start of `recentDays` 30 (full credit
    /// within ±1 h, fading to zero at ±4 h; <3 prior days ⇒ neutral 0.7),
    /// streak 30 (a full week caps it).
    public static func consistencyScore(sessions: [SessionRecord],
                                        recentDays: [[SessionRecord]],
                                        plannedDone: Int, plannedTotal: Int,
                                        streakDays: Int) -> Int? {
        let focus = sessions.filter { $0.phase == .focus }
        guard !focus.isEmpty else { return nil }

        let plan = plannedTotal > 0
            ? Double(plannedDone) / Double(plannedTotal)
            : 0.7

        let priorStarts = recentDays.compactMap { day in
            day.filter { $0.phase == .focus }.map(\.start).min()
        }
        let regularity: Double
        if priorStarts.count >= 3, let todayStart = focus.map(\.start).min() {
            let hours = priorStarts.map(fractionalHour).sorted()
            let median = hours[hours.count / 2]
            let delta = abs(fractionalHour(of: todayStart) - median)
            regularity = delta <= 1 ? 1 : max(0, 1 - (delta - 1) / 3)
        } else {
            regularity = 0.7
        }

        let streak = min(1, Double(streakDays) / 7)

        let score = plan * 40 + regularity * 30 + streak * 30
        return Int(score.rounded())
    }

    private static func fractionalHour(of date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
    }

    // MARK: - Filtering

    /// Narrows a session list before scoring/charting. `completedOnly` drops
    /// abandoned (skipped/stopped) sessions; `allowedTaskIDs` (nil = no
    /// attribution filter) keeps only sessions credited to one of those tasks —
    /// sessions with no task, and tasks outside the set, drop out.
    public static func filter(sessions: [SessionRecord], completedOnly: Bool,
                              allowedTaskIDs: Set<UUID>?) -> [SessionRecord] {
        sessions.filter { s in
            if completedOnly && !s.completed { return false }
            if let allowed = allowedTaskIDs {
                guard let id = s.taskID, allowed.contains(id) else { return false }
            }
            return true
        }
    }

    /// Completed focus sessions per start-day — the heatmap's series when a
    /// filter is active (the aggregate `PomodoroStats.history` can't be
    /// narrowed by task/completion).
    public static func dailyCounts(from sessions: [SessionRecord]) -> [DailyCount] {
        let cal = Calendar.current
        var byDay: [Date: Int] = [:]
        for s in sessions where s.phase == .focus && s.completed {
            byDay[cal.startOfDay(for: s.start), default: 0] += 1
        }
        return byDay.map { DailyCount(day: $0.key, count: $0.value) }
            .sorted { $0.day < $1.day }
    }

    /// Mean of the non-nil scores, rounded; nil when every day is nil.
    public static func average(_ scores: [Int?]) -> Int? {
        let vals = scores.compactMap { $0 }
        guard !vals.isEmpty else { return nil }
        return Int((Double(vals.reduce(0, +)) / Double(vals.count)).rounded())
    }

    // MARK: - Heatmap grid

    /// Chronological days → GitHub-style columns: one array per calendar week,
    /// 7 slots each, Monday first; `nil` pads days outside the input range so
    /// the view can render a fixed grid without date math.
    public static func heatmapWeeks(days: [DailyCount]) -> [[DailyCount?]] {
        guard !days.isEmpty else { return [] }
        let cal = Calendar.current
        var weeks: [[DailyCount?]] = []
        var current = [DailyCount?](repeating: nil, count: 7)
        var touched = false
        for d in days {
            let slot = (cal.component(.weekday, from: d.day) + 5) % 7   // 0 = Mon
            if touched, slot == 0 {
                weeks.append(current)
                current = [DailyCount?](repeating: nil, count: 7)
            }
            current[slot] = d
            touched = true
        }
        weeks.append(current)
        return weeks
    }

    // MARK: - Focus load

    /// 24 buckets of focus seconds for one day's sessions ("diqqat
    /// cho'qqilari"). A session spanning an hour boundary is split
    /// proportionally; breaks don't count as load.
    public static func hourlyLoad(sessions: [SessionRecord]) -> [TimeInterval] {
        var buckets = [TimeInterval](repeating: 0, count: 24)
        let cal = Calendar.current
        for s in sessions where s.phase == .focus {
            var cursor = s.start
            while cursor < s.end {
                let hour = cal.component(.hour, from: cursor)
                let hourStart = cal.date(bySettingHour: hour, minute: 0, second: 0,
                                         of: cursor) ?? cursor
                let hourEnd = hourStart.addingTimeInterval(3600)
                let sliceEnd = min(hourEnd, s.end)
                buckets[hour] += sliceEnd.timeIntervalSince(cursor)
                cursor = sliceEnd
            }
        }
        return buckets
    }
}
