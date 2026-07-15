import Foundation
import Testing
@testable import SharinganCore

@Suite("Jira mapping")
struct JiraMappingTests {

    // MARK: - Fixtures

    private static func fields(summary: String? = "Ship the thing",
                               priority: String? = nil,
                               labels: [String]? = nil,
                               duedate: String? = nil,
                               estimateSeconds: Int? = nil,
                               projectKey: String? = nil,
                               components: [String]? = nil,
                               statusName: String = "In Progress",
                               statusCategory: String = "indeterminate") -> JiraIssueFields {
        JiraIssueFields(
            summary: summary,
            status: JiraStatus(name: statusName,
                               statusCategory: JiraStatusCategory(key: statusCategory,
                                                                  name: statusName,
                                                                  colorName: nil)),
            priority: priority.map { JiraPriority(id: "1", name: $0, iconUrl: nil) },
            labels: labels,
            duedate: duedate,
            timeoriginalestimate: estimateSeconds,
            description: nil,
            project: projectKey.map { JiraProject(key: $0, name: "\($0) project", id: "10000") },
            issuetype: JiraIssueType(id: "10001", name: "Task", iconUrl: nil, subtask: false),
            components: components?.map { JiraComponent(id: nil, name: $0, description: nil) },
            updated: "2026-07-15T09:31:04.123+0000",
            assignee: JiraUser(accountId: "abc123", displayName: "Dev User",
                               emailAddress: nil, active: true),
            reporter: nil,
            created: nil,
            resolution: nil,
            fixVersions: nil,
            customfield_10020: nil)
    }

    private static func issue(_ fields: JiraIssueFields, key: String = "SHR-1", id: String = "10100") -> JiraIssue {
        JiraIssue(id: id, key: key,
                  selfLink: "https://example.atlassian.net/rest/api/3/issue/\(id)",
                  fields: fields, editMeta: nil)
    }

    private static func linkedTask(title: String = "Ship the thing",
                                   tags: [String] = [],
                                   priority: TaskPriority = .none,
                                   dueDate: Date? = nil,
                                   estimate: Int? = nil) -> TaskItem {
        TaskItem(title: title,
                 tags: tags,
                 dueDate: dueDate,
                 estimatedPomodoros: estimate,
                 priority: priority,
                 jiraKey: "SHR-1",
                 jiraIssueID: "10100",
                 jiraSiteHost: "example.atlassian.net")
    }

    /// A snapshot that agrees with `linkedTask()` on every field — the base
    /// every merge test perturbs exactly one side of.
    private static func snapshot(summary: String = "Ship the thing",
                                 priorityName: String? = nil,
                                 labels: [String] = [],
                                 components: [String] = [],
                                 dueDate: String? = nil,
                                 estimateSeconds: Int? = nil) -> CachedJiraIssue {
        CachedJiraIssue(issueID: "10100",
                        issueKey: "SHR-1",
                        siteHost: "example.atlassian.net",
                        summary: summary,
                        priorityName: priorityName,
                        labels: labels,
                        components: components,
                        dueDate: dueDate,
                        estimateSeconds: estimateSeconds)
    }

    private static func day(_ string: String) -> Date {
        var c = DateComponents()
        let parts = string.split(separator: "-").compactMap { Int($0) }
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.date(from: c)!
    }

    // MARK: - Priority

    @Test("Jira priority names map to local flags",
          arguments: [("Highest", 3), ("High", 3), ("Medium", 2), ("Low", 1), ("Lowest", 1)])
    func priorityPull(name: String, expected: Int) {
        #expect(JiraFieldMapper.priority(fromJiraName: name).rawValue == expected)
    }

    @Test("Unknown and absent Jira priorities fall back to no flag")
    func priorityPullUnknown() {
        #expect(JiraFieldMapper.priority(fromJiraName: nil) == .none)
        #expect(JiraFieldMapper.priority(fromJiraName: "Blocker") == .none)
        #expect(JiraFieldMapper.priority(fromJiraName: "") == .none)
    }

    @Test("Priority names are matched case- and whitespace-insensitively")
    func priorityPullNormalizes() {
        #expect(JiraFieldMapper.priority(fromJiraName: " high ") == .high)
        #expect(JiraFieldMapper.priority(fromJiraName: "MEDIUM") == .medium)
    }

