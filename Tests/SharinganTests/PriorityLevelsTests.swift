import Foundation
import Testing
@testable import SharinganCore

/// User-defined priority levels: the `TaskPriority` enum→struct conversion must
/// stay byte-compatible with the old persisted `Int`, the ordering/label
/// helpers must renumber correctly when custom levels are added, and deleting a
/// custom level must move its tasks back to `.none`.
@MainActor
@Suite("Priority levels")
struct PriorityLevelsTests {

    // MARK: - Codable compatibility (old data decodes identically)

    @Test("decodes a bare Int, matching the old enum's encoding")
    func decodesBareInt() throws {
        let dec = JSONDecoder()
        // `3` was the old enum's `.high` rawValue on disk.
        #expect(try dec.decode(TaskPriority.self, from: Data("3".utf8)) == .high)
        #expect(try dec.decode(TaskPriority.self, from: Data("0".utf8)) == .none)
        // A custom level round-trips as its rawValue.
        #expect(try dec.decode(TaskPriority.self, from: Data("7".utf8)).rawValue == 7)
    }

    @Test("encodes as a bare Int (byte-identical to the enum)")
    func encodesBareInt() throws {
        let enc = JSONEncoder()
        #expect(String(data: try enc.encode(TaskPriority.high), encoding: .utf8) == "3")
        #expect(String(data: try enc.encode(TaskPriority.none), encoding: .utf8) == "0")
        #expect(String(data: try enc.encode(TaskPriority(rawValue: 7)), encoding: .utf8) == "7")
    }

    @Test("priority round-trips through encode → decode")
    func roundTrips() throws {
        for raw in [0, 1, 2, 3, 4, 9] {
            let p = TaskPriority(rawValue: raw)
            let data = try JSONEncoder().encode(p)
            #expect(try JSONDecoder().decode(TaskPriority.self, from: data) == p)
        }
    }

    @Test("a TaskItem with a custom priority survives a JSON round-trip")
    func taskItemRoundTrip() throws {
        var t = TaskItem(title: "x")
        t.priority = TaskPriority(rawValue: 5)
        let data = try JSONEncoder().encode(t)
        let back = try JSONDecoder().decode(TaskItem.self, from: data)
        #expect(back.priority.rawValue == 5)
    }

    // MARK: - Ordering

    @Test("levels are most-urgent first, .none last")
    func levelsOrdering() {
        #expect(TaskPriority.levels(custom: []).map(\.rawValue) == [3, 2, 1, 0])
        #expect(TaskPriority.levels(custom: [4, 5]).map(\.rawValue) == [5, 4, 3, 2, 1, 0])
        // Order of the custom array doesn't matter — always sorted descending.
        #expect(TaskPriority.levels(custom: [5, 4]).map(\.rawValue) == [5, 4, 3, 2, 1, 0])
    }

    @Test("zero custom levels reproduce the old P1..P4 menu order exactly")
    func defaultOrderUnchanged() {
        #expect(TaskPriority.levels(custom: []) == [.high, .medium, .low, .none])
    }

    // MARK: - Rank labels

    @Test("built-in short labels with no custom levels")
    func builtinShortLabels() {
        let s = PomodoroSettings()
        #expect(s.priorityShortLabel(.high) == "P1")
        #expect(s.priorityShortLabel(.medium) == "P2")
        #expect(s.priorityShortLabel(.low) == "P3")
        #expect(s.priorityShortLabel(.none) == "")   // .none never gets a chip
    }

    @Test("adding one custom level renumbers the built-ins down")
    func rankRenumbering() {
        var s = PomodoroSettings()
        s.customPriorityLevels = [4]
        #expect(s.priorityShortLabel(TaskPriority(rawValue: 4)) == "P1")
        #expect(s.priorityShortLabel(.high) == "P2")
        #expect(s.priorityShortLabel(.medium) == "P3")
        #expect(s.priorityShortLabel(.low) == "P4")
        #expect(s.priorityShortLabel(.none) == "")
    }

    // MARK: - Importance rule (Eisenhower)

    @Test("custom levels above high count as important")
    func customLevelsAreImportant() {
        let now = Date()
        func task(_ p: TaskPriority) -> TaskItem { TaskItem(title: "t", priority: p) }
        // medium and above → important → schedule (not urgent, important).
        #expect(EisenhowerQuadrant.classify(task(.medium), now: now) == .schedule)
        #expect(EisenhowerQuadrant.classify(task(TaskPriority(rawValue: 9)), now: now) == .schedule)
        // low and none → not important → eliminate.
        #expect(EisenhowerQuadrant.classify(task(.low), now: now) == .eliminate)
    }

    // MARK: - Delete reassigns tasks to .none

    @Test("reassignPriority moves affected tasks off a deleted level")
    func reassignOnDelete() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("prio-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = TaskStore(fileURL: url)
        let custom = TaskPriority(rawValue: 4)
        store.add(title: "a", priority: custom)
        store.add(title: "b", priority: .high)
        store.add(title: "c", priority: custom)

        store.reassignPriority(from: custom, to: .none)

        #expect(store.tasks.filter { $0.priority == custom }.isEmpty)
        #expect(store.tasks.filter { $0.priority == .none }.count == 2)
        // Untouched levels stay put.
        #expect(store.tasks.filter { $0.priority == .high }.count == 1)
    }
}
