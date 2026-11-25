import Testing
import Foundation
@testable import SharinganCore

/// REVIEW 2.8 — cross-language keyword collisions must not eat English titles.
@Suite("Task input parser — keyword collisions")
struct ReviewParserTests {

    static var now: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 8; c.hour = 10; c.minute = 0
        return Calendar.current.date(from: c)!
    }

    private func parse(_ s: String) -> ParsedTaskInput {
        TaskInputParser.parse(s, now: Self.now)
    }

    @Test func leoNameStaysInTitle() {
        let p = parse("Call Leo")
        #expect(p.title == "Call Leo")
        #expect(p.dueDate == nil)
    }

    private func expectIntact(_ s: String) {
        let p = parse(s)
        #expect(p.title == s, "title eaten for \"\(s)\": got \"\(p.title)\"")
        #expect(p.dueDate == nil, "unexpected due date for \"\(s)\"")
        #expect(p.recurrence == Recurrence.none, "unexpected recurrence for \"\(s)\"")
    }

    @Test func englishTitlesWithForeignKeywordsStayIntact() {
        for s in ["Buy a safe", "Truth or dare", "Sore throat meds",
                  "Call her tag team", "Return the dun horse",
                  "Pick up her tag", "Watch them dare"] {
            expectIntact(s)
        }
    }

    @Test func markersDoNotCombineAcrossLanguages() {
        // Turkish "her" + German "tag" / "in" + Russian-ish units must not fire.
        expectIntact("Tell her tag 3 times")
        expectIntact("Ask her tage")
        // Same-language combinations still work.
        #expect(parse("every 3 days").recurrence == .everyNDays(3))
        #expect(parse("her gün").recurrence == .daily)
        #expect(parse("jeden tag").recurrence == .daily)
        let due = parse("in 2 hours").dueDate
        #expect(due != nil)
    }

    @Test func multiWordForeignFormsStillWork() {
        #expect(parse("da safe").dueDate != nil)
        #expect(parse("yau da dare").dueDate != nil)
    }

    @Test func japaneseKeywordsInsideWordsAreKept() {
        let p = parse("朝食を作る")          // "make breakfast" — 朝 is inside 朝食
        #expect(p.title == "朝食を作る")
        #expect(p.dueDate == nil)
        // Boundary matches still work.
        #expect(parse("明天开会").title == "开会")
        #expect(parse("水やり 毎日").recurrence == .daily)
    }

    @Test func uzbekHyphenDates() {
        let p = parse("5-mart hisobot")
        #expect(p.title == "hisobot")
        let cal = Calendar.current
        let d = p.dueDate.map { cal.dateComponents([.month, .day], from: $0) }
        #expect(d?.month == 3)
        #expect(d?.day == 5)
        #expect(parse("hisobot 15-iyul").dueDate != nil)
        // Plain hyphenated words are untouched.
        #expect(parse("e-mail 5-star review").title == "e-mail 5-star review")
    }
}
