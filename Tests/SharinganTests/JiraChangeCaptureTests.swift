import Foundation
import Testing
@testable import SharinganCore

// Two-way sync, the outbound half: a local edit to a linked task becomes a
// queued `fields` op — never an immediate network call. The diff runs against
// the last-seen snapshot (what Jira looked like at the previous sync), and
// repeated edits to one issue coalesce into a single queued item.
@Suite("Jira change capture")
struct JiraChangeCaptureTests {

    private func snapshot(summary: String = "API to terminate all sessions",
                          priorityName: String? = "High",
                          labels: [String] = ["backend"],
                          components: [String] = ["Auth"],
                          dueDate: String? = nil) -> CachedJiraIssue {
        CachedJiraIssue(issueID: "1", issueKey: "WT-689",
                        siteHost: "wayll.atlassian.net", summary: summary,
                        statusID: nil, statusName: "In Progress",
                        statusCategory: "indeterminate", issueType: "Story",
                        priorityName: priorityName, assigneeName: nil,
                        labels: labels, components: components,
                        projectKey: "WT", dueDate: dueDate,
                        estimateSeconds: nil, descriptionADF: nil,
                        jiraUpdated: nil, fetchedAt: Date())
    }

    private func linkedTask(title: String = "API to terminate all sessions",
                            tags: [String] = ["backend", "Auth"],
                            priority: TaskPriority = .high,
                            dueDate: Date? = nil) -> TaskItem {
        TaskItem(title: title, tags: tags, dueDate: dueDate,
                 priority: priority,
                 jiraKey: "WT-689", jiraIssueID: "1",
                 jiraSiteHost: "wayll.atlassian.net")
    }

    // MARK: - The pure diff

    @Test("an unchanged task produces nothing to push")
    func unchangedIsEmpty() {
        let push = JiraFieldMapper.pushFields(local: linkedTask(),
                                              lastSeen: snapshot())
        #expect(push.isEmpty)
    }

    @Test("a locally renamed task pushes its summary")
    func renamePushesSummary() {
        let push = JiraFieldMapper.pushFields(local: linkedTask(title: "Renamed"),
                                              lastSeen: snapshot())
        #expect(push.summary == "Renamed")
        #expect(push.priorityName == nil)
    }

    @Test("a changed priority pushes Jira's name for it")
    func priorityPushesName() {
        let push = JiraFieldMapper.pushFields(local: linkedTask(priority: .medium),
                                              lastSeen: snapshot(priorityName: "High"))
        #expect(push.priorityName == "Medium")
    }

    @Test("a new tag pushes as a label; imported components never do")
    func tagsPushAsLabelsWithoutComponents() {
        let push = JiraFieldMapper.pushFields(
            local: linkedTask(tags: ["backend", "Auth", "code review"]),
            lastSeen: snapshot(labels: ["backend"], components: ["Auth"]))
        // "Auth" came in as a component — pushing it as a label would duplicate
        // it on the Jira side. The new tag is spaced, so it label-normalizes.
        #expect(push.labels == ["backend", "code-review"])
    }

    @Test("a changed due date pushes in Jira's wire format")
    func dueDatePushes() throws {
        let due = try #require(JiraFieldMapper.date(fromJiraDueDate: "2026-07-20"))
        let push = JiraFieldMapper.pushFields(local: linkedTask(dueDate: due),
                                              lastSeen: snapshot(dueDate: "2026-07-18"))
        #expect(push.duedate == "2026-07-20")
    }

    // MARK: - Capture into the queue

    @MainActor
    private func makeService(mode: String) throws -> (JiraService, JiraStorage, TaskStore, UserDefaults) {
        let suite = "jira-capture-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set(mode, forKey: JiraService.syncModeDefaultsKey)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("jira-capture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storage = try #require(JiraStorage(path: dir.appendingPathComponent("t.sqlite").path))
        let tasks = TaskStore(fileURL: dir.appendingPathComponent("tasks.sqlite"))
        let service = JiraService(defaults: defaults,
                                  store: JiraTokenStore(
                                    defaults: defaults,
                                    readToken: { _, _ in nil },
                                    writeToken: { _, _, _ in },
                                    deleteToken: { _, _ in }),
                                  oauthConfig: nil,
                                  issueCache: storage,
                                  taskStore: tasks,
                                  restoreOnInit: false)
        return (service, storage, tasks, defaults)
    }

    @Test("two edits to one issue coalesce into a single queued item")
    @MainActor
    func editsCoalesce() throws {
        let (service, storage, _, _) = try makeService(mode: "twoWay")
        storage.upsertIssue(snapshot())

        var task = linkedTask()
        task.title = "First rename"
        service.taskDidChange(task)
        task.title = "Second rename"
        service.taskDidChange(task)

        let due = storage.dueItems(now: Date())
        #expect(due.count == 1)
        let push = try JSONDecoder().decode(JiraPushFields.self,
                                            from: Data(try #require(due.first?.payload).utf8))
        #expect(push.summary == "Second rename")
    }

    @Test("pull mode queues nothing — one-way stays one-way")
    @MainActor
    func pullModeQueuesNothing() throws {
        let (service, storage, _, _) = try makeService(mode: "pull")
        storage.upsertIssue(snapshot())
        var task = linkedTask()
        task.title = "Renamed while one-way"
        service.taskDidChange(task)
        #expect(storage.pendingCount() == 0)
    }

    @Test("an edit indistinguishable from the snapshot queues nothing")
    @MainActor
    func noopEditQueuesNothing() throws {
        let (service, storage, _, _) = try makeService(mode: "twoWay")
        storage.upsertIssue(snapshot())
        service.taskDidChange(linkedTask())
        #expect(storage.pendingCount() == 0)
    }
}