    @Test("Local flags map back to Jira priority names")
    func priorityPush() {
        #expect(JiraFieldMapper.jiraPriorityName(from: .high) == "High")
        #expect(JiraFieldMapper.jiraPriorityName(from: .medium) == "Medium")
        #expect(JiraFieldMapper.jiraPriorityName(from: .low) == "Low")
        // .none means "no opinion", not "clear Jira's priority".
        #expect(JiraFieldMapper.jiraPriorityName(from: .none) == nil)
        // Custom levels above P1 have no Jira equivalent either.
        #expect(JiraFieldMapper.jiraPriorityName(from: TaskPriority(rawValue: 7)) == nil)
    }

    // MARK: - Estimates

    @Test("Jira estimate seconds round up to whole pomodoros",
          arguments: [(1500, 1), (1501, 2), (1, 1), (3000, 2), (3001, 3), (7500, 5)])
    func estimatePull(seconds: Int, expected: Int) {
        #expect(JiraFieldMapper.pomodoros(fromEstimateSeconds: seconds) == expected)
    }

    @Test("Zero and absent estimates mean no estimate")
    func estimatePullEmpty() {
        #expect(JiraFieldMapper.pomodoros(fromEstimateSeconds: 0) == nil)
        #expect(JiraFieldMapper.pomodoros(fromEstimateSeconds: nil) == nil)
        #expect(JiraFieldMapper.pomodoros(fromEstimateSeconds: -60) == nil)
    }

    @Test("Pomodoros convert back to seconds")
    func estimatePush() {
        #expect(JiraFieldMapper.estimateSeconds(fromPomodoros: 1) == 1500)
        #expect(JiraFieldMapper.estimateSeconds(fromPomodoros: 4) == 6000)
        #expect(JiraFieldMapper.estimateSeconds(fromPomodoros: nil) == nil)
        #expect(JiraFieldMapper.estimateSeconds(fromPomodoros: 0) == nil)
    }

    // MARK: - Labels

    @Test("Local tags become Jira labels with spaces dashed")
    func labelPush() {
        #expect(JiraFieldMapper.jiraLabel(from: "backend") == "backend")
        #expect(JiraFieldMapper.jiraLabel(from: "code review") == "code-review")
        #expect(JiraFieldMapper.jiraLabel(from: "  needs design  ") == "needs-design")
    }

    @Test("Label round-trip is stable once dashed")
    func labelRoundTrip() throws {
        let local = TaskItem(title: "T", tags: ["code review", "backend"],
                             jiraKey: "SHR-1", jiraIssueID: "10100",
                             jiraSiteHost: "example.atlassian.net")
        let remote = Self.issue(Self.fields(labels: []))
        let first = JiraFieldMapper.merge(local: local, remote: remote, lastSeen: Self.snapshot())
        let pushed = try #require(first.fieldsToPush.labels)
        #expect(pushed == ["code-review", "backend"])

        // Jira now holds the dashed labels; pulling them back and merging again
        // must be a no-op rather than a fresh push.
        let echoed = Self.issue(Self.fields(labels: pushed))
        let second = JiraFieldMapper.merge(local: first.mergedTask,
                                           remote: echoed,
                                           lastSeen: Self.snapshot(labels: pushed))
        #expect(second.mergedTask.tags == ["code-review", "backend"])
        #expect(second.fieldsToPush.labels == nil)
        #expect(second.conflicts.isEmpty)
    }

    // MARK: - Due dates

    @Test("Due dates cross the boundary as yyyy-MM-dd in UTC")
    func dueDateMapping() throws {
        let parsed = try #require(JiraFieldMapper.date(fromJiraDueDate: "2026-07-15"))
        #expect(JiraFieldMapper.jiraDueDate(from: parsed) == "2026-07-15")
        #expect(JiraFieldMapper.date(fromJiraDueDate: nil) == nil)
        #expect(JiraFieldMapper.date(fromJiraDueDate: "") == nil)
        #expect(JiraFieldMapper.date(fromJiraDueDate: "not-a-date") == nil)
        #expect(JiraFieldMapper.jiraDueDate(from: nil) == nil)
    }

    // MARK: - Import

