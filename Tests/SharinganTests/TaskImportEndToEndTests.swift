import Foundation
import Testing
@testable import SharinganCore

/// The full import pipeline, exactly as the Import button runs it:
/// `TaskImportParser.parse` → `TaskStore.insert` (real SQLite in a temp dir)
/// → a *fresh* `TaskStore` on the same file — asserting every field survives
/// persistence, not just parsing.
@MainActor
@Suite("Task import — end to end through the store")
struct TaskImportEndToEndTests {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("blink-import-\(UUID().uuidString).json")
    }

    @Test func markdownTemplateImportsAndRoundTrips() throws {
        let url = tempURL()
        let store = TaskStore(fileURL: url)
        let parsed = TaskImportParser.parse(TaskImportParser.markdownTemplate)
        #expect(parsed.count == 2)
        for t in parsed { store.insert(t) }

        // What the user sees after relaunch: a second store on the same file.
        let reloaded = TaskStore(fileURL: url)
        #expect(reloaded.tasks.count == 2)

        let report = try #require(reloaded.tasks.first { $0.title == "Write the report" })
        #expect(report.priority == .high)
        #expect(report.tags == ["deep-work"])
        #expect(report.project == "myproject")
        #expect(report.category == "Work")
        #expect(report.estimatedPomodoros == 4)
        #expect(report.recurrence == .weekly)
        #expect(report.pomodoroKind == .big)
        #expect(report.dueDate != nil)
        #expect(report.plannedDate != nil)
        #expect(report.notes.contains("notes"))
        #expect(report.subtasks.count == 3)
        #expect(report.subtasks[0].estimatedPomodoros == 1)
        #expect(report.subtasks[1].pomodoroKind == .big)
        #expect(report.subtasks[2].isDone)

        let reading = try #require(reloaded.tasks.first { $0.title == "Read 20 pages" })
        #expect(reading.priority == .low)
        #expect(reading.recurrence == .daily)
    }

    @Test func fencedLLMJSONImportsAndRoundTrips() throws {
        // A messy-but-typical LLM answer: fenced, trailing comma, curly quotes.
        let pasted = """
        ```json
        [
          {
            \u{201C}title\u{201D}: \u{201C}Sprint planning\u{201D},
            "priority": "P1",
            "due": "2026-07-20 15:00",
            "pomodoro": "big",
            "subtasks": ["Agenda", {"title": "Estimates", "estimate": 2},],
          },
          { "title": "Inbox zero", "repeat": "har kuni" }
        ]
        ```
        """
        let url = tempURL()
        let store = TaskStore(fileURL: url)
        let parsed = TaskImportParser.parse(pasted)
        #expect(parsed.count == 2)
        for t in parsed { store.insert(t) }

        let reloaded = TaskStore(fileURL: url)
        let sprint = try #require(reloaded.tasks.first { $0.title == "Sprint planning" })
        #expect(sprint.priority == .high)
        #expect(sprint.pomodoroKind == .big)
        #expect(sprint.dueDate != nil)
        #expect(sprint.subtasks.map(\.title) == ["Agenda", "Estimates"])
        #expect(sprint.subtasks[1].estimatedPomodoros == 2)
        let inbox = try #require(reloaded.tasks.first { $0.title == "Inbox zero" })
        #expect(inbox.recurrence == .daily)
    }

    // The submit hook every add field routes through: documents bulk-import,
    // plain quick-add lines fall through to the caller's single add.
    @Test func addFieldHookImportsDocumentsOnly() {
        let store = TaskStore(fileURL: tempURL())
        // One quick-add line — not a document; caller should single-add it.
        #expect(store.importIfDocument("hisobot yozish p1 ertaga") == 0)
        #expect(store.tasks.isEmpty)
        // A pasted markdown doc imports in bulk.
        #expect(store.importIfDocument("# One p1\n# Two ~2") == 2)
        #expect(store.tasks.count == 2)
        // Single-line JSON counts as a document too.
        #expect(store.importIfDocument(#"{"title": "From JSON"}"#) == 1)
        // Fenced content likewise.
        #expect(store.importIfDocument("```json\n[{\"title\": \"Fenced\"}]\n```") == 1)
        // JSON-looking garbage yields nothing — caller falls back.
        #expect(store.importIfDocument("[not json") == 0)
        #expect(store.tasks.count == 4)
    }

    @Test func importAppendsBelowExistingTasks() {
        let url = tempURL()
        let store = TaskStore(fileURL: url)
        store.add(title: "Already here")
        for t in TaskImportParser.parse("# Imported one\n# Imported two") {
            store.insert(t)
        }
        let orders = store.tasks.sorted { $0.sortOrder < $1.sortOrder }.map(\.title)
        #expect(orders == ["Already here", "Imported one", "Imported two"])
    }
}
