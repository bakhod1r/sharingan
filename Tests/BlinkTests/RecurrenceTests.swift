import Testing
import Foundation
@testable import BlinkCore

@Suite("Recurrence")
struct RecurrenceTests {

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 14) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = 30
        return Calendar.current.date(from: c)!
    }

    // MARK: - nextDate math

    @Test func everyNDaysAddsN() {
        let start = date(2026, 7, 8)
        let next = Recurrence.everyNDays(3).nextDate(after: start)
        #expect(Calendar.current.isDate(next, inSameDayAs: date(2026, 7, 11)))
        // Time of day is preserved.
        #expect(Calendar.current.component(.hour, from: next) == 14)
    }

    @Test func monthlyMovesToNextMonthSameDay() {
        let start = date(2026, 7, 15)
        let next = Recurrence.monthly(15).nextDate(after: start)
        #expect(Calendar.current.isDate(next, inSameDayAs: date(2026, 8, 15)))
        #expect(Calendar.current.component(.hour, from: next) == 14)
    }

    @Test func monthlyPicksLaterDayInSameMonth() {
        // Due the 20th, today is the 10th — next occurrence is THIS month.
        let start = date(2026, 7, 10)
        let next = Recurrence.monthly(20).nextDate(after: start)
        #expect(Calendar.current.isDate(next, inSameDayAs: date(2026, 7, 20)))
    }

    @Test func monthlyClampsShortMonths() {
        // Day 31 from January → February clamps to the 28th (2027 not a leap year).
        let start = date(2027, 1, 31)
        let next = Recurrence.monthly(31).nextDate(after: start)
        #expect(Calendar.current.isDate(next, inSameDayAs: date(2027, 2, 28)))
    }

    @Test func existingCasesStillWork() {
        let wed = date(2026, 7, 8)   // Wednesday
        #expect(Calendar.current.isDate(Recurrence.daily.nextDate(after: wed),
                                        inSameDayAs: date(2026, 7, 9)))
        #expect(Calendar.current.isDate(Recurrence.weekly.nextDate(after: wed),
                                        inSameDayAs: date(2026, 7, 15)))
        let fri = date(2026, 7, 10)  // Friday → weekdays skips to Monday
        #expect(Calendar.current.isDate(Recurrence.weekdays.nextDate(after: fri),
                                        inSameDayAs: date(2026, 7, 13)))
    }

    // MARK: - Coding

    @Test func newCasesRoundTrip() throws {
        for r in [Recurrence.everyNDays(3), .monthly(15), .daily, .none] {
            let data = try JSONEncoder().encode(r)
            let back = try JSONDecoder().decode(Recurrence.self, from: data)
            #expect(back == r)
        }
    }

    @Test func oldRawStringsStillDecode() throws {
        for (raw, expected) in [("\"daily\"", Recurrence.daily),
                                ("\"weekdays\"", .weekdays),
                                ("\"weekly\"", .weekly),
                                ("\"none\"", .none)] {
            let back = try JSONDecoder().decode(Recurrence.self,
                                                from: raw.data(using: .utf8)!)
            #expect(back == expected)
        }
    }

    @Test func newCasesEncodeAsCompactStrings() throws {
        let data = try JSONEncoder().encode(Recurrence.everyNDays(3))
        #expect(String(data: data, encoding: .utf8) == "\"everyNDays:3\"")
        let data2 = try JSONEncoder().encode(Recurrence.monthly(15))
        #expect(String(data: data2, encoding: .utf8) == "\"monthly:15\"")
    }

    @Test func garbageDecodesToNone() throws {
        let back = try JSONDecoder().decode(Recurrence.self,
                                            from: "\"biweekly-ish\"".data(using: .utf8)!)
        #expect(back == .none)
    }

    @Test func labelsExist() {
        #expect(Recurrence.everyNDays(3).label == "Every 3 days")
        #expect(Recurrence.monthly(15).label == "Monthly (day 15)")
    }

    @Test func taskItemWithNewRecurrenceRoundTrips() throws {
        var t = TaskItem(title: "rent")
        t.recurrence = .monthly(1)
        let data = try JSONEncoder().encode(t)
        let back = try JSONDecoder().decode(TaskItem.self, from: data)
        #expect(back.recurrence == .monthly(1))
    }
}
