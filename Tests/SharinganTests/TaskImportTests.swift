import Testing
import Foundation
@testable import SharinganCore

@Suite("Task import (markdown + JSON)")
struct TaskImportTests {

    /// Fixed reference: Wednesday 2026-07-08 10:00 local.
    static var now: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 8; c.hour = 10; c.minute = 0
        return Calendar.current.date(from: c)!
    }

    private func parse(_ s: String) -> [TaskItem] {
        TaskImportParser.parse(s, now: Self.now)
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        return Calendar.current.date(from: c)!
    }

    // MARK: - Markdown: heading blocks

    @Test func headingLineUsesQuickAddTokens() {
        let tasks = parse("# Write report p1 #deep @blink ~4")
        #expect(tasks.count == 1)
        let t = tasks[0]
        #expect(t.title == "Write report")
        #expect(t.priority == .high)
        #expect(t.tags == ["deep"])
        #expect(t.project == "blink")
        #expect(t.estimatedPomodoros == 4)
    }

    @Test func keyValueLinesRefineTheTask() {
        let tasks = parse("""
        # Write report
        category: Work
        project: Sharingan
        tags: deep, focus
        priority: P1
        due: 2026-07-20 15:00
        planned: 2026-07-21
        estimate: 4
        repeat: weekly
        pomodoro: big
        """)
        #expect(tasks.count == 1)
        let t = tasks[0]
        #expect(t.category == "Work")
        #expect(t.project == "Sharingan")
        #expect(t.tags == ["deep", "focus"])
        #expect(t.priority == .high)
        #expect(t.dueDate == date(2026, 7, 20, 15, 0))
        #expect(t.plannedDate == Calendar.current.startOfDay(for: date(2026, 7, 21)))
        #expect(t.estimatedPomodoros == 4)
        #expect(t.recurrence == .weekly)
        #expect(t.pomodoroKind == .big)
    }

    @Test func uzbekKeyAliasesWork() {
        let tasks = parse("""
        # Hisobot yozish
        kategoriya: Ish
        loyiha: Sharingan
        teglar: chuqur
        muhimlik: P2
        muddat: 2026-07-20
        reja: 2026-07-21
        baho: 3
        takror: har kuni
        eslatma: tezroq tugatish kerak
        """)
        #expect(tasks.count == 1)
        let t = tasks[0]
        #expect(t.category == "Ish")
        #expect(t.project == "Sharingan")
        #expect(t.tags == ["chuqur"])
        #expect(t.priority == .medium)
        #expect(t.dueDate == date(2026, 7, 20))
        #expect(t.plannedDate == Calendar.current.startOfDay(for: date(2026, 7, 21)))
        #expect(t.estimatedPomodoros == 3)
        #expect(t.recurrence == .daily)
        #expect(t.notes == "tezroq tugatish kerak")
    }

    @Test func dateValuesAcceptNaturalLanguage() {
        // "tomorrow 15:00" through the quick-add parser.
        let tasks = parse("""
        # Thing
        due: tomorrow 15:00
        """)
        #expect(tasks[0].dueDate == date(2026, 7, 9, 15, 0))
    }

    @Test func subtasksWithEstimatesAndKinds() {
        let tasks = parse("""
        # Big feature
        - [ ] Plan it ~1
        - [x] Research
        - [ ] Build ~3 (big)
        """)
        let subs = tasks[0].subtasks
        #expect(subs.count == 3)
        #expect(subs[0].title == "Plan it")
        #expect(subs[0].estimatedPomodoros == 1)
        #expect(subs[1].isDone)
        #expect(subs[2].title == "Build")
        #expect(subs[2].estimatedPomodoros == 3)
        #expect(subs[2].pomodoroKind == .big)
    }

    @Test func freeTextBecomesNotes() {
        let tasks = parse("""
        # Thing
        First note line.
        Second line.
        """)
        #expect(tasks[0].notes == "First note line.\nSecond line.")
    }

    @Test func notesColonLinesAreNotSwallowedAsKeys() {
        // "Meeting: discuss X" — unknown key, stays a note.
        let tasks = parse("""
        # Thing
        Meeting: discuss X
        """)
        #expect(tasks[0].notes == "Meeting: discuss X")
    }

    @Test func multipleHeadingsMakeMultipleTasks() {
        let tasks = parse("""
        # First p1
        - [ ] a step

        ## Second ~2
        notes here
        """)
        #expect(tasks.count == 2)
        #expect(tasks[0].title == "First")
        #expect(tasks[0].priority == .high)
        #expect(tasks[0].subtasks.count == 1)
        #expect(tasks[1].title == "Second")
        #expect(tasks[1].estimatedPomodoros == 2)
        #expect(tasks[1].notes == "notes here")
    }

    @Test func doneFlagCompletesTheTask() {
        let tasks = parse("""
        # Old thing
        done: true
        """)
        #expect(tasks[0].isDone)
        #expect(tasks[0].completedAt != nil)
    }

    @Test func allTokenHeadingKeepsRawTitle() {
        // Parser would strip everything; the raw text must survive as title.
        let tasks = parse("# p1 #ish")
        #expect(tasks.count == 1)
        #expect(!tasks[0].title.isEmpty)
    }

    // MARK: - Markdown: headingless checklist

    @Test func headinglessChecklistMakesFlatTasks() {
        let tasks = parse("""
        - [ ] Buy milk #errands
        - [ ] Write report p1 ~4
          - [ ] outline ~1
          - [x] gather data
        - Call mom
        """)
        #expect(tasks.count == 3)
        #expect(tasks[0].title == "Buy milk")
        #expect(tasks[0].tags == ["errands"])
        #expect(tasks[1].title == "Write report")
        #expect(tasks[1].subtasks.count == 2)
        #expect(tasks[1].subtasks[1].isDone)
        #expect(tasks[2].title == "Call mom")
    }

    @Test func emptyAndGarbageYieldNothing() {
        #expect(parse("").isEmpty)
        #expect(parse("   \n\n  ").isEmpty)
    }

    // MARK: - JSON

    @Test func jsonArrayOfTasks() {
        let tasks = parse("""
        [
          {
            "title": "Write report",
            "category": "Work",
            "project": "Sharingan",
            "tags": ["deep", "focus"],
            "priority": "P1",
            "due": "2026-07-20 15:00",
            "planned": "2026-07-21",
            "estimate": 4,
            "repeat": "weekly",
            "pomodoro": "big",
            "notes": "multi\\nline",
            "subtasks": [
              {"title": "Plan", "estimate": 1},
              {"title": "Old", "done": true, "pomodoro": "small"},
              "Just a string step"
            ]
          },
          {"title": "Second"}
        ]
        """)
        #expect(tasks.count == 2)
        let t = tasks[0]
        #expect(t.title == "Write report")
        #expect(t.category == "Work")
        #expect(t.project == "Sharingan")
        #expect(t.tags == ["deep", "focus"])
        #expect(t.priority == .high)
        #expect(t.dueDate == date(2026, 7, 20, 15, 0))
        #expect(t.plannedDate == Calendar.current.startOfDay(for: date(2026, 7, 21)))
        #expect(t.estimatedPomodoros == 4)
        #expect(t.recurrence == .weekly)
        #expect(t.pomodoroKind == .big)
        #expect(t.notes == "multi\nline")
        #expect(t.subtasks.count == 3)
        #expect(t.subtasks[0].estimatedPomodoros == 1)
        #expect(t.subtasks[1].isDone)
        #expect(t.subtasks[1].pomodoroKind == .small)
        #expect(t.subtasks[2].title == "Just a string step")
    }

    @Test func jsonSingleObjectAndTasksWrapper() {
        #expect(parse(#"{"title": "Solo"}"#).count == 1)
        #expect(parse(#"{"tasks": [{"title": "A"}, {"title": "B"}]}"#).count == 2)
    }

    @Test func jsonLenientForms() {
        let tasks = parse("""
        [{
          "title": "Lenient",
          "tags": "one, two",
          "priority": 1,
          "due": "2026-07-20T15:00:00Z",
          "repeat": "har kuni"
        }]
        """)
        let t = tasks[0]
        #expect(t.tags == ["one", "two"])
        #expect(t.priority == .high)
        #expect(t.recurrence == .daily)
        let utc = ISO8601DateFormatter().date(from: "2026-07-20T15:00:00Z")
        #expect(t.dueDate == utc)
    }

    @Test func jsonInvalidYieldsNothing() {
        #expect(parse("{ not json").isEmpty)
        #expect(parse("[1, 2, 3]").isEmpty)
    }

    // MARK: - Pasted-JSON damage tolerance

    @Test func jsonInsideCodeFencesParses() {
        // The shape an LLM answer arrives in.
        let tasks = parse("""
        ```json
        [{"title": "Fenced", "priority": "P1"}]
        ```
        """)
        #expect(tasks.count == 1)
        #expect(tasks[0].title == "Fenced")
        #expect(tasks[0].priority == .high)
    }

    @Test func markdownInsideCodeFencesParses() {
        let tasks = parse("""
        ```markdown
        # Fenced task p2
        ```
        """)
        #expect(tasks.count == 1)
        #expect(tasks[0].title == "Fenced task")
        #expect(tasks[0].priority == .medium)
    }

    @Test func trailingCommasAreTolerated() {
        let tasks = parse("""
        [
          {
            "title": "Messy",
            "tags": ["a", "b",],
          },
        ]
        """)
        #expect(tasks.count == 1)
        #expect(tasks[0].tags == ["a", "b"])
    }

    @Test func curlyQuotesAreTolerated() {
        // Notes/TextEdit smart punctuation rewrites straight quotes.
        let tasks = parse("[{\u{201C}title\u{201D}: \u{201C}Smart quotes\u{201D}}]")
        #expect(tasks.count == 1)
        #expect(tasks[0].title == "Smart quotes")
    }

    @Test func bomIsStripped() {
        let tasks = parse("\u{FEFF}[{\"title\": \"BOM\"}]")
        #expect(tasks.count == 1)
    }

    @Test func validJSONStringsAreNeverRewritten() {
        // Cleanup passes must not fire when the document already parses:
        // a legitimate ",]" inside a string survives untouched.
        let tasks = parse(#"[{"title": "Keep ,] and “quotes” intact"}]"#)
        #expect(tasks.count == 1)
        #expect(tasks[0].title == "Keep ,] and \u{201C}quotes\u{201D} intact")
    }

    // MARK: - Templates

    @Test func templatesRoundTripThroughTheParser() {
        let md = parse(TaskImportParser.markdownTemplate)
        #expect(md.count >= 2)
        #expect(md.allSatisfy { !$0.title.isEmpty })
        let js = parse(TaskImportParser.jsonTemplate)
        #expect(js.count >= 1)
        #expect(js.allSatisfy { !$0.title.isEmpty })
    }
}