    @Test("A fresh issue imports as a linked task")
    func importsFreshIssue() throws {
        let issue = Self.issue(Self.fields(summary: "Fix the parser",
                                           priority: "High",
                                           labels: ["backend", "urgent"],
                                           duedate: "2026-07-20",
                                           estimateSeconds: 3600,
                                           projectKey: "SHR",
                                           components: ["API"]))
        let task = JiraFieldMapper.taskItem(from: issue, siteHost: "example.atlassian.net")

        #expect(task.title == "Fix the parser")
        #expect(task.priority == .high)
        #expect(task.tags == ["backend", "urgent", "API"])
        #expect(task.dueDate == Self.day("2026-07-20"))
        #expect(task.estimatedPomodoros == 3)          // 3600s → ceil(2.4)
        #expect(task.project == "SHR")
        #expect(task.category == "SHR")
        #expect(task.jiraKey == "SHR-1")
        #expect(task.jiraIssueID == "10100")
        #expect(task.jiraSiteHost == "example.atlassian.net")
        // Status is "In Progress" — completion is never inferred from it.
        #expect(!task.isDone)
    }

    @Test("An issue with no summary falls back to its key")
    func importsIssueWithoutSummary() {
        let task = JiraFieldMapper.taskItem(from: Self.issue(Self.fields(summary: nil)),
                                            siteHost: "example.atlassian.net")
        #expect(task.title == "SHR-1")
    }

    // MARK: - Three-way merge: summary

    @Test("Summary: Jira changed, local didn't → pull")
    func summaryPulls() {
        let outcome = JiraFieldMapper.merge(local: Self.linkedTask(),
                                            remote: Self.issue(Self.fields(summary: "Ship it faster")),
                                            lastSeen: Self.snapshot())
        #expect(outcome.mergedTask.title == "Ship it faster")
        #expect(outcome.fieldsToPush.summary == nil)
        #expect(outcome.conflicts.isEmpty)
    }

    @Test("Summary: local changed, Jira didn't → push")
    func summaryPushes() {
        let outcome = JiraFieldMapper.merge(local: Self.linkedTask(title: "Ship it locally"),
                                            remote: Self.issue(Self.fields()),
                                            lastSeen: Self.snapshot())
        #expect(outcome.mergedTask.title == "Ship it locally")
        #expect(outcome.fieldsToPush.summary == "Ship it locally")
        #expect(outcome.conflicts.isEmpty)
    }

    @Test("Summary: both changed → Jira wins and the conflict is reported")
    func summaryConflicts() {
        let outcome = JiraFieldMapper.merge(local: Self.linkedTask(title: "Local title"),
                                            remote: Self.issue(Self.fields(summary: "Remote title")),
                                            lastSeen: Self.snapshot())
        #expect(outcome.mergedTask.title == "Remote title")
        #expect(outcome.fieldsToPush.summary == nil)
        #expect(outcome.conflicts == ["summary"])
    }

    @Test("Summary: neither changed → no-op")
    func summaryNoop() {
        let outcome = JiraFieldMapper.merge(local: Self.linkedTask(),
                                            remote: Self.issue(Self.fields()),
                                            lastSeen: Self.snapshot())
        #expect(outcome.mergedTask.title == "Ship the thing")
        #expect(outcome.fieldsToPush.isEmpty)
        #expect(outcome.conflicts.isEmpty)
    }

    @Test("Both sides making the same edit is convergence, not a conflict")
    func summaryConverges() {
        let outcome = JiraFieldMapper.merge(local: Self.linkedTask(title: "Same new title"),
                                            remote: Self.issue(Self.fields(summary: "Same new title")),
                                            lastSeen: Self.snapshot())
        #expect(outcome.mergedTask.title == "Same new title")
        #expect(outcome.fieldsToPush.isEmpty)
        #expect(outcome.conflicts.isEmpty)
    }

    // MARK: - Three-way merge: priority

    @Test("Priority: Jira changed, local didn't → pull")
    func priorityPulls() {
        let outcome = JiraFieldMapper.merge(local: Self.linkedTask(priority: .low),
                                            remote: Self.issue(Self.fields(priority: "Highest")),
                                            lastSeen: Self.snapshot(priorityName: "Low"))
        #expect(outcome.mergedTask.priority == .high)
        #expect(outcome.fieldsToPush.priorityName == nil)
        #expect(outcome.conflicts.isEmpty)
    }

