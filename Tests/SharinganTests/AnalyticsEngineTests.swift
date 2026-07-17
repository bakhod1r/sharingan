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
}
