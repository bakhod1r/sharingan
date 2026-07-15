import CloudKit
import Foundation
import Testing
@testable import SharinganCore

// Phase 0-1 of the hierarchy-aware Jira conversion: the issue-type field and
// subtask-level Jira identity must survive persistence, sync mapping, and the
// importer must nest Jira sub-tasks under their parents instead of scattering
// them as orphan top-level tasks (45 of the user's 131 imports were exactly
// that).
@Suite("Jira hierarchy")
struct JiraHierarchyTests {

    // MARK: - Persistence

    @Test("jiraIssueType and subtask Jira identity survive a DB round-trip")
    func dbRoundTripCarriesTypeAndSubtaskIdentity() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("jira-hier-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("t.sqlite").path
        defer { try? FileManager.default.removeItem(at: dir) }

        var task = TaskItem(title: "API to terminate all sessions",
                            jiraKey: "WT-689", jiraIssueID: "10100",
                            jiraSiteHost: "wayll.atlassian.net",
                            jiraIssueType: "Story")
        task.subtasks = [
            Subtask(title: "Write endpoint", estimatedPomodoros: 2,
                    jiraKey: "WT-702", jiraIssueID: "10102"),
            Subtask(title: "local-only step"),
        ]

        do {
            let db = try #require(TaskDatabase(path: path))
            db.saveTasks([task])
        }
        let db2 = try #require(TaskDatabase(path: path))
        let loaded = try #require(db2.loadTasks().first)

        #expect(loaded.jiraIssueType == "Story")
        #expect(loaded.subtasks.count == 2)
        let jiraSub = try #require(loaded.subtasks.first)
        #expect(jiraSub.jiraKey == "WT-702")
        #expect(jiraSub.jiraIssueID == "10102")
        #expect(jiraSub.isJiraLinked)
        let localSub = try #require(loaded.subtasks.last)
        #expect(localSub.jiraKey == nil)
        #expect(!localSub.isJiraLinked)
    }

    @Test("jiraIssueType and subtask identity ride the CloudKit record")
    func recordMapperRoundTripCarriesTypeAndSubtaskIdentity() throws {
        let zone = CKRecordZone.ID(zoneName: "SharinganData",
                                   ownerName: CKCurrentUserDefaultName)
        var task = TaskItem(title: "Task 1",
                            jiraKey: "SHRGN-4", jiraIssueID: "10004",
                            jiraSiteHost: "wayll.atlassian.net",
                            jiraIssueType: "Bug")
        task.subtasks = [Subtask(title: "step", jiraKey: "SHRGN-9", jiraIssueID: "10009")]

        let record = RecordMapper.record(for: task, in: zone, systemFields: nil)
        let back = try #require(RecordMapper.task(from: record))

        #expect(back.jiraIssueType == "Bug")
        let sub = try #require(back.subtasks.first)
        #expect(sub.jiraKey == "SHRGN-9")
        #expect(sub.jiraIssueID == "10009")
    }

    // MARK: - Parent decoding

    @Test("an issue's parent reference decodes from the fields payload")
    func issueParentDecodes() throws {
        let json = Data("""
        {
          "id": "10102",
          "key": "WT-702",
          "fields": {
            "summary": "Write endpoint",
            "issuetype": { "name": "Sub-task", "subtask": true },
            "parent": { "id": "10100", "key": "WT-689" }
          }
        }
        """.utf8)
        let issue = try JSONDecoder().decode(JiraIssue.self, from: json)
        #expect(issue.fields.parent?.key == "WT-689")
        #expect(issue.fields.parent?.id == "10100")
        #expect(issue.fields.issuetype?.subtask == true)
    }

    @Test("parent is nil when absent — top-level issues stay top-level")
    func issueWithoutParentDecodes() throws {
        let json = Data("""
        {
          "id": "10100",
          "key": "WT-689",
          "fields": { "summary": "API to terminate all sessions",
                      "issuetype": { "name": "Story", "subtask": false } }
        }
        """.utf8)
        let issue = try JSONDecoder().decode(JiraIssue.self, from: json)
        #expect(issue.fields.parent == nil)
    }

    // MARK: - Hierarchy building

    /// Decodes a minimal issue; assembling via JSON keeps these tests honest
    /// about what the wire actually carries.
    private func makeIssue(key: String, id: String, type: String, subtask: Bool = false,
                           parentKey: String? = nil, parentID: String? = nil,
                           summary: String? = nil, statusCategory: String = "indeterminate",
                           estimateSeconds: Int? = nil) throws -> JiraIssue {
        var fields: [String: Any] = [
            "summary": summary ?? "Issue \(key)",
            "issuetype": ["name": type, "subtask": subtask],
            "status": ["name": "S", "statusCategory": ["key": statusCategory]],
        ]
        if let parentKey { fields["parent"] = ["id": parentID ?? "", "key": parentKey] }
        if let estimateSeconds { fields["timeoriginalestimate"] = estimateSeconds }
        let payload: [String: Any] = ["id": id, "key": key, "fields": fields]
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(JiraIssue.self, from: data)
    }

