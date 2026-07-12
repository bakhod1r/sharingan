import Testing
import Foundation
@testable import SharinganCore

@Suite("Task input parser")
struct TaskInputParserTests {

    /// Fixed reference: Wednesday 2026-07-08 10:00 local.
    static var now: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 8; c.hour = 10; c.minute = 0
        return Calendar.current.date(from: c)!
    }

    private func parse(_ s: String) -> ParsedTaskInput {
        TaskInputParser.parse(s, now: Self.now)
    }

    // MARK: - Plain title

    @Test func plainTitlePassesThrough() {
        let p = parse("write the report")
        #expect(p.title == "write the report")
        #expect(p.tags.isEmpty)
        #expect(p.project == nil)
        #expect(p.priority == .none)
        #expect(p.dueDate == nil)
        #expect(p.estimatedPomodoros == nil)
        #expect(p.recurrence == Recurrence.none)
    }

    // MARK: - Tags / project / priority / estimate

    @Test func tagsAreExtracted() {
        let p = parse("hisobot yozish #ish #deep-work")
        #expect(p.title == "hisobot yozish")
        #expect(p.tags == ["ish", "deep-work"])
    }

    @Test func projectIsExtracted() {
        let p = parse("fix parser @blink")
        #expect(p.title == "fix parser")
        #expect(p.project == "blink")
    }

    @Test func firstProjectWins() {
        let p = parse("thing @alpha @beta")
        #expect(p.project == "alpha")
        #expect(p.title == "thing")
    }

    @Test func priorityToken() {
        #expect(parse("urgent thing p1").priority == .high)
        #expect(parse("p2 medium thing").priority == .medium)
        #expect(parse("p3 low thing").priority == .low)
        #expect(parse("nothing p4").priority == TaskPriority.none)
        // Not a standalone word — stays in the title.
        let p = parse("upgrade p10 board")
        #expect(p.priority == TaskPriority.none)
        #expect(p.title == "upgrade p10 board")
    }

    @Test func estimateToken() {
        let p = parse("big feature ~3")
        #expect(p.estimatedPomodoros == 3)
        #expect(p.title == "big feature")
    }

    // MARK: - Dates

    @Test func todayAndBugun() throws {
        for word in ["today", "bugun"] {
            let p = parse("thing \(word)")
            let due = try #require(p.dueDate)
            #expect(Calendar.current.isDate(due, inSameDayAs: Self.now))
            #expect(p.title == "thing")
        }
    }

    @Test func tomorrowAndErtaga() throws {
        for word in ["tomorrow", "ertaga"] {
            let p = parse("thing \(word)")
            let due = try #require(p.dueDate)
            let expected = Calendar.current.date(byAdding: .day, value: 1, to: Self.now)!
            #expect(Calendar.current.isDate(due, inSameDayAs: expected))
        }
    }

    @Test func weekdayNamesPickNextOccurrence() throws {
        // Reference date is a Wednesday; "friday"/"juma" = +2 days.
        for word in ["friday", "juma"] {
            let p = parse("review \(word)")
            let due = try #require(p.dueDate)
            let expected = Calendar.current.date(byAdding: .day, value: 2, to: Self.now)!
            #expect(Calendar.current.isDate(due, inSameDayAs: expected))
        }
        // A weekday that IS today rolls a full week ahead.
        for word in ["wednesday", "chorshanba"] {
            let p = parse("thing \(word)")
            let due = try #require(p.dueDate)
            let expected = Calendar.current.date(byAdding: .day, value: 7, to: Self.now)!
            #expect(Calendar.current.isDate(due, inSameDayAs: expected))
        }
    }

    @Test func numericDayMonth() throws {
        let p = parse("pay rent 12.08")
        let due = try #require(p.dueDate)
        let c = Calendar.current.dateComponents([.day, .month, .year], from: due)
        #expect(c.day == 12)
        #expect(c.month == 8)
        #expect(c.year == 2026)
        #expect(p.title == "pay rent")
    }

    @Test func dateWithNoTimeDefaultsToNine() throws {
        let p = parse("thing tomorrow")
        let due = try #require(p.dueDate)
        let c = Calendar.current.dateComponents([.hour, .minute], from: due)
        #expect(c.hour == 9)
        #expect(c.minute == 0)
    }

    @Test func explicitTimeCombinesWithDate() throws {
        let p = parse("meeting ertaga 15:00")
        let due = try #require(p.dueDate)
        let cal = Calendar.current
        let expectedDay = cal.date(byAdding: .day, value: 1, to: Self.now)!
        #expect(cal.isDate(due, inSameDayAs: expectedDay))
        let c = cal.dateComponents([.hour, .minute], from: due)
        #expect(c.hour == 15)
        #expect(c.minute == 0)
    }

    @Test func bareTimeTodayIfFuture() throws {
        let p = parse("call mom 5pm")   // now is 10:00, 17:00 is later today
        let due = try #require(p.dueDate)
        let cal = Calendar.current
        #expect(cal.isDate(due, inSameDayAs: Self.now))
        #expect(cal.component(.hour, from: due) == 17)
        #expect(p.title == "call mom")
    }

    @Test func barePastTimeRollsToTomorrow() throws {
        let p = parse("standup 9:00")   // 09:00 already passed (now 10:00)
        let due = try #require(p.dueDate)
        let cal = Calendar.current
        let expected = cal.date(byAdding: .day, value: 1, to: Self.now)!
        #expect(cal.isDate(due, inSameDayAs: expected))
        #expect(cal.component(.hour, from: due) == 9)
    }

    // MARK: - Recurrence

    @Test func recurrenceWords() {
        #expect(parse("water plants daily").recurrence == .daily)
        #expect(parse("sug'orish har kuni").recurrence == .daily)
        #expect(parse("standup weekdays").recurrence == .weekdays)
        #expect(parse("standup ish kunlari").recurrence == .weekdays)
        #expect(parse("review weekly").recurrence == .weekly)
        #expect(parse("review har hafta").recurrence == .weekly)
    }

    @Test func recurrenceStripsFromTitle() {
        let p = parse("water plants daily")
        #expect(p.title == "water plants")
    }

    // MARK: - Escape hatch

    @Test func leadingBackslashDisablesParsing() {
        let p = parse(#"\buy p1 sticker #not-a-tag tomorrow"#)
        #expect(p.title == "buy p1 sticker #not-a-tag tomorrow")
        #expect(p.priority == TaskPriority.none)
        #expect(p.tags.isEmpty)
        #expect(p.dueDate == nil)
    }

    // MARK: - Kitchen sink

    @Test func fullExample() throws {
        let p = parse("ertaga 15:00 p1 #ish @blink ~2 hisobot yozish")
        #expect(p.title == "hisobot yozish")
        #expect(p.tags == ["ish"])
        #expect(p.project == "blink")
        #expect(p.priority == .high)
        #expect(p.estimatedPomodoros == 2)
        let due = try #require(p.dueDate)
        let cal = Calendar.current
        let expectedDay = cal.date(byAdding: .day, value: 1, to: Self.now)!
        #expect(cal.isDate(due, inSameDayAs: expectedDay))
        #expect(cal.component(.hour, from: due) == 15)
    }

    @Test func whitespaceOnlyGivesEmptyTitle() {
        let p = parse("   ")
        #expect(p.title.isEmpty)
    }
}
