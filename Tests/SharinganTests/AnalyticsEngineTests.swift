import Testing
import Foundation
@testable import SharinganCore

@Suite("Analytics engine")
struct AnalyticsEngineTests {
    private let day = Calendar.current.startOfDay(for: Date())

    private func focus(hour: Double, minutes: Double = 25,
                       completed: Bool = true) -> SessionRecord {
        let start = day.addingTimeInterval(hour * 3600)
        return SessionRecord(start: start,
                             end: start.addingTimeInterval(minutes * 60),
                             phase: .focus, completed: completed,
                             plannedSeconds: 25 * 60)
    }

    private func brk(hour: Double, completed: Bool = true) -> SessionRecord {
        let start = day.addingTimeInterval(hour * 3600)
        return SessionRecord(start: start, end: start.addingTimeInterval(300),
                             phase: .shortBreak, completed: completed,
                             plannedSeconds: 300)
    }

    // MARK: Focus score

    @Test func emptyDayHasNoScore() {
        #expect(AnalyticsEngine.focusScore(sessions: [], dailyGoal: 8,
                                           focusMinutes: 25) == nil)
        #expect(AnalyticsEngine.consistencyScore(sessions: [], recentDays: [],
                                                 plannedDone: 0, plannedTotal: 0,
                                                 streakDays: 0) == nil)
    }

    @Test func perfectDayScoresHigh() {
        // 8 completed pomodoros (goal met), all breaks taken, 4+ deep run.
        var sessions: [SessionRecord] = []
        for i in 0..<8 {
            sessions.append(focus(hour: 9 + Double(i) * 0.6))
            sessions.append(brk(hour: 9.45 + Double(i) * 0.6))
        }
        let score = AnalyticsEngine.focusScore(sessions: sessions, dailyGoal: 8,
                                               focusMinutes: 25)
        #expect(score != nil && score! >= 90)
    }

    @Test func allAbandonedDayScoresLow() {
        let sessions = [focus(hour: 9, completed: false),
                        focus(hour: 10, completed: false),
                        focus(hour: 11, completed: false)]
        let score = AnalyticsEngine.focusScore(sessions: sessions, dailyGoal: 8,
                                               focusMinutes: 25)
        #expect(score != nil && score! < 40)
    }

    @Test func breakOnlyDayHasNoScore() {
        #expect(AnalyticsEngine.focusScore(sessions: [brk(hour: 9)],
                                           dailyGoal: 8, focusMinutes: 25) == nil)
    }

    // MARK: Consistency score

    @Test func consistencyNeutralWithoutPlanOrHistory() {
        // One focus session, no planned tasks, no prior days: neutral plan
        // (0.7×40) + neutral regularity (0.7×30) + zero streak = 49.
        let score = AnalyticsEngine.consistencyScore(
            sessions: [focus(hour: 9)], recentDays: [],
            plannedDone: 0, plannedTotal: 0, streakDays: 0)
        #expect(score == 49)
    }

    @Test func consistencyRewardsPlanStreakAndRegularity() {
        let history = (1...5).map { _ in [focus(hour: 9)] }
        let score = AnalyticsEngine.consistencyScore(
            sessions: [focus(hour: 9.5)], recentDays: history,
            plannedDone: 4, plannedTotal: 4, streakDays: 7)
        #expect(score == 100)   // plan 40 + regularity 30 (±1h) + streak 30
    }

    // MARK: Hourly load

    @Test func hourlyLoadSplitsAcrossHourBoundary() {
        // 10:30–11:30 → 1800 s in bucket 10, 1800 s in bucket 11.
        let load = AnalyticsEngine.hourlyLoad(sessions: [focus(hour: 10.5,
                                                               minutes: 60)])
        #expect(load.count == 24)
        #expect(abs(load[10] - 1800) < 1)
        #expect(abs(load[11] - 1800) < 1)
        #expect(load[9] == 0 && load[12] == 0)
    }

    @Test func hourlyLoadIgnoresBreaks() {
        let load = AnalyticsEngine.hourlyLoad(sessions: [brk(hour: 9)])
        #expect(load.allSatisfy { $0 == 0 })
    }

    // MARK: Heatmap grid

    @Test func heatmapWeeksPadsToMondayAndKeepsOrder() {
        let cal = Calendar.current
        // A Wednesday, so the first column needs 2 leading pads (Mon, Tue).
        var comps = DateComponents(); comps.year = 2026; comps.month = 7; comps.day = 15
        let wednesday = cal.date(from: comps)!
        let days = (0..<10).map { i in
            DailyCount(day: cal.date(byAdding: .day, value: i, to: wednesday)!,
                       count: i)
        }
        let weeks = AnalyticsEngine.heatmapWeeks(days: days)
        #expect(weeks.count == 2)
        #expect(weeks.allSatisfy { $0.count == 7 })
        #expect(weeks[0][0] == nil && weeks[0][1] == nil)     // Mon, Tue pads
        #expect(weeks[0][2]?.count == 0)                       // Wed 15th
        #expect(weeks[1][0]?.count == 5)                       // next Monday
        #expect(weeks[1][4]?.count == 9)                       // last day (Fri 24th)
        #expect(weeks[1][5] == nil && weeks[1][6] == nil)      // trailing pads
    }

    // MARK: Filtering

    @Test func filterDropsAbandonedWhenCompletedOnly() {
        let sessions = [focus(hour: 9), focus(hour: 10, completed: false)]
        let kept = AnalyticsEngine.filter(sessions: sessions, completedOnly: true,
                                          allowedTaskIDs: nil)
        #expect(kept.count == 1)
        #expect(kept.first?.completed == true)
    }

    @Test func filterNarrowsToAllowedTaskIDs() {
        let a = UUID(), b = UUID()
        var s1 = focus(hour: 9); s1.taskID = a
        var s2 = focus(hour: 10); s2.taskID = b
        var s3 = focus(hour: 11)          // no task attribution
        s3.taskID = nil
        let kept = AnalyticsEngine.filter(sessions: [s1, s2, s3],
                                          completedOnly: false,
                                          allowedTaskIDs: [a])
        #expect(kept.map(\.taskID) == [a])
    }

    @Test func filterWithNilAllowedKeepsEverything() {
        let sessions = [focus(hour: 9), focus(hour: 10, completed: false)]
        let kept = AnalyticsEngine.filter(sessions: sessions, completedOnly: false,
                                          allowedTaskIDs: nil)
        #expect(kept.count == 2)
    }

    @Test func dailyCountsBucketsCompletedFocusByStartDay() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        var y = SessionRecord(start: yesterday.addingTimeInterval(9 * 3600),
                              end: yesterday.addingTimeInterval(9 * 3600 + 1500),
                              phase: .focus, completed: true, plannedSeconds: 1500)
        y.taskID = nil
        let counts = AnalyticsEngine.dailyCounts(from: [
            y,
            focus(hour: 9),                       // today, completed
            focus(hour: 10, completed: false),    // today, abandoned → not counted
            brk(hour: 11)                         // break → not counted
        ])
        let byDay = Dictionary(uniqueKeysWithValues: counts.map { ($0.day, $0.count) })
        #expect(byDay[yesterday] == 1)
        #expect(byDay[today] == 1)
    }

    @Test func averageIgnoresNilDays() {
        #expect(AnalyticsEngine.average([80, nil, 90, nil]) == 85)
        #expect(AnalyticsEngine.average([nil, nil]) == nil)
        #expect(AnalyticsEngine.average([]) == nil)
    }

    // MARK: App totals

    @Test func appTotalsSumsAndSortsDescending() {
        var s1 = focus(hour: 9)
        s1.appUsage = ["com.a": 600, "com.b": 120]
        var s2 = focus(hour: 10)
        s2.appUsage = ["com.a": 300, "com.c": 0]   // zero-time app drops out
        let totals = AnalyticsEngine.appTotals(sessions: [s1, s2])
        #expect(totals.map(\.bundleID) == ["com.a", "com.b"])
        #expect(totals.first?.seconds == 900)
    }

    @Test func appTotalsEmptyWhenNoUsage() {
        #expect(AnalyticsEngine.appTotals(sessions: [focus(hour: 9)]).isEmpty)
    }

    @Test func appTotalsByTaskGroupsPerTaskAndDropsTaskless() {
        let t1 = UUID(), t2 = UUID()
        var a = focus(hour: 9); a.taskID = t1
        a.appUsage = ["com.a": 600, "com.b": 120]
        var b = focus(hour: 11); b.taskID = t1        // same task, another day-part
        b.appUsage = ["com.a": 300]
        var c = focus(hour: 13); c.taskID = t2
        c.appUsage = ["com.b": 480, "com.c": 0]        // zero-time app drops out
        var d = focus(hour: 15)                        // no taskID → excluded
        d.appUsage = ["com.a": 999]

        let byTask = AnalyticsEngine.appTotalsByTask(sessions: [a, b, c, d])
        #expect(byTask.count == 2)                      // taskless session ignored
        #expect(byTask[t1]?.map(\.bundleID) == ["com.a", "com.b"])  // summed + sorted
        #expect(byTask[t1]?.first?.seconds == 900)
        #expect(byTask[t2]?.map(\.bundleID) == ["com.b"])           // zero-time dropped
    }
}
