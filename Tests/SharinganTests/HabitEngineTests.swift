import XCTest
@testable import SharinganCore

final class HabitEngineTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2   // Monday
        return c
    }()
    private let id = UUID()
    // 2024-01-01 is a Monday; today = Wednesday 2024-01-10.
    private func day(_ d: Int) -> Date { cal.date(from: DateComponents(year: 2024, month: 1, day: d))! }
    private var today: Date { day(10) }

    private func habit(_ s: HabitSchedule = .daily, _ m: HabitCompletionMode = .manual, start: Int = 1) -> TaskHabit {
        TaskHabit(schedule: s, mode: m, startDay: day(start))
    }
    private func checks(_ days: [Int]) -> [HabitCheck] { days.map { HabitCheck(day: day($0), taskID: id) } }
    private func st(_ d: Int, _ h: TaskHabit, log: [FocusLogEntry] = [], checks c: [HabitCheck] = []) -> HabitDayStatus {
        HabitEngine.status(for: day(d), habit: h, taskID: id, focusLog: log, checks: c, today: today, calendar: cal)
    }
    private func cur(_ h: TaskHabit, log: [FocusLogEntry] = [], _ c: [HabitCheck] = []) -> Int {
        HabitEngine.currentStreak(habit: h, taskID: id, focusLog: log, checks: c, today: today, calendar: cal)
    }
    private func longest(_ h: TaskHabit, _ c: [HabitCheck]) -> Int {
        HabitEngine.longestStreak(habit: h, taskID: id, focusLog: [], checks: c, today: today, calendar: cal)
    }
    private func entry(_ d: Int, count: Int, sub: UUID? = nil, task: UUID? = nil) -> FocusLogEntry {
        FocusLogEntry(day: day(d), taskID: task ?? id, subtaskID: sub, title: "t", count: count, seconds: 0)
    }

    func testPomodoroThresholdAndSubtaskRowsIgnored() {
        let h = habit(.daily, .pomodoro(target: 3))
        XCTAssertEqual(st(5, h, log: [entry(5, count: 2)]), .missed)
        XCTAssertEqual(st(5, h, log: [entry(5, count: 3)]), .done)
        XCTAssertEqual(st(5, h, log: [entry(5, count: 1), entry(5, count: 5, sub: UUID())]), .missed)
        XCTAssertEqual(st(5, h, log: [entry(5, count: 9, task: UUID())]), .missed)
        XCTAssertEqual(st(10, h, log: [entry(10, count: 1)]), .pending)
    }

    func testPomodoroHabitDoneByManualCheck() {
        let h = habit(.daily, .pomodoro(target: 2))
        XCTAssertEqual(st(5, h), .missed)
        XCTAssertEqual(st(5, h, checks: checks([5])), .done)
        XCTAssertEqual(HabitEngine.progress(on: day(5), habit: h, taskID: id, focusLog: [], checks: checks([5]), calendar: cal), 1)
        XCTAssertEqual(HabitEngine.progress(on: day(5), habit: h, taskID: id, focusLog: [entry(5, count: 1)], checks: [], calendar: cal), 0.5)
        XCTAssertEqual(HabitEngine.progress(on: day(5), habit: h, taskID: id, focusLog: [], checks: [], calendar: cal), 0)
    }

    func testPomodoroStreakCountsCheckedDays() {
        let h = habit(.daily, .pomodoro(target: 2), start: 6)
        XCTAssertEqual(cur(h, log: [entry(6, count: 2)], checks([7, 8, 9])), 4)
        XCTAssertEqual(cur(h, log: [], checks([7, 8, 9])), 3)
    }

    func testManualChecksAndStatuses() {
        let h = habit(start: 3)
        XCTAssertEqual(st(2, h), .beforeStart)
        XCTAssertEqual(st(4, h, checks: checks([4])), .done)
        XCTAssertEqual(st(5, h, checks: checks([4])), .missed)
        XCTAssertEqual(st(10, h), .pending)
        XCTAssertEqual(st(11, h), .future)
        XCTAssertEqual(st(4, h, checks: [HabitCheck(day: day(4), taskID: UUID())]), .missed)
    }

    func testWeekdaysSkipUnscheduled() {
        let h = habit(.weekdays([2, 4]))   // Mon, Wed
        XCTAssertEqual(st(1, h), .missed)       // Mon
        XCTAssertEqual(st(2, h), .notScheduled) // Tue
        // Mon 1, Wed 3, Mon 8 done; Wed 10 pending -> unscheduled Tue/Thu etc. skipped
        XCTAssertEqual(cur(h, checks([1, 3, 8])), 3)
        XCTAssertEqual(cur(h, checks([1, 8])), 1)        // Wed 3 missed breaks after Mon 8
    }

    func testStreakAcrossPendingToday() {
        let h = habit()
        XCTAssertEqual(cur(h, checks([7, 8, 9])), 3)             // today pending: not broken
        XCTAssertEqual(cur(h, checks([7, 8, 9, 10])), 4)
        XCTAssertEqual(cur(h, checks([7, 8])), 0)                // yesterday missed
        XCTAssertEqual(longest(h, checks([1, 2, 3, 4, 6, 7])), 4)
    }

    func testTimesPerWeekStreak() {
        let h = habit(.timesPerWeek(2))
        // Week1 (Jan1-7): 2 done; week2 (Jan8-14, today Wed): 1 done, still reachable.
        XCTAssertEqual(cur(h, checks([1, 3, 8])), 1)
        XCTAssertEqual(cur(h, checks([1, 3, 8, 9])), 2)
        // Week 1 only one done -> missed; current week met.
        XCTAssertEqual(cur(h, checks([2, 8, 9])), 1)
        XCTAssertEqual(longest(h, checks([1, 3, 8, 9])), 2)
        // Never reachable once too few days left: Friday-today with 0 done and need 7.
        let strict = habit(.timesPerWeek(7))
        XCTAssertEqual(cur(strict, checks([])), 0)
    }

    func testCompletionRate() {
        let h = habit()
        let from = day(4), to = day(10)
        // days 4...9 scheduled (6), today pending excluded; 3 done
        let r = HabitEngine.completionRate(habit: h, taskID: id, focusLog: [], checks: checks([4, 5, 9]),
                                           from: from, to: to, today: today, calendar: cal)
        XCTAssertEqual(r, 0.5, accuracy: 0.0001)
        // Before start excluded.
        let h2 = habit(start: 8)
        let r2 = HabitEngine.completionRate(habit: h2, taskID: id, focusLog: [], checks: checks([8]),
                                            from: from, to: to, today: today, calendar: cal)
        XCTAssertEqual(r2, 1.0 / 2.0, accuracy: 0.0001)
        let t = HabitEngine.tally(habit: habit(start: 11), taskID: id, focusLog: [], checks: [], from: from, to: to, today: today, calendar: cal)
        XCTAssertEqual(t, HabitTally())
    }

    func testWeekdayRates() {
        let h = habit()
        let rates = HabitEngine.weekdayRates(habit: h, taskID: id, focusLog: [], checks: checks([1, 8, 2]),
                                             from: day(1), to: day(10), today: today, calendar: cal)
        XCTAssertEqual(rates[2] ?? -1, 1.0, accuracy: 0.0001)   // Mondays 1, 8 done
        XCTAssertEqual(rates[3] ?? -1, 0.5, accuracy: 0.0001)   // Tuesdays 2 done, 9 missed
    }

    func testReportAggregates() {
        let h = habit()
        let input = HabitInput(taskID: id, title: "Read", habit: h)
        let rep = HabitReport.make(habits: [input], focusLog: [], checks: checks([7, 8, 9, 10]),
                                   days: 7, today: today, calendar: cal)
        XCTAssertEqual(rep.rows.count, 1)
        XCTAssertEqual(rep.bestCurrentStreak, 4)
        XCTAssertEqual(rep.bestStreakEye, .tomoe2)
        XCTAssertEqual(rep.totalDone, 4)
        XCTAssertEqual(rep.overallRate, 4.0 / 7.0, accuracy: 0.0001)
        XCTAssertNotNil(rep.strongestWeekday)
        XCTAssertEqual(rep.rows[0].longestStreak, 4)
        let empty = HabitReport.make(habits: [], focusLog: [], checks: [], days: 7, today: today, calendar: cal)
        XCTAssertEqual(empty.overallRate, 0); XCTAssertNil(empty.strongestWeekday)
    }

    func testPendingToday() {
        let h = habit()
        XCTAssertTrue(HabitEngine.isPendingToday(habit: h, taskID: id, focusLog: [], checks: [], today: today, calendar: cal))
        XCTAssertFalse(HabitEngine.isPendingToday(habit: h, taskID: id, focusLog: [], checks: checks([10]), today: today, calendar: cal))
        let w = habit(.timesPerWeek(2))
        XCTAssertFalse(HabitEngine.isPendingToday(habit: w, taskID: id, focusLog: [], checks: checks([8, 9]), today: today, calendar: cal))
    }

    // MARK: Forgiving eye

    func testEyeOneMissDropsOneStageTwoResetsToDormant() {
        let sevenDone = [Bool](repeating: true, count: 7)           // 3 tomoe
        XCTAssertEqual(HabitEngine.eyeStage(results: sevenDone), .tomoe3)
        XCTAssertEqual(HabitEngine.eyeStage(results: sevenDone + [false]), .tomoe2)
        XCTAssertEqual(HabitEngine.eyeStage(results: sevenDone + [false, false]), .dormant)
        // Recovery after a single miss keeps the floor until streak catches up.
        XCTAssertEqual(HabitEngine.eyeStage(results: sevenDone + [false, true]), .tomoe2)
        // A done in between clears the consecutive-miss count.
        XCTAssertEqual(HabitEngine.eyeStage(results: sevenDone + [false, true, false]), .tomoe1)
        XCTAssertEqual(HabitEngine.eyeStage(results: []), .dormant)
        XCTAssertEqual(HabitEngine.eyeStage(results: [false]), .dormant)
    }

    func testEyeIsForgivingButStreakStaysHonest() {
        let h = habit()
        let c = checks([1, 2, 3, 4, 5, 6, 7, 9])   // Jan 8 missed, 9 done, 10 pending
        XCTAssertEqual(cur(h, c), 1)
        XCTAssertEqual(HabitEngine.eyeStage(habit: h, taskID: id, focusLog: [], checks: c, today: today, calendar: cal), .tomoe2)
    }

    func testMonthlyRatesLastMonthsOldestFirst() {
        let h = habit()          // started Jan 1
        let input = HabitInput(taskID: id, title: "R", habit: h)
        // Jan 1..9 scheduled (today pending excluded); 3 done.
        let m = HabitEngine.monthlyRates(habits: [input], focusLog: [], checks: checks([1, 2, 3]),
                                         months: 3, today: today, calendar: cal)
        XCTAssertEqual(m.count, 3)
        XCTAssertEqual(m.map { cal.component(.month, from: $0.monthStart) }, [11, 12, 1])
        XCTAssertEqual(m[0].tally, HabitTally())            // before start
        XCTAssertEqual(m[1].tally, HabitTally())
        XCTAssertEqual(m[2].tally, HabitTally(done: 3, scheduled: 9))
        XCTAssertEqual(m[2].rate, 3.0 / 9.0, accuracy: 0.0001)
        let rep = HabitReport.make(habits: [input], focusLog: [], checks: checks([1]), days: 7, today: today, calendar: cal)
        XCTAssertEqual(rep.monthlyRates.count, 6)
        XCTAssertEqual(HabitEngine.monthlyRates(habits: [], focusLog: [], checks: [], months: 0, today: today, calendar: cal), [])
    }
}
