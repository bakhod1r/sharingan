import Foundation
import Testing
@testable import SharinganCore

// A completed pomodoro on a Jira-linked task queues a worklog. When the active
// subtask mirrors a Jira sub-task, the worklog targets the sub-task issue —
// that's where the work (and the time) actually belongs — otherwise the parent
// task's issue.
@Suite("Jira worklog hook")
struct JiraWorklogHookTests {

    @MainActor
    private func makeService() throws -> (JiraService, JiraStorage, TaskStore, UserDefaults) {
        let suite = "jira-worklog-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set("twoWay", forKey: JiraService.syncModeDefaultsKey)
        defaults.set(true, forKey: JiraService.worklogSyncDefaultsKey)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("jira-worklog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storage = try #require(JiraStorage(path: dir.appendingPathComponent("t.sqlite").path))
        let tasks = TaskStore(fileURL: dir.appendingPathComponent("tasks.sqlite"))
        let service = JiraService(defaults: defaults,
                                  store: JiraTokenStore(defaults: defaults,
                                                        readToken: { _, _ in nil },
                                                        writeToken: { _, _, _ in },
                                                        deleteToken: { _, _ in }),
                                  oauthConfig: nil, issueCache: storage,
                                  taskStore: tasks, restoreOnInit: false)
        return (service, storage, tasks, defaults)
    }

    @Test("a pomodoro on a linked task queues a worklog against its issue")
    @MainActor
    func pomodoroQueuesWorklog() throws {
        let (service, storage, tasks, _) = try makeService()
        let task = TaskItem(title: "API to terminate all sessions",
                            jiraKey: "WT-689", jiraIssueID: "1",
                            jiraSiteHost: "wayll.atlassian.net")
        tasks.upsertJiraTask(task)

        service.pomodoroCompleted(taskID: task.id, subtaskID: nil, seconds: 1500,
                                  completedAt: Date(timeIntervalSince1970: 1_800_000_000))

        let due = storage.dueItems(now: Date())
        #expect(due.count == 1)
        #expect(due.first?.issueKey == "WT-689")
        #expect(due.first?.op == .worklog)
        let w = try JSONDecoder().decode(JiraWorklogPayload.self,
                                         from: Data(try #require(due.first?.payload).utf8))
        #expect(w.timeSpentSeconds == 1500)
    }

    @Test("a pomodoro on a linked subtask targets the sub-task issue, not the parent")
    @MainActor
    func pomodoroOnSubtaskTargetsSubtask() throws {
        let (service, storage, tasks, _) = try makeService()
        var task = TaskItem(title: "Parent", jiraKey: "WT-689", jiraIssueID: "1",
                            jiraSiteHost: "wayll.atlassian.net")
        let sub = Subtask(title: "Write endpoint", jiraKey: "WT-702", jiraIssueID: "3")
        task.subtasks = [sub]
        tasks.upsertJiraTask(task)

        service.pomodoroCompleted(taskID: task.id, subtaskID: sub.id, seconds: 1500,
                                  completedAt: Date())

        let due = storage.dueItems(now: Date())
        #expect(due.first?.issueKey == "WT-702")
    }

    @Test("a sub-minute session is skipped — Jira rejects worklogs under a minute")
    @MainActor
    func subMinuteSkipped() throws {
        let (service, storage, tasks, _) = try makeService()
        let task = TaskItem(title: "T", jiraKey: "WT-1", jiraIssueID: "1",
                            jiraSiteHost: "wayll.atlassian.net")
        tasks.upsertJiraTask(task)
        service.pomodoroCompleted(taskID: task.id, subtaskID: nil, seconds: 40, completedAt: Date())
        #expect(storage.pendingCount() == 0)
    }

    @Test("worklog sync off queues nothing")
    @MainActor
    func worklogSyncOffQueuesNothing() throws {
        let (service, storage, tasks, defaults) = try makeService()
        defaults.set(false, forKey: JiraService.worklogSyncDefaultsKey)
        let task = TaskItem(title: "T", jiraKey: "WT-1", jiraIssueID: "1",
                            jiraSiteHost: "wayll.atlassian.net")
        tasks.upsertJiraTask(task)
        service.pomodoroCompleted(taskID: task.id, subtaskID: nil, seconds: 1500, completedAt: Date())
        #expect(storage.pendingCount() == 0)
    }
}