    @Test("sub-tasks group under their parents; parent order is preserved")
    func hierarchyGroupsSubtasksUnderParents() throws {
        let parentA = try makeIssue(key: "WT-689", id: "1", type: "Story")
        let parentB = try makeIssue(key: "WT-690", id: "2", type: "Task")
        let subA1 = try makeIssue(key: "WT-702", id: "3", type: "Sub-task", subtask: true, parentKey: "WT-689")
        let subA2 = try makeIssue(key: "WT-703", id: "4", type: "Sub-task", subtask: true, parentKey: "WT-689")

        let h = JiraFieldMapper.buildHierarchy(issues: [subA1, parentA, parentB, subA2])

        #expect(h.parents.map(\.key) == ["WT-689", "WT-690"])
        #expect(h.subtasks(forParentKey: "WT-689").map(\.key) == ["WT-702", "WT-703"])
        #expect(h.subtasks(forParentKey: "WT-690").isEmpty)
        #expect(h.orphanSubtasks.isEmpty)
    }

    @Test("a sub-task whose parent isn't in the set is an orphan, not a parent")
    func hierarchyIsolatesOrphans() throws {
        let sub = try makeIssue(key: "WT-800", id: "9", type: "Sub-task", subtask: true, parentKey: "WT-999")
        let h = JiraFieldMapper.buildHierarchy(issues: [sub])
        #expect(h.parents.isEmpty)
        #expect(h.orphanSubtasks.map(\.key) == ["WT-800"])
    }

    @Test("a Jira sub-task converts to a Subtask carrying its own identity")
    func subtaskConversion() throws {
        let sub = try makeIssue(key: "WT-702", id: "10102", type: "Sub-task", subtask: true,
                                parentKey: "WT-689", summary: "Write endpoint",
                                statusCategory: "done", estimateSeconds: 3000)
        let s = JiraFieldMapper.subtask(from: sub)
        #expect(s.title == "Write endpoint")
        #expect(s.isDone)
        #expect(s.estimatedPomodoros == 2)   // ceil(3000/1500)
        #expect(s.jiraKey == "WT-702")
        #expect(s.jiraIssueID == "10102")
    }

    @Test("importing an issue records its Jira issue type for the badge")
    func importCarriesIssueType() throws {
        let epic = try makeIssue(key: "SHRGN-1", id: "11", type: "Epic")
        let task = JiraFieldMapper.taskItem(from: epic, siteHost: "wayll.atlassian.net")
        #expect(task.jiraIssueType == "Epic")
    }

    // MARK: - Nesting + absorbing flat imports

    @Test("nesting keeps local subtask progress and absorbs a flat-imported twin")
    func nestSubtasksPreservesProgressAndAbsorbsFlatTask() throws {
        var parent = TaskItem(title: "API to terminate all sessions",
                              jiraKey: "WT-689", jiraIssueID: "1",
                              jiraSiteHost: "wayll.atlassian.net", jiraIssueType: "Story")
        // Already-nested subtask with local progress; Jira renamed it since.
        let existingID = UUID()
        parent.subtasks = [
            Subtask(id: existingID, title: "Old name", pomodorosDone: 3,
                    jiraKey: "WT-702", jiraIssueID: "3"),
            Subtask(title: "local-only step", pomodorosDone: 1),
        ]
        let remoteRenamed = try makeIssue(key: "WT-702", id: "3", type: "Sub-task", subtask: true,
                                          parentKey: "WT-689", summary: "New name")
        let remoteNew = try makeIssue(key: "WT-704", id: "5", type: "Sub-task", subtask: true,
                                      parentKey: "WT-689", summary: "Fresh step")
        // The old flat import of WT-704: its progress must transfer, and it must go.
        let flatTwin = TaskItem(title: "Fresh step", pomodorosDone: 2,
                                jiraKey: "WT-704", jiraIssueID: "5",
                                jiraSiteHost: "wayll.atlassian.net")

        let result = JiraFieldMapper.nestSubtasks(into: parent,
                                                  remote: [remoteRenamed, remoteNew],
                                                  absorbing: [flatTwin])

        let subs = result.parent.subtasks
        #expect(subs.count == 3)
        let renamed = try #require(subs.first { $0.jiraIssueID == "3" })
        #expect(renamed.id == existingID)          // identity kept — views don't lose it
        #expect(renamed.title == "New name")       // Jira owns the title
        #expect(renamed.pomodorosDone == 3)        // local progress kept
        let fresh = try #require(subs.first { $0.jiraIssueID == "5" })
        #expect(fresh.pomodorosDone == 2)          // absorbed from the flat twin
        #expect(result.absorbedTaskIDs == [flatTwin.id])
        #expect(subs.contains { $0.title == "local-only step" && $0.pomodorosDone == 1 })
    }
}
