import Testing
import Foundation
@testable import BlinkCore

@Suite("Stats attribution — pomodoros by project / tag")
struct StatsAttributionTests {

    private func task(_ title: String,
                      done: Int,
                      project: String? = nil,
                      tags: [String] = []) -> TaskItem {
        TaskItem(title: title, tags: tags, pomodorosDone: done, project: project)
    }

    // MARK: - By project

    @Test func groupsByProjectSummingPomodoros() {
        let tasks = [
            task("a", done: 3, project: "Blink"),
            task("b", done: 2, project: "Blink"),
            task("c", done: 4, project: "Thesis"),
        ]
        let out = TaskBreakdown.pomodoros(byProject: tasks)
        #expect(out.map(\.name) == ["Blink", "Thesis"])
        #expect(out.map(\.count) == [5, 4])
    }

    @Test func nilOrBlankProjectFallsIntoNoProjectBucket() {
        let tasks = [
            task("a", done: 2, project: nil),
            task("b", done: 1, project: "   "),
            task("c", done: 1, project: "Blink"),
        ]
        let out = TaskBreakdown.pomodoros(byProject: tasks)
        #expect(out.map(\.name) == ["No project", "Blink"])
        #expect(out.map(\.count) == [3, 1])
    }

    @Test func projectsSortedDescendingWithAlphabeticalTies() {
        let tasks = [
            task("a", done: 2, project: "Zeta"),
            task("b", done: 2, project: "Alpha"),
            task("c", done: 5, project: "Mid"),
        ]
        let out = TaskBreakdown.pomodoros(byProject: tasks)
        #expect(out.map(\.name) == ["Mid", "Alpha", "Zeta"])
    }

    @Test func tasksWithZeroPomodorosAreIgnoredForProjects() {
        let tasks = [
            task("a", done: 0, project: "Blink"),
            task("b", done: 0, project: nil),
        ]
        #expect(TaskBreakdown.pomodoros(byProject: tasks).isEmpty)
    }

    @Test func emptyInputYieldsEmptyProjectBreakdown() {
        #expect(TaskBreakdown.pomodoros(byProject: []).isEmpty)
    }

    // MARK: - By tag

    @Test func groupsByTagSummingPomodoros() {
        let tasks = [
            task("a", done: 3, tags: ["ish", "deep"]),
            task("b", done: 2, tags: ["ish"]),
        ]
        let out = TaskBreakdown.pomodoros(byTag: tasks)
        #expect(out.map(\.name) == ["ish", "deep"])
        #expect(out.map(\.count) == [5, 3])
    }

    @Test func duplicateTagOnOneTaskCountsOnce() {
        let tasks = [task("a", done: 4, tags: ["ish", "ish"])]
        let out = TaskBreakdown.pomodoros(byTag: tasks)
        #expect(out.map(\.name) == ["ish"])
        #expect(out.map(\.count) == [4])
    }

    @Test func untaggedTasksContributeNothingToTags() {
        let tasks = [
            task("a", done: 3, tags: []),
            task("b", done: 1, tags: ["ish"]),
        ]
        let out = TaskBreakdown.pomodoros(byTag: tasks)
        #expect(out.map(\.name) == ["ish"])
        #expect(out.map(\.count) == [1])
    }

    @Test func tagsSortedDescendingWithAlphabeticalTies() {
        let tasks = [
            task("a", done: 2, tags: ["zzz"]),
            task("b", done: 2, tags: ["aaa"]),
            task("c", done: 7, tags: ["mid"]),
        ]
        let out = TaskBreakdown.pomodoros(byTag: tasks)
        #expect(out.map(\.name) == ["mid", "aaa", "zzz"])
    }

    @Test func tasksWithZeroPomodorosAreIgnoredForTags() {
        let tasks = [task("a", done: 0, tags: ["ish"])]
        #expect(TaskBreakdown.pomodoros(byTag: tasks).isEmpty)
    }

    @Test func emptyInputYieldsEmptyTagBreakdown() {
        #expect(TaskBreakdown.pomodoros(byTag: []).isEmpty)
    }
}
