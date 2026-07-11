import Foundation
import Testing
@testable import BlinkCore

@MainActor
@Suite("Subtask reorder + promote")
struct SubtaskOpsTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("blink-subtaskops-\(UUID().uuidString).sqlite")
    }

    private func tempStore() -> TaskStore { TaskStore(fileURL: tempURL()) }

    /// Builds a task with three subtasks A, B, C and returns (store, taskID).
    private func storeWithSubtasks(url: URL? = nil) -> (TaskStore, UUID) {
        let s = TaskStore(fileURL: url ?? tempURL())
        s.add(title: "Parent")
        let id = s.tasks[0].id
        s.addSubtask(id, title: "A")
        s.addSubtask(id, title: "B")
        s.addSubtask(id, title: "C")
        return (s, id)
    }

    // MARK: - reorderSubtasks

    @Test func reorderMovesAndPersistsAcrossInstances() throws {
        let url = tempURL()
        let (s, id) = storeWithSubtasks(url: url)

        // Move "A" (index 0) below "B" — onMove semantics: destination 2.
        s.reorderSubtasks(id, from: IndexSet(integer: 0), to: 2)
        #expect(s.tasks[0].subtasks.map(\.title) == ["B", "A", "C"])

        // A second store on the same path sees the new order.
        let reloaded = TaskStore(fileURL: url)
        let task = try #require(reloaded.tasks.first { $0.id == id })
        #expect(task.subtasks.map(\.title) == ["B", "A", "C"])
    }

    @Test func reorderUnknownTaskIsNoOp() {
        let (s, id) = storeWithSubtasks()
        s.reorderSubtasks(UUID(), from: IndexSet(integer: 0), to: 2)
        #expect(s.tasks.first { $0.id == id }?.subtasks.map(\.title) == ["A", "B", "C"])
    }

    // MARK: - promoteSubtask

    @Test func promoteInheritsParentMetadataAndSubtaskProgress() throws {
        let s = tempStore()
        s.add(title: "Parent", category: TaskCategory.presets[1].name,
              tags: ["deep", "q3"], project: "Blink", priority: .high)
        let parentID = s.tasks[0].id
        s.addSubtask(parentID, title: "Ship it", estimate: 3)
        let sub = s.tasks[0].subtasks[0]

        // Progress + a completed state that must NOT carry over.
        s.setActiveSubtask(taskID: parentID, subtaskID: sub.id)
        s.incrementPomodoro(parentID)
        s.toggleSubtask(parentID, sub.id)

        let newID = try #require(s.promoteSubtask(parentID, sub.id))
        let promoted = try #require(s.tasks.first { $0.id == newID })
        let parent = try #require(s.tasks.first { $0.id == parentID })

        #expect(newID != sub.id)
        #expect(promoted.title == "Ship it")
        #expect(promoted.category == TaskCategory.presets[1].name)
        #expect(promoted.project == "Blink")
        #expect(promoted.tags == ["deep", "q3"])
        #expect(promoted.priority == .high)
        #expect(promoted.estimatedPomodoros == 3)
        #expect(promoted.pomodorosDone == 1)
        #expect(!promoted.isDone)
        #expect(promoted.completedAt == nil)
        #expect(promoted.dueDate == nil)
        #expect(promoted.plannedDate == nil)
        #expect(promoted.recurrence == .none)
        #expect(promoted.notes.isEmpty)
        #expect(promoted.subtasks.isEmpty)
        #expect(!parent.subtasks.contains { $0.id == sub.id })
    }

    @Test func promotePositionsNewTaskRightAfterParent() throws {
        let s = tempStore()
        s.add(title: "Parent")
        s.add(title: "After")
        let parentID = s.tasks[0].id
        s.addSubtask(parentID, title: "Step")
        let subID = s.tasks[0].subtasks[0].id

        let newID = try #require(s.promoteSubtask(parentID, subID))
        let ordered = s.tasks.sorted(by: TaskStore.inListOrder)
        #expect(ordered.map(\.title) == ["Parent", "Step", "After"])
        #expect(ordered[1].id == newID)
    }

    @Test func promoteActiveSubtaskClearsActiveSubtaskID() throws {
        let (s, id) = storeWithSubtasks()
        let subID = s.tasks[0].subtasks[1].id
        s.setActiveSubtask(taskID: id, subtaskID: subID)
        #expect(s.activeSubtaskID == subID)

        _ = try #require(s.promoteSubtask(id, subID))
        #expect(s.activeSubtaskID == nil)
    }

    @Test func promoteUnknownIDsReturnsNilWithoutChanges() {
        let (s, id) = storeWithSubtasks()
        let before = s.tasks

        #expect(s.promoteSubtask(UUID(), s.tasks[0].subtasks[0].id) == nil)
        #expect(s.promoteSubtask(id, UUID()) == nil)
        #expect(s.tasks == before)
    }
}
