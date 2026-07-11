import Foundation
import Testing
@testable import BlinkCore

@MainActor
@Suite("Task duplication and templates")
struct TemplateTests {
    private func tempURL(_ tag: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("blink-template-\(tag)-\(UUID().uuidString).sqlite")
    }

    private func tempStore() -> TaskStore { TaskStore(fileURL: tempURL("store")) }

    // MARK: - Duplication

    @Test func duplicateAssignsFreshIDsThroughout() throws {
        let s = tempStore()
        s.add(title: "Original")
        let id = s.tasks[0].id
        s.addSubtask(id, title: "Step 1", estimate: 2)
        s.addSubtask(id, title: "Step 2")

        let newID = try #require(s.duplicate(id))
        #expect(newID != id)
        let copy = try #require(s.tasks.first { $0.id == newID })
        let original = try #require(s.tasks.first { $0.id == id })
        #expect(copy.subtasks.count == 2)
        for (dup, orig) in zip(copy.subtasks, original.subtasks) {
            #expect(dup.id != orig.id)
            #expect(dup.title == orig.title)
            #expect(dup.estimatedPomodoros == orig.estimatedPomodoros)
        }
    }

    @Test func duplicateAppendsCopySuffixAndResetsState() throws {
        let s = tempStore()
        s.add(title: "Ship feature")
        let id = s.tasks[0].id
        s.addSubtask(id, title: "Write code")
        s.incrementPomodoro(id)
        s.toggleSubtask(id, s.tasks[0].subtasks[0].id)
        s.toggleDone(id)   // sets completedAt

        let newID = try #require(s.duplicate(id))
        let copy = try #require(s.tasks.first { $0.id == newID })
        #expect(copy.title == "Ship feature (copy)")
        #expect(copy.isDone == false)
        #expect(copy.pomodorosDone == 0)
        #expect(copy.completedAt == nil)
        #expect(copy.subtasks[0].isDone == false)
        #expect(copy.subtasks[0].pomodorosDone == 0)
        #expect(abs(copy.createdAt.timeIntervalSinceNow) < 5)
    }

    @Test func duplicateKeepsMetadata() throws {
        let s = tempStore()
        let due = Date().addingTimeInterval(3600)
        s.add(title: "Meta", category: "Study", tags: ["deep", "focus"],
              dueDate: due, estimatedPomodoros: 4, recurrence: .weekly,
              project: "Blink", notes: "Some notes", priority: .high)
        let id = s.tasks[0].id
        s.togglePlannedToday(id)
        let original = s.tasks[0]

        let newID = try #require(s.duplicate(id))
        let copy = try #require(s.tasks.first { $0.id == newID })
        #expect(copy.category == "Study")
        #expect(copy.tags == ["deep", "focus"])
        #expect(copy.project == "Blink")
        #expect(copy.priority == .high)
        #expect(copy.dueDate == original.dueDate)
        #expect(copy.plannedDate == original.plannedDate)
        #expect(copy.estimatedPomodoros == 4)
        #expect(copy.notes == "Some notes")
        #expect(copy.recurrence == .weekly)
    }

    @Test func duplicateLeavesOriginalUntouchedAndSlotsCopyAfterIt() throws {
        let s = tempStore()
        s.add(title: "A")
        s.add(title: "B")
        s.add(title: "C")
        let a = s.tasks[0]

        let newID = try #require(s.duplicate(a.id))
        let after = try #require(s.tasks.first { $0.id == a.id })
        #expect(after == a)   // original completely unchanged

        let ordered = s.tasks.sorted(by: TaskStore.inListOrder).map(\.title)
        #expect(ordered == ["A", "A (copy)", "B", "C"])
        let copy = try #require(s.tasks.first { $0.id == newID })
        #expect(copy.sortOrder == a.sortOrder + 1)
    }

    @Test func duplicateUnknownIDReturnsNil() {
        let s = tempStore()
        s.add(title: "Only one")
        #expect(s.duplicate(UUID()) == nil)
        #expect(s.tasks.count == 1)
    }

