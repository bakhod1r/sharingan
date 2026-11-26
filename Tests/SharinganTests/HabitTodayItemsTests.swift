import XCTest
@testable import SharinganCore

final class HabitTodayItemsTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }()
    private func day(_ d: Int) -> Date { cal.date(from: DateComponents(year: 2024, month: 1, day: d))! }
    private var today: Date { day(10) }  // Wednesday

    private func input(_ id: UUID, _ s: HabitSchedule = .daily,
                       _ m: HabitCompletionMode = .manual, start: Int = 1, _ title: String = "h") -> HabitInput {
        HabitInput(taskID: id, title: title, habit: TaskHabit(schedule: s, mode: m, startDay: day(start)))
    }
    private func items(_ hs: [HabitInput], log: [FocusLogEntry] = [], checks: [HabitCheck] = []) -> [HabitTodayItem] {
        HabitEngine.todayItems(habits: hs, focusLog: log, checks: checks, today: today, calendar: cal)
    }

    func testDailyManualPendingAndDone() {
        let a = UUID(), b = UUID()
        let r = items([input(a, .daily, .manual, start: 1, "A"), input(b, .daily, .manual, start: 1, "B")], checks: [HabitCheck(day: today, taskID: b)])
        XCTAssertEqual(r.map(\.taskID), [a, b])
        XCTAssertFalse(r[0].isDone); XCTAssertEqual(r[0].progress, 0)
        XCTAssertTrue(r[0].isManual); XCTAssertNil(r[0].pomodoroTarget); XCTAssertEqual(r[0].pomodoroCount, 0)
        XCTAssertTrue(r[1].isDone); XCTAssertEqual(r[1].progress, 1); XCTAssertEqual(r[1].title, "B")
    }

    func testNotScheduledAndBeforeStartExcluded() {
        let a = UUID(), b = UUID()
        XCTAssertTrue(items([input(a, .weekdays([2, 3])), input(b, start: 12)]).isEmpty)
    }

    func testPomodoroProgress() {
        let a = UUID()
        let log = [FocusLogEntry(day: today, taskID: a, subtaskID: nil, title: "t", count: 1, seconds: 0)]
        let r = items([input(a, .daily, .pomodoro(target: 2))], log: log)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].progress, 0.5); XCTAssertEqual(r[0].pomodoroCount, 1)
        XCTAssertEqual(r[0].pomodoroTarget, 2); XCTAssertFalse(r[0].isDone); XCTAssertFalse(r[0].isManual)
    }

    func testTimesPerWeekQuotaMetExcludedButDoneTodayIncluded() {
        let a = UUID(), b = UUID()
        let met = [HabitCheck(day: day(8), taskID: a), HabitCheck(day: day(9), taskID: a)]
        XCTAssertTrue(items([input(a, .timesPerWeek(2))], checks: met).isEmpty)
        let doneToday = met.map { HabitCheck(day: $0.day, taskID: b) } + [HabitCheck(day: today, taskID: b)]
        let r = items([input(b, .timesPerWeek(2))], checks: doneToday)
        XCTAssertEqual(r.count, 1); XCTAssertTrue(r[0].isDone)
    }

    func testOrderPreserved() {
        let ids = (0..<4).map { _ in UUID() }
        let r = items(ids.map { input($0) }, checks: [HabitCheck(day: today, taskID: ids[1])])
        XCTAssertEqual(r.map(\.taskID), ids)
    }
}
