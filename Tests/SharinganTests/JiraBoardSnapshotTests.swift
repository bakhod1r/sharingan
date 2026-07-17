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

    @Test("the Agile-free board groups issues into To Do / In Progress / Done by status category")
    func statusCategoryColumns() throws {
        func issue(_ key: String, _ category: String) throws -> JiraIssue {
            let json = #"""
            {"id":"\#(key)","key":"\#(key)","fields":{"summary":"\#(key)","status":{"id":"1","name":"S","statusCategory":{"key":"\#(category)"}}}}
            """#
            return try JSONDecoder().decode(JiraIssue.self, from: Data(json.utf8))
        }
        let issues = [try issue("A", "new"), try issue("B", "indeterminate"),
                      try issue("C", "done"), try issue("D", "new")]
        let cols = JiraBoardModel.buildStatusCategoryColumns(issues: issues)
        #expect(cols.map(\.name) == ["To Do", "In Progress", "Done"])
        #expect(cols[0].cards.map(\.key) == ["A", "D"])
        #expect(cols[1].cards.map(\.key) == ["B"])
        #expect(cols[2].cards.map(\.key) == ["C"])
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