    @Test("Priority: local changed, Jira didn't → push")
    func priorityPushes() {
        let outcome = JiraFieldMapper.merge(local: Self.linkedTask(priority: .medium),
                                            remote: Self.issue(Self.fields(priority: "Low")),
                                            lastSeen: Self.snapshot(priorityName: "Low"))
        #expect(outcome.mergedTask.priority == .medium)
        #expect(outcome.fieldsToPush.priorityName == "Medium")
        #expect(outcome.conflicts.isEmpty)
    }

    @Test("Priority: both changed → Jira wins")
    func priorityConflicts() {
        let outcome = JiraFieldMapper.merge(local: Self.linkedTask(priority: .low),
                                            remote: Self.issue(Self.fields(priority: "High")),
                                            lastSeen: Self.snapshot(priorityName: "Medium"))
        #expect(outcome.mergedTask.priority == .high)
        #expect(outcome.fieldsToPush.priorityName == nil)
        #expect(outcome.conflicts == ["priority"])
    }

    @Test("Priority: neither changed → no-op")
    func priorityNoop() {
        let outcome = JiraFieldMapper.merge(local: Self.linkedTask(priority: .medium),
                                            remote: Self.issue(Self.fields(priority: "Medium")),
                                            lastSeen: Self.snapshot(priorityName: "Medium"))
        #expect(outcome.mergedTask.priority == .medium)
        #expect(outcome.fieldsToPush.isEmpty)
        #expect(outcome.conflicts.isEmpty)
    }

    @Test("Priority: a Jira rename within one bucket isn't a change")
    func priorityRenameIsNotAChange() {
        // "Highest" and "High" both mean P1 locally — pulling one over the
        // other must not manufacture a push or a conflict.
        let outcome = JiraFieldMapper.merge(local: Self.linkedTask(priority: .high),
                                            remote: Self.issue(Self.fields(priority: "Highest")),
                                            lastSeen: Self.snapshot(priorityName: "High"))
        #expect(outcome.fieldsToPush.isEmpty)
        #expect(outcome.conflicts.isEmpty)
    }

    @Test("Priority: clearing the flag locally never pushes")
    func priorityNoneNeverPushes() {
        let outcome = JiraFieldMapper.merge(local: Self.linkedTask(priority: .none),
                                            remote: Self.issue(Self.fields(priority: "High")),
                                            lastSeen: Self.snapshot(priorityName: "High"))
        #expect(outcome.fieldsToPush.priorityName == nil)
        #expect(outcome.mergedTask.priority == .none)
    }

    // MARK: - Three-way merge: due date

    @Test("Due date: Jira changed, local didn't → pull")
    func dueDatePulls() {
        let outcome = JiraFieldMapper.merge(local: Self.linkedTask(dueDate: Self.day("2026-07-15")),
                                            remote: Self.issue(Self.fields(duedate: "2026-07-20")),
                                            lastSeen: Self.snapshot(dueDate: "2026-07-15"))
        #expect(outcome.mergedTask.dueDate == Self.day("2026-07-20"))
        #expect(outcome.fieldsToPush.duedate == nil)
        #expect(outcome.conflicts.isEmpty)
    }

    @Test("Due date: local changed, Jira didn't → push")
    func dueDatePushes() {
        let outcome = JiraFieldMapper.merge(local: Self.linkedTask(dueDate: Self.day("2026-07-22")),
                                            remote: Self.issue(Self.fields(duedate: "2026-07-15")),
                                            lastSeen: Self.snapshot(dueDate: "2026-07-15"))
        #expect(outcome.fieldsToPush.duedate == "2026-07-22")
        #expect(outcome.mergedTask.dueDate == Self.day("2026-07-22"))
        #expect(outcome.conflicts.isEmpty)
    }

    @Test("Due date: both changed → Jira wins")
    func dueDateConflicts() {
        let outcome = JiraFieldMapper.merge(local: Self.linkedTask(dueDate: Self.day("2026-07-22")),
                                            remote: Self.issue(Self.fields(duedate: "2026-07-30")),
                                            lastSeen: Self.snapshot(dueDate: "2026-07-15"))
        #expect(outcome.mergedTask.dueDate == Self.day("2026-07-30"))
        #expect(outcome.conflicts == ["duedate"])
    }

