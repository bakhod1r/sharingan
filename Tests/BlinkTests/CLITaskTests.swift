import Testing
import Foundation
@testable import BlinkCore

/// `tired task …` plumbing: the CLI-readable task snapshot and the
/// number → UUID resolution behind `done` / `start` / `queue`.
@Suite("CLI task bridge")
struct CLITaskTests {

    // MARK: - Snapshot entry codable

    @Test func taskSnapshotEntryRoundTrips() throws {
        let entry = CLIBridge.TaskSnapshotEntry(
            id: UUID(), title: "hisobot yozish", priorityLabel: "P1",
            due: Date(timeIntervalSince1970: 1_000_000),
            tags: ["ish", "blink"], project: "blink")
        let back = try JSONDecoder().decode(
            CLIBridge.TaskSnapshotEntry.self, from: JSONEncoder().encode(entry))
        #expect(back == entry)
    }

    @Test func taskSnapshotEntryDefaultsStayEmpty() throws {
        let entry = CLIBridge.TaskSnapshotEntry(id: UUID(), title: "bare")
        let back = try JSONDecoder().decode(
            CLIBridge.TaskSnapshotEntry.self, from: JSONEncoder().encode(entry))
        #expect(back.priorityLabel.isEmpty)
        #expect(back.due == nil)
        #expect(back.tags.isEmpty)
        #expect(back.project == nil)
    }

    // MARK: - Snapshot file I/O (shared dir, like the timer snapshot)

    @Test func writeReadTaskSnapshotRoundTrips() {
        // The bridge writes to the fixed shared CLI directory — keep whatever
        // snapshot was there and put it back afterwards.
        let previous = CLIBridge.readTaskSnapshot()
        defer { CLIBridge.writeTaskSnapshot(previous ?? []) }

        let entries = [
            CLIBridge.TaskSnapshotEntry(id: UUID(), title: "first"),
            CLIBridge.TaskSnapshotEntry(id: UUID(), title: "second",
                                        priorityLabel: "P2",
                                        due: Date(timeIntervalSince1970: 2_000_000),
                                        tags: ["x"], project: "p"),
        ]
        CLIBridge.writeTaskSnapshot(entries)
        #expect(CLIBridge.readTaskSnapshot() == entries)

        CLIBridge.writeTaskSnapshot([])
        #expect(CLIBridge.readTaskSnapshot() == [])
    }

    // MARK: - Store → snapshot mapping

    @Test func taskSnapshotEntriesExcludeDoneAndFollowListOrder() {
        let done = TaskItem(title: "finished", isDone: true, sortOrder: 0)
        let second = TaskItem(title: "second", sortOrder: 5)
        let first = TaskItem(title: "first", tags: ["ish"], dueDate: Date(),
                             sortOrder: 1, project: "blink", priority: .high)

        let entries = CLIBridge.taskSnapshotEntries(from: [done, second, first])

        #expect(entries.map(\.title) == ["first", "second"])
        #expect(entries[0].id == first.id)
        #expect(entries[0].priorityLabel == "P1")
        #expect(entries[0].tags == ["ish"])
        #expect(entries[0].project == "blink")
        #expect(entries[0].due == first.dueDate)
        #expect(entries[1].priorityLabel.isEmpty)   // .none renders as no flag
    }

    @Test func taskSnapshotEntriesBreakSortOrderTiesByCreation() {
        let older = TaskItem(title: "older", createdAt: Date(timeIntervalSince1970: 100),
                             sortOrder: 3)
        let newer = TaskItem(title: "newer", createdAt: Date(timeIntervalSince1970: 200),
                             sortOrder: 3)
        let entries = CLIBridge.taskSnapshotEntries(from: [newer, older])
        #expect(entries.map(\.title) == ["older", "newer"])
    }

    // MARK: - Index resolution (`tired task done 2` → UUID)

    @Test func resolveTaskIndexIsOneBasedAndBoundsChecked() {
        let entries = [
            CLIBridge.TaskSnapshotEntry(id: UUID(), title: "a"),
            CLIBridge.TaskSnapshotEntry(id: UUID(), title: "b"),
        ]
        #expect(CLIBridge.resolveTaskIndex(1, in: entries) == entries[0].id)
        #expect(CLIBridge.resolveTaskIndex(2, in: entries) == entries[1].id)
        #expect(CLIBridge.resolveTaskIndex(0, in: entries) == nil)
        #expect(CLIBridge.resolveTaskIndex(-1, in: entries) == nil)
        #expect(CLIBridge.resolveTaskIndex(3, in: entries) == nil)
        #expect(CLIBridge.resolveTaskIndex(1, in: []) == nil)
    }
}
