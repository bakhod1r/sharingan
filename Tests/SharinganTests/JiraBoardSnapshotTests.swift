import Foundation
import Testing
@testable import SharinganCore

@Suite("Jira board snapshot cache", .serialized)
struct JiraBoardSnapshotTests {

    private func tempStorage() throws -> JiraStorage {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("jira-snap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try #require(JiraStorage(path: dir.appendingPathComponent("t.sqlite").path))
    }

    @Test("a board snapshot round-trips through SQLite")
    func roundTrip() throws {
        let store = try tempStorage()
        let snap = JiraStorage.BoardSnapshot(
            projectKey: "SHRGN", siteHost: "x.atlassian.net",
            sprintName: "Sprint 7", columnsJSON: #"[{"id":"To Do"}]"#)
        store.saveBoardSnapshot(snap)

        let back = try #require(store.boardSnapshot(projectKey: "SHRGN"))
        #expect(back.projectKey == "SHRGN")
        #expect(back.siteHost == "x.atlassian.net")
        #expect(back.sprintName == "Sprint 7")
        #expect(back.columnsJSON == #"[{"id":"To Do"}]"#)
    }

    @Test("saving the same project again replaces the snapshot")
    func upsert() throws {
        let store = try tempStorage()
        store.saveBoardSnapshot(.init(projectKey: "P", siteHost: "h", sprintName: "A", columnsJSON: "[]"))
        store.saveBoardSnapshot(.init(projectKey: "P", siteHost: "h", sprintName: "B", columnsJSON: "[1]"))
        let back = try #require(store.boardSnapshot(projectKey: "P"))
        #expect(back.sprintName == "B")
        #expect(back.columnsJSON == "[1]")
    }

    @Test("a nil sprint name (kanban board) survives the round-trip")
    func nilSprint() throws {
        let store = try tempStorage()
        store.saveBoardSnapshot(.init(projectKey: "K", siteHost: "h", sprintName: nil, columnsJSON: "[]"))
        let back = try #require(store.boardSnapshot(projectKey: "K"))
        #expect(back.sprintName == nil)
    }

    @Test("an unknown project has no snapshot")
    func missing() throws {
        let store = try tempStorage()
        #expect(store.boardSnapshot(projectKey: "nope") == nil)
    }

    @Test("the model's Column list encodes and decodes for the cache")
    func columnCodable() throws {
        let card = JiraBoardModel.Card(id: "SHRGN-1", key: "SHRGN-1", summary: "Do it",
                                       issueType: "Task", priorityName: "High",
                                       estimateSeconds: 3600, statusId: "10",
                                       statusCategoryKey: "indeterminate")
        let column = JiraBoardModel.Column(id: "In Progress", name: "In Progress",
                                           statusIds: ["10"], cards: [card], isOther: false)
        let data = try JSONEncoder().encode([column])
        let back = try JSONDecoder().decode([JiraBoardModel.Column].self, from: data)
        #expect(back == [column])
    }
}
