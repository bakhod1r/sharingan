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
        #expect(store.importIfDocument("hisobot yozish p1 ertaga") == nil)
        #expect(store.tasks.isEmpty)
        // A pasted markdown doc imports in bulk.
        #expect(store.importIfDocument("# One p1\n# Two ~2")?.inserted == 2)
        #expect(store.tasks.count == 2)
        // Single-line JSON counts as a document too.
        #expect(store.importIfDocument(#"{"title": "From JSON"}"#)?.inserted == 1)
        // Fenced content likewise.
        #expect(store.importIfDocument("```json\n[{\"title\": \"Fenced\"}]\n```")?.inserted == 1)
        // JSON-looking garbage yields nothing — caller falls back.
        #expect(store.importIfDocument("[not json") == nil)
        #expect(store.tasks.count == 4)
    }

    // "Template tashlasa double task qo'shmasin": re-importing a document
    // holds back tasks whose titles are already on the open list — they are
    // returned for the UI's "add anyway?" prompt, never inserted silently.
    @Test func duplicateTitlesAreHeldBackNotInserted() {
        let store = TaskStore(fileURL: tempURL())
        let doc = "# Write report p1\n# Read 20 pages ~1"
        #expect(store.importIfDocument(doc)?.inserted == 2)

        // Same template pasted again: nothing inserted, both held back.
        let again = store.importIfDocument(doc)
        #expect(again?.inserted == 0)
        #expect(again?.duplicates.count == 2)
        #expect(store.tasks.count == 2)

        // The user says "add anyway" → the held-back copies go in.
        store.insertAll(again?.duplicates ?? [])
        #expect(store.tasks.count == 4)
    }

    @Test func duplicateMatchIsCaseInsensitiveAndBatchAware() {
        let store = TaskStore(fileURL: tempURL())
        store.add(title: "Write Report")
        let result = store.importIfDocument("# write report\n# Fresh one\n# fresh ONE")
        // "write report" duplicates the existing task; the second "fresh one"
        // duplicates the first inside the same batch.
        #expect(result?.inserted == 1)
        #expect(result?.duplicates.count == 2)
    }

    @Test func completedTasksDoNotBlockReimport() {
        let store = TaskStore(fileURL: tempURL())
        store.add(title: "Daily review")
        store.toggleDone(store.tasks[0].id)
        let result = store.importIfDocument("# Daily review\n# Other")
        #expect(result?.inserted == 2)
        #expect(result?.duplicates.isEmpty == true)
    }

    // Exactly-once add through the coordinator (the sharingan:// URL and
    // `tired` CLI path) — guards the double-add regression at the app level,
    // and documents that this path bulk-imports documents too.
    @Test func cliAddIsExactlyOnceAndImportsDocuments() {
        let store = TaskStore(fileURL: tempURL())
        let coord = SharinganCoordinator(timer: PomodoroTimer())
        coord.cliTaskAdd("hisobot yozish p1", store: store)
        #expect(store.tasks.count == 1)
        #expect(store.tasks[0].title == "hisobot yozish")
        coord.cliTaskAdd("# One ~1\n# Two ~2", store: store)
        #expect(store.tasks.count == 3)
        // Empty payloads add nothing.
        coord.cliTaskAdd("   ", store: store)
        coord.cliTaskAdd(nil, store: store)
        #expect(store.tasks.count == 3)
        // Headless path: re-importing the same document skips duplicates
        // silently (no UI to ask through).
        coord.cliTaskAdd("# One ~1\n# Two ~2", store: store)
        #expect(store.tasks.count == 3)
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