    @Test("Due date: neither changed → no-op")
    func dueDateNoop() {
        let outcome = JiraFieldMapper.merge(local: Self.linkedTask(dueDate: Self.day("2026-07-15")),
                                            remote: Self.issue(Self.fields(duedate: "2026-07-15")),
                                            lastSeen: Self.snapshot(dueDate: "2026-07-15"))
        #expect(outcome.fieldsToPush.isEmpty)
        #expect(outcome.conflicts.isEmpty)
    }

    // MARK: - Three-way merge: estimate

    @Test("Estimate: Jira changed, local didn't → pull")
    func estimatePulls() {
        let outcome = JiraFieldMapper.merge(local: Self.linkedTask(estimate: 1),
                                            remote: Self.issue(Self.fields(estimateSeconds: 4500)),
                                            lastSeen: Self.snapshot(estimateSeconds: 1500))
        #expect(outcome.mergedTask.estimatedPomodoros == 3)
        #expect(outcome.conflicts.isEmpty)
    }

    @Test("Estimate: local changed → pushes only behind the caller's flag")
    func estimatePushesBehindFlag() {
        let local = Self.linkedTask(estimate: 4)
        let remote = Self.issue(Self.fields(estimateSeconds: 1500))
        let base = Self.snapshot(estimateSeconds: 1500)

        let off = JiraFieldMapper.merge(local: local, remote: remote, lastSeen: base)
        #expect(off.fieldsToPush.timeoriginalestimate == nil)
        #expect(off.mergedTask.estimatedPomodoros == 4)

        let on = JiraFieldMapper.merge(local: local, remote: remote, lastSeen: base, pushEstimate: true)
        #expect(on.fieldsToPush.timeoriginalestimate == 6000)
    }

    @Test("Estimate: both changed → Jira wins")
    func estimateConflicts() {
        let outcome = JiraFieldMapper.merge(local: Self.linkedTask(estimate: 4),
                                            remote: Self.issue(Self.fields(estimateSeconds: 3000)),
                                            lastSeen: Self.snapshot(estimateSeconds: 1500),
                                            pushEstimate: true)
        #expect(outcome.mergedTask.estimatedPomodoros == 2)
        #expect(outcome.fieldsToPush.timeoriginalestimate == nil)
        #expect(outcome.conflicts == ["timeoriginalestimate"])
    }

    @Test("Estimate: neither changed → no-op")
    func estimateNoop() {
        let outcome = JiraFieldMapper.merge(local: Self.linkedTask(estimate: 1),
                                            remote: Self.issue(Self.fields(estimateSeconds: 1500)),
                                            lastSeen: Self.snapshot(estimateSeconds: 1500),
                                            pushEstimate: true)
        #expect(outcome.fieldsToPush.isEmpty)
        #expect(outcome.conflicts.isEmpty)
    }

    // MARK: - Three-way merge: labels (set-diff)

    @Test("Labels: a local add and a different Jira add both survive")
    func labelSetDiffKeepsBothAdds() throws {
        let outcome = JiraFieldMapper.merge(
            local: Self.linkedTask(tags: ["backend", "mine"]),
            remote: Self.issue(Self.fields(labels: ["backend", "theirs"])),
            lastSeen: Self.snapshot(labels: ["backend"]))

        #expect(Set(outcome.mergedTask.tags) == ["backend", "mine", "theirs"])
        let pushed = try #require(outcome.fieldsToPush.labels)
        #expect(Set(pushed) == ["backend", "mine", "theirs"])
        // Labels compose — there is nothing for Jira to win.
        #expect(outcome.conflicts.isEmpty)
    }

    @Test("Labels: a remove on either side propagates")
    func labelSetDiffPropagatesRemoves() {
        let localRemoved = JiraFieldMapper.merge(
            local: Self.linkedTask(tags: ["backend"]),
            remote: Self.issue(Self.fields(labels: ["backend", "stale"])),
            lastSeen: Self.snapshot(labels: ["backend", "stale"]))
        #expect(localRemoved.mergedTask.tags == ["backend"])
        #expect(localRemoved.fieldsToPush.labels == ["backend"])

        let remoteRemoved = JiraFieldMapper.merge(
            local: Self.linkedTask(tags: ["backend", "stale"]),
            remote: Self.issue(Self.fields(labels: ["backend"])),
            lastSeen: Self.snapshot(labels: ["backend", "stale"]))
        #expect(remoteRemoved.mergedTask.tags == ["backend"])
        #expect(remoteRemoved.fieldsToPush.labels == nil)   // already matches Jira
    }

