import Foundation
import Testing
@testable import SharinganCore

/// Issue numbers are the one identifier users read out loud ("T-42"), so the
/// rules that keep them meaningful — assigned once, never reused, never
/// renumbered — are pinned here.
@MainActor
struct TaskNumberingTests {
    private func freshStore() throws -> TaskStore {
        try TaskStore(fileURL: freshDatabaseURL())
    }

    private func freshDatabaseURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("numbering-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("blink.sqlite")
    }

    @Test func numbersRunFromOneInCreationOrder() throws {
        let store = try freshStore()
        store.add(title: "first")
        store.add(title: "second")
        store.add(title: "third")

        #expect(store.tasks.map(\.number) == [1, 2, 3])
        #expect(store.tasks.map(\.code) == ["T-1", "T-2", "T-3"])
    }

    /// Opening a database written before numbering existed: every task lands
    /// unnumbered at once, and the sequence must follow createdAt rather than
    /// the order the rows come back in — so the numbers match the order the user
    /// actually made the tasks in. (Tasks arriving one at a time are simply
    /// numbered as they arrive; only a whole legacy database has anything to
    /// sort.)
    @Test func backfillNumbersLegacyTasksOldestFirst() throws {
        let url = try freshDatabaseURL()
        let now = Date()
        let legacy = [(-1, "newest"), (-10, "oldest"), (-5, "middle")].map { offset, title in
            TaskItem(title: title,
                     createdAt: now.addingTimeInterval(Double(offset) * 60),
                     sortOrder: offset)   // row order deliberately unlike createdAt
        }
        // Written straight through the database, so the rows arrive exactly as a
        // pre-numbering build left them: number = 0.
        let db = try #require(TaskDatabase(path: url.path))
        db.saveTasks(legacy)
        #expect(db.loadTasks().allSatisfy { $0.number == 0 })

        let store = TaskStore(fileURL: url)
        let byTitle = Dictionary(uniqueKeysWithValues: store.tasks.map { ($0.title, $0.number) })
        #expect(byTitle["oldest"] == 1)
        #expect(byTitle["middle"] == 2)
        #expect(byTitle["newest"] == 3)
    }

    @Test func anAssignedNumberIsNeverChanged() throws {
        let store = try freshStore()
        store.add(title: "keeps its number")
        let id = try #require(store.tasks.first?.id)
        let assigned = try #require(store.tasks.first?.number)

        var edited = try #require(store.tasks.first { $0.id == id })
        edited.title = "edited"
        store.update(edited)
        store.setPriority(id, .high)
        store.add(title: "a later task")

        #expect(store.tasks.first { $0.id == id }?.number == assigned)
    }

    /// Deleting must not free a number for reuse: a report row still points at
    /// the old task, and two tasks reading "T-2" in one history is a lie.
    @Test func deletedNumbersAreNotReused() throws {
        let store = try freshStore()
        store.add(title: "one")
        store.add(title: "two")
        let second = try #require(store.tasks.first { $0.title == "two" }?.id)

        store.delete(second)          // to Trash — still holds number 2
        store.add(title: "three")
        #expect(store.tasks.first { $0.title == "three" }?.number == 3)

        store.deletePermanently(second)   // gone entirely
        store.add(title: "four")
        #expect(store.tasks.first { $0.title == "four" }?.number == 4)
    }

    /// A task arriving over sync carries the number its origin Mac gave it;
    /// this Mac must not renumber it.
    @Test func syncedTaskKeepsItsOriginNumber() throws {
        let store = try freshStore()
        store.add(title: "local")

        var remote = TaskItem(title: "from another Mac")
        remote.number = 900
        store.insert(remote)

        #expect(store.tasks.first { $0.id == remote.id }?.number == 900)
        // The next local task continues past the highest number in the store,
        // so it cannot collide with what arrived.
        store.add(title: "after")
        #expect(store.tasks.first { $0.title == "after" }?.number == 901)
    }

    @Test func numbersSurviveAReload() throws {
        let url = try freshDatabaseURL()

        let first = TaskStore(fileURL: url)
        first.add(title: "one")
        first.add(title: "two")
        let before = first.tasks.map(\.number)
        #expect(before == [1, 2])

        let reopened = TaskStore(fileURL: url)
        #expect(reopened.tasks.map(\.number) == before)
    }

    /// The backfill runs on load and must actually reach the database — the
    /// number sits outside contentHash, so the usual save path skips it (see
    /// TaskDatabase.backfillNumbers). If it only lived in memory, numbers would
    /// silently shift as soon as a task was deleted.
    @Test func backfilledNumbersReachTheDatabase() throws {
        let url = try freshDatabaseURL()

        let first = TaskStore(fileURL: url)
        var legacy = TaskItem(title: "predates numbering")
        legacy.number = 0
        first.insert(legacy)
        #expect(first.tasks.first?.number == 1)

        let reopened = TaskStore(fileURL: url)
        #expect(reopened.tasks.first?.number == 1)
    }
}