    // MARK: - Templates

    @Test func saveTemplateStripsState() throws {
        let store = TemplateStore(fileURL: tempURL("strip"))
        var task = TaskItem(title: "Weekly review", tags: ["ritual"],
                            isDone: true, pomodorosDone: 7,
                            dueDate: Date(), estimatedPomodoros: 3,
                            plannedDate: Date(), notes: "Checklist",
                            subtasks: [Subtask(title: "Inbox zero", isDone: true,
                                               estimatedPomodoros: 1, pomodorosDone: 2)],
                            priority: .medium)
        task.completedAt = Date()

        store.saveTemplate(from: task, name: "Review")
        let template = try #require(store.templates.first)
        #expect(template.name == "Review")
        let item = template.item
        #expect(item.isDone == false)
        #expect(item.pomodorosDone == 0)
        #expect(item.completedAt == nil)
        #expect(item.dueDate == nil)
        #expect(item.plannedDate == nil)
        #expect(item.subtasks[0].isDone == false)
        #expect(item.subtasks[0].pomodorosDone == 0)
        // Shape survives.
        #expect(item.title == "Weekly review")
        #expect(item.tags == ["ritual"])
        #expect(item.estimatedPomodoros == 3)
        #expect(item.subtasks[0].estimatedPomodoros == 1)
        #expect(item.priority == .medium)
    }

    @Test func instantiateReturnsFreshIDsEachCall() throws {
        let store = TemplateStore(fileURL: tempURL("fresh"))
        let task = TaskItem(title: "Sprint prep",
                            subtasks: [Subtask(title: "Groom backlog")])
        store.saveTemplate(from: task, name: "Sprint")
        let tid = try #require(store.templates.first?.id)

        let first = try #require(store.instantiate(tid))
        let second = try #require(store.instantiate(tid))
        #expect(first.id != second.id)
        #expect(first.id != task.id)
        #expect(first.subtasks[0].id != second.subtasks[0].id)
        #expect(first.subtasks[0].id != task.subtasks[0].id)
        #expect(abs(first.createdAt.timeIntervalSinceNow) < 5)
        #expect(store.instantiate(UUID()) == nil)
    }

    @Test func renameAndDeletePersistAcrossInstances() throws {
        let url = tempURL("persist")
        let a = TemplateStore(fileURL: url)
        a.saveTemplate(from: TaskItem(title: "One"), name: "First")
        a.saveTemplate(from: TaskItem(title: "Two"), name: "Second")
        let firstID = try #require(a.templates.first { $0.name == "First" }?.id)
        let secondID = try #require(a.templates.first { $0.name == "Second" }?.id)
        a.rename(firstID, to: "Renamed")
        a.delete(secondID)

        let b = TemplateStore(fileURL: url)
        #expect(b.templates.count == 1)
        #expect(b.templates.first?.id == firstID)
        #expect(b.templates.first?.name == "Renamed")
        #expect(b.templates.first?.item.title == "One")
    }

    @Test func insertingInstantiatedTemplateAppendsWithSortOrder() throws {
        let url = tempURL("insert")
        let tasks = TaskStore(fileURL: url)
        let templates = TemplateStore(fileURL: url)
        tasks.add(title: "Existing")

        templates.saveTemplate(from: TaskItem(title: "From template"), name: "T")
        let tid = try #require(templates.templates.first?.id)
        let instance = try #require(templates.instantiate(tid))
        tasks.insert(instance)

        let ordered = tasks.tasks.sorted(by: TaskStore.inListOrder).map(\.title)
        #expect(ordered == ["Existing", "From template"])
        let inserted = try #require(tasks.tasks.first { $0.title == "From template" })
        #expect(inserted.sortOrder > tasks.tasks.first { $0.title == "Existing" }!.sortOrder)

        // Persisted like any other task.
        let reloaded = TaskStore(fileURL: url)
        #expect(reloaded.tasks.contains { $0.id == instance.id })
    }
}