    @Test("Labels: Jira-only label adds pull without pushing back")
    func labelPullOnly() {
        let outcome = JiraFieldMapper.merge(
            local: Self.linkedTask(tags: ["backend"]),
            remote: Self.issue(Self.fields(labels: ["backend", "triage"])),
            lastSeen: Self.snapshot(labels: ["backend"]))
        #expect(outcome.mergedTask.tags == ["backend", "triage"])
        #expect(outcome.fieldsToPush.labels == nil)
        #expect(outcome.fieldsToPush.isEmpty)
    }

    @Test("Labels: component tags are never pushed to Jira as labels")
    func componentTagsStayLocal() {
        // "API" arrived as a component, so it lives in tags but must not look
        // like a local label add.
        let outcome = JiraFieldMapper.merge(
            local: Self.linkedTask(tags: ["backend", "API"]),
            remote: Self.issue(Self.fields(labels: ["backend"], components: ["API"])),
            lastSeen: Self.snapshot(labels: ["backend"], components: ["API"]))
        #expect(outcome.fieldsToPush.labels == nil)
        #expect(outcome.mergedTask.tags.contains("API"))
    }

    // MARK: - Three-way merge: no snapshot

    @Test("Without a snapshot Jira wins silently and labels union")
    func mergeWithoutSnapshot() {
        let outcome = JiraFieldMapper.merge(
            local: Self.linkedTask(title: "Local title", tags: ["mine"], priority: .low),
            remote: Self.issue(Self.fields(summary: "Remote title",
                                           priority: "High",
                                           labels: ["theirs"])),
            lastSeen: nil)
        #expect(outcome.mergedTask.title == "Remote title")
        #expect(outcome.mergedTask.priority == .high)
        #expect(Set(outcome.mergedTask.tags) == ["mine", "theirs"])
        // A first link adopting Jira's values is expected, not a conflict.
        #expect(outcome.conflicts.isEmpty)
    }

    // MARK: - Merge: identity and non-mappings

    @Test("Merge refreshes the issue key and never touches completion")
    func mergeKeepsIdentityAndCompletion() {
        var local = Self.linkedTask()
        local.isDone = true
        let moved = Self.issue(Self.fields(summary: "Ship the thing", projectKey: "OPS"),
                               key: "OPS-9", id: "10100")
        let outcome = JiraFieldMapper.merge(local: local, remote: moved, lastSeen: Self.snapshot())

        #expect(outcome.mergedTask.jiraKey == "OPS-9")
        #expect(outcome.mergedTask.jiraIssueID == "10100")
        #expect(outcome.mergedTask.project == "OPS")
        // Status said "In Progress"; the task stays done because Jira status
        // never drives local completion.
        #expect(outcome.mergedTask.isDone)
    }

    // MARK: - Snapshot

    @Test("A fetched issue snapshots every Jira-owned field")
    func snapshotsIssue() throws {
        let issue = Self.issue(Self.fields(summary: "Fix the parser",
                                           priority: "High",
                                           labels: ["backend"],
                                           duedate: "2026-07-20",
                                           estimateSeconds: 3600,
                                           projectKey: "SHR",
                                           components: ["API"]))
        let cached = JiraFieldMapper.snapshot(from: issue, siteHost: "example.atlassian.net")

        #expect(cached.issueID == "10100")
        #expect(cached.issueKey == "SHR-1")
        #expect(cached.summary == "Fix the parser")
        #expect(cached.priorityName == "High")
        #expect(cached.labels == ["backend"])
        #expect(cached.components == ["API"])
        #expect(cached.projectKey == "SHR")
        #expect(cached.dueDate == "2026-07-20")
        #expect(cached.estimateSeconds == 3600)
        #expect(cached.statusName == "In Progress")
        #expect(cached.statusCategory == "indeterminate")
        #expect(cached.assigneeName == "Dev User")
        #expect(try #require(cached.jiraUpdated).timeIntervalSince1970 > 0)
    }

    // MARK: - Storage (temp file only — never the real app database)

