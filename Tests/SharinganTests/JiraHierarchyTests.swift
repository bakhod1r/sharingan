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
}
