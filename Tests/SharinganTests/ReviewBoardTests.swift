import Foundation
import Testing
@testable import SharinganCore

@MainActor
@Suite("Review fixes: boards / filters")
struct ReviewBoardTests {
    private func store() throws -> TaskStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("review-board-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return TaskStore(fileURL: dir.appendingPathComponent("blink.sqlite"))
    }

    private func columnStore() -> BoardColumnStore {
        let suite = "review-board-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return BoardColumnStore(defaults: d)
    }

    // MARK: 2.2 Columns menu

    @Test func hiddenCountAndShowAll() {
        let s = columnStore()
        #expect(s.columns.hiddenCount == 0)
        let ids = s.columns.inDisplayOrder.prefix(2).map(\.id)
        ids.forEach { s.setEnabled($0, false) }
        #expect(s.columns.hiddenCount == 2)
        #expect(s.enabled.count == s.columns.count - 2)
        // Menu lists hidden columns too.
        #expect(s.columns.inDisplayOrder.count == s.columns.count)
        s.showAll()
        #expect(s.columns.hiddenCount == 0)
    }

    @Test func toggleBringsHiddenColumnBack() {
        let s = columnStore()
        let id = s.columns[0].id
        s.setEnabled(id, false)
        #expect(!s.enabled.contains { $0.id == id })
        s.setEnabled(id, true)
        #expect(s.enabled.contains { $0.id == id })
    }

    // MARK: 2.6 quick-add parser

    @Test func addParsedAppliesParserFields() throws {
        let s = try store()
        let now = Date()
        #expect(s.addParsed("write report #work @acme p1 ~3", now: now))
        let t = try #require(s.tasks.first)
        #expect(t.title == "write report")
        #expect(t.tags == ["work"])
        #expect(t.project == "acme")
        #expect(t.priority != .none)
        #expect(t.estimatedPomodoros == 3)
    }

    @Test func addParsedPlainTitleAndEmpty() throws {
        let s = try store()
        #expect(!s.addParsed("   "))
        #expect(s.addParsed("just a title"))
        #expect(s.tasks.first?.title == "just a title")
        #expect(s.tasks.first?.dueDate == nil)
    }

    // MARK: 2.11 narrow filter

    @Test func narrowFilterCoversProjectAndDevice() {
        #expect(!TaskNarrowFilter().isActive)
        #expect(TaskNarrowFilter(project: "acme").isActive)
        #expect(TaskNarrowFilter(device: "MacBook").isActive)
        #expect(TaskNarrowFilter(device: "MacBook").chip == .device("MacBook"))
        #expect(TaskNarrowFilter(project: "acme").chip == .project("acme"))
    }

    @Test func narrowFilterSymbols() {
        #expect(TaskNarrowFilter.Chip.tag("x").symbol == "#")
        #expect(TaskNarrowFilter.Chip.project("x").symbol == "@")
    }

    // MARK: 2.5 promote draft-only subtask (store-side contract)

    @Test func promoteUnsavedSubtaskReturnsNilFromStore() throws {
        let s = try store()
        s.add(title: "parent")
        let id = try #require(s.tasks.first?.id)
        #expect(s.promoteSubtask(id, UUID()) == nil)
    }
}