    /// Dates are stored the way `TaskDatabase` stores them: epoch seconds in a
    /// REAL column. `Date` holds its interval relative to 2001, so adding the
    /// epoch offset on write and subtracting it on read can land a bit-pattern
    /// away from the original — sub-microsecond, irrelevant for a "when did we
    /// fetch this" stamp, but enough to make `==` on a raw `Date()` flaky. The
    /// storage tests therefore pin a whole-second timestamp, which is exact.
    private static let fetchStamp = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStorage() throws -> (JiraStorage, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("jira-storage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("blink.sqlite")
        return (try #require(JiraStorage(path: url.path)), dir)
    }

    @Test("Cached issues round-trip through SQLite")
    func storageRoundTripsIssues() throws {
        let (storage, dir) = try makeStorage()
        defer { try? FileManager.default.removeItem(at: dir) }

        let issue = Self.issue(Self.fields(labels: ["backend"], duedate: "2026-07-20",
                                           estimateSeconds: 3600, projectKey: "SHR",
                                           components: ["API"]))
        let cached = JiraFieldMapper.snapshot(from: issue, siteHost: "example.atlassian.net",
                                              fetchedAt: Self.fetchStamp)
        storage.upsertIssue(cached)

        let byID = try #require(storage.issue(id: "10100"))
        #expect(byID == cached)
        #expect(storage.issue(key: "SHR-1") == cached)
        #expect(storage.allIssues().count == 1)

        // Upsert replaces rather than duplicating — the row is a snapshot.
        var moved = cached
        moved.summary = "Renamed upstream"
        moved.labels = ["backend", "triage"]
        storage.upsertIssue(moved)
        #expect(storage.allIssues().count == 1)
        #expect(storage.issue(id: "10100")?.summary == "Renamed upstream")
        #expect(storage.issue(id: "10100")?.labels == ["backend", "triage"])

        storage.deleteIssue(id: "10100")
        #expect(storage.issue(id: "10100") == nil)
        #expect(storage.allIssues().isEmpty)
    }

    @Test("The outbox hands back only items whose backoff has elapsed")
    func storageOutboxDueItems() throws {
        let (storage, dir) = try makeStorage()
        defer { try? FileManager.default.removeItem(at: dir) }

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let ready = OutboxItem(issueKey: "SHR-1", payload: #"{"timeSpentSeconds":1500}"#,
                               createdAt: now.addingTimeInterval(-60))
        let backingOff = OutboxItem(issueKey: "SHR-2", payload: "{}",
                                    createdAt: now.addingTimeInterval(-30),
                                    attempts: 2,
                                    nextAttemptAt: now.addingTimeInterval(300))
        let dead = OutboxItem(issueKey: "SHR-3", payload: "{}", createdAt: now,
                              attempts: 9, failed: true, lastError: "410 Gone")
        for item in [ready, backingOff, dead] { storage.enqueue(item) }

        #expect(storage.pendingCount() == 3)
        #expect(storage.dueItems(now: now).map(\.issueKey) == ["SHR-1"])
        #expect(storage.dueItems(now: now.addingTimeInterval(600)).map(\.issueKey) == ["SHR-1", "SHR-2"])
        #expect(storage.failedItems().map(\.issueKey) == ["SHR-3"])
        #expect(storage.failedItems().first?.lastError == "410 Gone")

        let stored = try #require(storage.dueItems(now: now).first)
        #expect(stored == ready)

        // A failed attempt writes back the backoff.
        var retried = ready
        retried.attempts = 1
        retried.nextAttemptAt = now.addingTimeInterval(60)
        retried.lastError = "503"
        storage.update(retried)
        #expect(storage.dueItems(now: now).isEmpty)
        #expect(storage.dueItems(now: now.addingTimeInterval(120)).first == retried)

        storage.delete(id: ready.id)
        #expect(storage.pendingCount() == 2)
    }

    @Test("A second connection to the same file sees the first one's writes")
    func storageSurvivesReopen() throws {
        let (storage, dir) = try makeStorage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("blink.sqlite")

        let cached = JiraFieldMapper.snapshot(from: Self.issue(Self.fields()),
                                              siteHost: "example.atlassian.net",
                                              fetchedAt: Self.fetchStamp)
        storage.upsertIssue(cached)
        storage.enqueue(OutboxItem(issueKey: "SHR-1", payload: "{}"))

        // WAL is what makes the app's second connection to blink.sqlite safe.
        let reopened = try #require(JiraStorage(path: url.path))
        #expect(reopened.issue(id: "10100") == cached)
        #expect(reopened.pendingCount() == 1)
    }
}
