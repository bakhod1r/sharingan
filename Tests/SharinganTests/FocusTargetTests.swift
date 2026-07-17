import Testing
import Foundation
@testable import SharinganCore

/// Focusing a task with subtasks targets its first unfinished subtask, uses
/// that subtask's pomodoro size, and surfaces the subtask's title to the focus
/// screens (`activeFocusTitle`).
@Suite("Focus target")
@MainActor
struct FocusTargetTests {

    private func freshStore() throws -> TaskStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("focustarget-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return TaskStore(fileURL: dir.appendingPathComponent("blink.sqlite"))
    }

    @Test func focusingTaskWithSubtasksTargetsFirstOpenOne() throws {
        let store = try freshStore()
        var task = TaskItem(title: "Parent", category: "Work")
        task.subtasks = [
            Subtask(title: "Done step", isDone: true),
            Subtask(title: "First open", pomodoroKind: .big),
            Subtask(title: "Second open"),
        ]
        store.insert(task)

        store.selectFocusTarget(task.id)
        #expect(store.activeTaskID == task.id)
        #expect(store.activeSubtaskID == task.subtasks[1].id, "must skip the done step")
        // The targeted subtask's pomodoro size wins.
        #expect(store.resolvedActiveKind == .big)
        // Screens show the subtask's title, not the task's.
        #expect(store.activeFocusTitle == "First open")
    }

    @Test func focusingTaskWithoutOpenSubtasksTargetsTheTask() throws {
        let store = try freshStore()
        var task = TaskItem(title: "Solo", category: "Work", pomodoroKind: .small)
        task.subtasks = [Subtask(title: "already done", isDone: true)]
        store.insert(task)

        store.selectFocusTarget(task.id)
        #expect(store.activeSubtaskID == nil)
        #expect(store.resolvedActiveKind == .small)      // falls back to the task's kind
        #expect(store.activeFocusTitle == "Solo")
    }

    @Test func plainTaskFocusesItself() throws {
        let store = try freshStore()
        let task = TaskItem(title: "Plain", category: "Work")
        store.insert(task)

        store.selectFocusTarget(task.id)
        #expect(store.activeSubtaskID == nil)
        #expect(store.activeFocusTitle == "Plain")
    }

    @Test func activeFocusTitleIsNilWhenNothingActive() throws {
        let store = try freshStore()
        #expect(store.activeFocusTitle == nil)
    }

    @Test func codeRendersTheAssignedNumber() {
        var task = TaskItem(title: "X", category: "Work")
        #expect(task.code == nil)   // unnumbered until the store assigns one
        task.number = 42
        #expect(task.code == "T-42")
    }

    @Test func shortLabelAppendsSubtaskNumberFromOne() throws {
        let store = try freshStore()
        var task = TaskItem(title: "Parent", category: "Work")
        task.subtasks = [Subtask(title: "one"), Subtask(title: "two"), Subtask(title: "three")]
        store.insert(task)
        // insert() numbers the task; read it back rather than assuming "T-1".
        let code = try #require(store.tasks.first { $0.id == task.id }?.code)

        store.setActiveSubtask(taskID: task.id, subtaskID: task.subtasks[2].id)
        // A dot, not a dash: "T-1-3" would read as two codes joined.
        #expect(store.activeShortLabel == "\(code).3")

        // Task-level focus shows the bare code, no suffix.
        store.setActiveSubtask(taskID: task.id, subtaskID: nil)
        #expect(store.activeShortLabel == code)
    }
}
