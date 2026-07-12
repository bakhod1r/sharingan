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

    // MARK: - Multilingual dates (25 languages, all live at once)

    @Test func todayAcrossLanguages() throws {
        // English, Spanish, French, German, Russian, Turkish, Korean, Arabic,
        // Hindi, Indonesian (phrase), Swahili.
        for word in ["today", "hoy", "aujourd'hui", "heute", "сегодня",
                     "bugün", "오늘", "اليوم", "आज", "hari ini", "leo"] {
            let p = parse("thing \(word)")
            let due = try #require(p.dueDate, "no due for \(word)")
            #expect(Calendar.current.isDate(due, inSameDayAs: Self.now),
                    "‘\(word)’ should mean today")
        }
    }

    @Test func tomorrowAcrossLanguages() throws {
        let expected = Calendar.current.date(byAdding: .day, value: 1, to: Self.now)!
        // Uzbek, Spanish, French, German, Russian, Turkish, Korean, Portuguese,
        // Indonesian, Vietnamese (phrase), Italian.
        for word in ["ertaga", "mañana", "demain", "morgen", "завтра",
                     "yarın", "내일", "amanhã", "besok", "ngày mai", "domani"] {
            let p = parse("thing \(word)")
            let due = try #require(p.dueDate, "no due for \(word)")
            #expect(Calendar.current.isDate(due, inSameDayAs: expected),
                    "‘\(word)’ should mean tomorrow")
        }
    }

    @Test func dayAfterTomorrowAcrossLanguages() throws {
        let expected = Calendar.current.date(byAdding: .day, value: 2, to: Self.now)!
        // Uzbek, German, Spanish (phrase), Turkish (phrase), Italian, Korean,
        // Hindi, Russian.
        for word in ["indamon", "übermorgen", "pasado mañana", "öbür gün",
                     "dopodomani", "모레", "परसों", "послезавтра"] {
            let p = parse("thing \(word)")
            let due = try #require(p.dueDate, "no due for \(word)")
            #expect(Calendar.current.isDate(due, inSameDayAs: expected),
                    "‘\(word)’ should mean the day after tomorrow")
        }
    }

    @Test func yesterdayAcrossLanguages() throws {
        let expected = Calendar.current.date(byAdding: .day, value: -1, to: Self.now)!
        for word in ["yesterday", "kecha", "ayer", "hier", "вчера", "어제"] {
            let p = parse("thing \(word)")
            let due = try #require(p.dueDate, "no due for \(word)")
            #expect(Calendar.current.isDate(due, inSameDayAs: expected))
        }
    }

    @Test func nextWeekAcrossLanguages() throws {
        let expected = Calendar.current.date(byAdding: .day, value: 7, to: Self.now)!
        // English, Uzbek, German, Turkish, Korean.
        for phrase in ["next week", "keyingi hafta", "nächste woche",
                       "gelecek hafta", "다음 주"] {
            let p = parse("plan \(phrase)")
            let due = try #require(p.dueDate, "no due for \(phrase)")
            #expect(Calendar.current.isDate(due, inSameDayAs: expected))
            #expect(p.title == "plan")
        }
    }

    // MARK: - CJK (no spaces — substring scan)

    @Test func chineseTomorrowLiftedFromTitle() throws {
        // 明天 = tomorrow, 开会 = "meeting" — no spaces between them.
        let p = parse("明天开会")
        let due = try #require(p.dueDate)
        let expected = Calendar.current.date(byAdding: .day, value: 1, to: Self.now)!
        #expect(Calendar.current.isDate(due, inSameDayAs: expected))
        #expect(p.title == "开会")
    }

    @Test func japaneseTodayAndRecurrence() throws {
        #expect(parse("水やり 毎日").recurrence == .daily)     // "watering daily"
        let p = parse("今日 レポート")                          // "today report"
        let due = try #require(p.dueDate)
        #expect(Calendar.current.isDate(due, inSameDayAs: Self.now))
    }

    @Test func chineseRecurrenceWordStripped() {
        let p = parse("每天喝水")   // 每天 = daily, 喝水 = "drink water"
        #expect(p.recurrence == .daily)
        #expect(p.title == "喝水")
    }

    // MARK: - Recurrence in more languages + compositional

    @Test func recurrenceAcrossLanguages() {
        #expect(parse("gießen täglich").recurrence == .daily)        // German
        #expect(parse("review semanal").recurrence == .weekly)       // Spanish
        #expect(parse("отчёт ежемесячно").recurrence == .monthly(1)) // Russian
        #expect(parse("standup 平日").recurrence == .weekdays)        // Japanese
    }

    @Test func everyNDaysCompositional() {
        #expect(parse("water plants every 3 days").recurrence == .everyNDays(3))
        #expect(parse("sug'orish har 2 kunda").recurrence == .everyNDays(2))
        #expect(parse("clean every day").recurrence == .daily)
        #expect(parse("meet every week").recurrence == .weekly)
    }

    // MARK: - Relative offsets ("in N hours/days")

    @Test func relativeOffsetInHours() throws {
        let p = parse("call back in 2 hours")   // now = 10:00 → 12:00
        let due = try #require(p.dueDate)
        #expect(Calendar.current.component(.hour, from: due) == 12)
        #expect(Calendar.current.isDate(due, inSameDayAs: Self.now))
        #expect(p.title == "call back")
    }

    @Test func relativeOffsetInDays() throws {
        let p = parse("ship in 3 days")
        let due = try #require(p.dueDate)
        let expected = Calendar.current.date(byAdding: .day, value: 3, to: Self.now)!
        #expect(Calendar.current.isDate(due, inSameDayAs: expected))
        #expect(p.title == "ship")
    }

    @Test func bareMarkerStaysInTitle() {
        // "in" without a following number+unit must not be consumed.
        let p = parse("put files in the box")
        #expect(p.title == "put files in the box")
        #expect(p.dueDate == nil)
    }

    // MARK: - Priority words

    @Test func priorityWordsInferHigh() {
        #expect(parse("urgent buy milk").priority == .high)
        #expect(parse("muhim hisobot").priority == .high)   // Uzbek
        #expect(parse("dringend anrufen").priority == .high) // German
        let p = parse("urgent buy milk")
        #expect(p.title == "buy milk")
    }

    // MARK: - Registry integrity

    @Test func everyLanguageDefinesCoreConcepts() {
        for (idx, lang) in LocalizedKeywords.all.enumerated() {
            #expect(!lang.today.isEmpty, "language #\(idx) missing today")
            #expect(!lang.tomorrow.isEmpty, "language #\(idx) missing tomorrow")
            #expect(!lang.yesterday.isEmpty, "language #\(idx) missing yesterday")
            #expect(lang.weekdays.count == 7, "language #\(idx) needs 7 weekdays")
            #expect(lang.weekdays.allSatisfy { !$0.isEmpty },
                    "language #\(idx) has an empty weekday")
            #expect(!lang.daily.isEmpty, "language #\(idx) missing daily")
            #expect(!lang.weekly.isEmpty, "language #\(idx) missing weekly")
            #expect(!lang.monthly.isEmpty, "language #\(idx) missing monthly")
            #expect(!lang.priorityHigh.isEmpty, "language #\(idx) missing priority")
        }
    }

    @Test func topTwentyFiveLanguages() {
        #expect(LocalizedKeywords.all.count == 25)
    }

    // MARK: - Parts of day → clock time

    @Test func partsOfDaySetTheClock() throws {
        // "tomorrow evening" = tomorrow at 18:00 (day word + time word combine).
        let p = try #require(parse("meeting tomorrow evening").dueDate)
        let cal = Calendar.current
        let expectedDay = cal.date(byAdding: .day, value: 1, to: Self.now)!
        #expect(cal.isDate(p, inSameDayAs: expectedDay))
        #expect(cal.component(.hour, from: p) == 18)
    }

    @Test func tonightIsTodayAtEight() throws {
        let p = try #require(parse("call mom tonight").dueDate)  // now 10:00
        let cal = Calendar.current
        #expect(cal.isDate(p, inSameDayAs: Self.now))
        #expect(cal.component(.hour, from: p) == 20)
        #expect(parse("call mom tonight").title == "call mom")
    }

    @Test func partsOfDayAcrossLanguages() throws {
        let cal = Calendar.current
        // Uzbek "ertaga kechqurun" = tomorrow 18:00.
        let uz = try #require(parse("uchrashuv ertaga kechqurun").dueDate)
        #expect(cal.component(.hour, from: uz) == 18)
        // German "morgens" and French "midi".
        #expect(cal.component(.hour, from: try #require(parse("plan morgens").dueDate)) == 9)
        #expect(cal.component(.hour, from: try #require(parse("déjeuner midi").dueDate)) == 12)
    }

    // MARK: - next month / year, weekend

    @Test func nextMonthAndYear() throws {
        let cal = Calendar.current
        let m = try #require(parse("pay rent next month").dueDate)
        let expM = cal.date(byAdding: .month, value: 1, to: Self.now)!
        #expect(cal.isDate(m, inSameDayAs: expM))

        let y = try #require(parse("renew next year").dueDate)
        let expY = cal.date(byAdding: .year, value: 1, to: Self.now)!
        #expect(cal.isDate(y, inSameDayAs: expY))
        #expect(parse("pay rent next month").title == "pay rent")
    }

    @Test func weekendIsComingSaturday() throws {
        // Reference date is Wednesday 2026-07-08 → Saturday is 2026-07-11.
        let p = try #require(parse("relax weekend").dueDate)
        let cal = Calendar.current
        #expect(cal.component(.weekday, from: p) == 7)   // Saturday
    }

    @Test func nextMonthAcrossLanguages() throws {
        let cal = Calendar.current
        let expected = cal.date(byAdding: .month, value: 1, to: Self.now)!
        // Uzbek, German, Russian, Korean, Chinese (CJK).
        for phrase in ["keyingi oy", "nächsten monat", "следующий месяц",
                       "다음 달", "下个月"] {
            let due = try #require(parse("x \(phrase)").dueDate, "no due for \(phrase)")
            #expect(cal.isDate(due, inSameDayAs: expected), "‘\(phrase)’ should be next month")
        }
    }

    // MARK: - Month-name dates

    @Test func monthNameWithDayEitherOrder() throws {
        let cal = Calendar.current
        for input in ["party december 25", "party 25 december"] {
            let due = try #require(parse(input).dueDate, "no due for \(input)")
            let c = cal.dateComponents([.day, .month], from: due)
            #expect(c.day == 25)
            #expect(c.month == 12)
            #expect(parse(input).title == "party")
        }
    }

    @Test func monthNameOrdinalAndOtherLanguages() throws {
        let cal = Calendar.current
        // English ordinal.
        let en = try #require(parse("trip june 5th").dueDate)
        #expect(cal.component(.month, from: en) == 6)
        #expect(cal.component(.day, from: en) == 5)
        // Uzbek "5 mart", Russian "5 марта", German "5 dezember".
        #expect(cal.component(.month, from: try #require(parse("hisobot 5 mart").dueDate)) == 3)
        #expect(cal.component(.month, from: try #require(parse("отчёт 5 марта").dueDate)) == 3)
    }

    @Test func bareMonthNameStaysInTitle() {
        // "may" without an adjacent day number must not become a date.
        let p = parse("may the build pass")
        #expect(p.dueDate == nil)
        #expect(p.title == "may the build pass")
    }

    // MARK: - Relative offsets: month/year + postpositional

    @Test func offsetMonthsAndYears() throws {
        let cal = Calendar.current
        let m = try #require(parse("review in 2 months").dueDate)
        #expect(cal.isDate(m, inSameDayAs: cal.date(byAdding: .month, value: 2, to: Self.now)!))
    }

    @Test func postpositionalOffsets() throws {
        let cal = Calendar.current
        // Uzbek "2 soatdan keyin" and Turkish "2 saat sonra" = +2 hours (12:00).
        #expect(cal.component(.hour, from: try #require(parse("qo'ng'iroq 2 soatdan keyin").dueDate)) == 12)
        #expect(cal.component(.hour, from: try #require(parse("ara 2 saat sonra").dueDate)) == 12)
        #expect(parse("qo'ng'iroq 2 soatdan keyin").title == "qo'ng'iroq")
    }
}
