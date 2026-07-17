import Testing
import Foundation
@testable import SharinganCore

@Suite("Burnout detector")
struct BurnoutDetectorTests {
    private let cal = Calendar.current

    private func focus(day: Date, hour: Int, completed: Bool = true) -> SessionRecord {
        let start = cal.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        return SessionRecord(start: start, end: start.addingTimeInterval(1500),
                             phase: .focus, completed: completed, plannedSeconds: 1500)
    }
    private func brk(day: Date, hour: Int, completed: Bool) -> SessionRecord {
        let start = cal.date(bySettingHour: hour, minute: 30, second: 0, of: day)!
        return SessionRecord(start: start, end: start.addingTimeInterval(300),
                             phase: .shortBreak, completed: completed, plannedSeconds: 300)
    }

    @Test func calmWeekHasNoReasons() {
        let today = cal.startOfDay(for: Date())
        let sessions = (0..<3).map { focus(day: cal.date(byAdding: .day, value: -$0, to: today)!, hour: 10) }
        #expect(BurnoutDetector.evaluate(sessions: sessions).reasons.isEmpty)
    }

    @Test func hugeDayAndHeavyStreakTriggerWarning() {
        let today = cal.startOfDay(for: Date())
        var sessions: [SessionRecord] = []
        // 5 consecutive heavy days (8 each); one of them is huge (12).
        for back in 0..<5 {
            let day = cal.date(byAdding: .day, value: -back, to: today)!
            let count = back == 0 ? 12 : 8
            for h in 0..<count { sessions.append(focus(day: day, hour: 8 + h % 12)) }
        }
        let result = BurnoutDetector.evaluate(sessions: sessions)
        #expect(result.isWarning)
        #expect(result.reasons.count >= 2)
    }

    @Test func skippingBreaksIsAReason() {
        let today = cal.startOfDay(for: Date())
        let sessions = (0..<6).map { brk(day: today, hour: $0, completed: false) }
        let result = BurnoutDetector.evaluate(sessions: sessions)
        #expect(result.reasons.contains { $0.contains("skipping") })
    }

    @Test func longestConsecutiveRunCountsGaps() {
        let today = cal.startOfDay(for: Date())
        let d = { (n: Int) in self.cal.date(byAdding: .day, value: -n, to: today)! }
        // days 0,1,2 present; 4,5 present → longest run 3.
        let set: Set<Date> = [d(0), d(1), d(2), d(4), d(5)]
        #expect(BurnoutDetector.longestConsecutiveRun(days: set, cal: cal) == 3)
    }
}

@Suite("Smart suggestions")
struct SmartSuggestionsTests {
    @Test func surfacesBestHourAndWeekday() {
        var stats = PomodoroStats()
        stats.hourCounts[9] = 10                       // best hour = 9
        // Give a best weekday by registering completions on a known Monday.
        var mondayComps = DateComponents(); mondayComps.year = 2026; mondayComps.month = 7; mondayComps.day = 13
        let monday = Calendar.current.date(from: mondayComps)!  // 2026-07-13 is a Monday
        stats.history = [DailyCount(day: monday, count: 5)]
        let out = SmartSuggestions.insights(stats: stats, sessions: [], limit: 2)
        #expect(out.count == 2)
        #expect(out.contains { $0.contains("focus best") })
    }

    @Test func emptyDataYieldsNothing() {
        #expect(SmartSuggestions.insights(stats: PomodoroStats(), sessions: []).isEmpty)
    }
}
