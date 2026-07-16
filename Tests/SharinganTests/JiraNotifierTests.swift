import Foundation
import Testing
@testable import SharinganCore

@Suite("Jira smart notifications")
struct JiraNotifierTests {

    // MARK: - Fixtures

    /// A recorder standing in for `NotificationService.notify`.
    final class Recorder: @unchecked Sendable {
        private(set) var fired: [(title: String, body: String, id: String)] = []
        var ids: [String] { fired.map(\.id) }
        var count: Int { fired.count }
        func reset() { fired = [] }
        var notify: (String, String, String) -> Void {
            { [self] title, body, id in fired.append((title, body, id)) }
        }
    }

    /// A UserDefaults suite scrubbed clean for one test.
    static func freshDefaults(_ name: String) throws -> UserDefaults {
        let suite = "JiraNotifierTests.\(name)"
        let d = try #require(UserDefaults(suiteName: suite))
        d.removePersistentDomain(forName: suite)
        return d
    }

    /// UTC everywhere so "today" doesn't depend on the machine running the test.
    static var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = try! #require(TimeZone(identifier: "UTC"))
        return c
    }

    static func date(_ iso: String) throws -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return try #require(f.date(from: iso))
    }

    static func issue(_ key: String, summary: String = "Do the thing",
                      duedate: String? = nil) -> JiraIssue {
        JiraIssue(id: key, key: key, selfLink: "",
                  fields: JiraIssueFields(
                    summary: summary, status: nil, priority: nil, labels: nil,
                    duedate: duedate, timeoriginalestimate: nil, description: nil,
                    project: nil, issuetype: nil, components: nil, updated: nil,
                    assignee: nil, reporter: nil, created: nil, resolution: nil,
                    fixVersions: nil, customfield_10020: nil),
                  editMeta: nil)
    }

    static func sprint(id: Int = 7, name: String = "Sprint 42",
                       endDate: String?, state: String = "active") -> JiraSprint {
        JiraSprint(id: id, name: name, state: state, startDate: nil,
                   endDate: endDate, completeDate: nil, originBoardId: nil)
    }

    static func notifier(_ defaults: UserDefaults, _ rec: Recorder) -> JiraNotifier {
        JiraNotifier(defaults: defaults, calendar: utcCalendar, notify: rec.notify)
    }

    // MARK: - Newly assigned

    @Test("First run stores the key set and announces nothing")
    func firstRunIsSilent() throws {
        let d = try Self.freshDefaults("firstRun")
        let rec = Recorder()
        let n = Self.notifier(d, rec)
        let now = try Self.date("2026-07-16T09:00:00Z")

        n.process(issues: (1...131).map { Self.issue("SHA-\($0)") }, sprint: nil, now: now)

        #expect(rec.count == 0)
        // The set must have been recorded, or run two would fire all 131.
        #expect(d.array(forKey: JiraNotifier.seenKeysDefaultsKey) != nil)
    }

    @Test("A key appearing on the second run fires exactly one newly-assigned")
    func newKeyFiresOnce() throws {
        let d = try Self.freshDefaults("newKey")
        let rec = Recorder()
        let n = Self.notifier(d, rec)
        let now = try Self.date("2026-07-16T09:00:00Z")

        n.process(issues: [Self.issue("SHA-1")], sprint: nil, now: now)
        #expect(rec.count == 0)

        n.process(issues: [Self.issue("SHA-1"), Self.issue("SHA-2", summary: "Ship it")],
                  sprint: nil, now: now)
        #expect(rec.count == 1)
        #expect(rec.ids == ["jira.notify.assigned.SHA-2"])
        #expect(rec.fired[0].body.contains("SHA-2"))
        #expect(rec.fired[0].body.contains("Ship it"))

        // Third run, same set — silence.
        rec.reset()
        n.process(issues: [Self.issue("SHA-1"), Self.issue("SHA-2")], sprint: nil, now: now)
        #expect(rec.count == 0)
    }

    @Test("An issue that disappears and comes back is not re-announced")
    func reappearingKeyIsSilent() throws {
        let d = try Self.freshDefaults("reappear")
        let rec = Recorder()
        let n = Self.notifier(d, rec)
        let now = try Self.date("2026-07-16T09:00:00Z")

        n.process(issues: [Self.issue("SHA-1")], sprint: nil, now: now)
        n.process(issues: [Self.issue("SHA-1"), Self.issue("SHA-2")], sprint: nil, now: now)
        rec.reset()

        // SHA-2 gets un-assigned / resolved, then comes back.
        n.process(issues: [Self.issue("SHA-1")], sprint: nil, now: now)
        n.process(issues: [Self.issue("SHA-1"), Self.issue("SHA-2")], sprint: nil, now: now)
        #expect(rec.count == 0)
    }

    @Test("Multiple new keys each get their own notification")
    func multipleNewKeys() throws {
        let d = try Self.freshDefaults("multiNew")
        let rec = Recorder()
        let n = Self.notifier(d, rec)
        let now = try Self.date("2026-07-16T09:00:00Z")

        n.process(issues: [Self.issue("SHA-1")], sprint: nil, now: now)
        n.process(issues: [Self.issue("SHA-1"), Self.issue("SHA-2"), Self.issue("SHA-3")],
                  sprint: nil, now: now)
        #expect(rec.ids.sorted() == ["jira.notify.assigned.SHA-2", "jira.notify.assigned.SHA-3"])
    }

    // MARK: - Due today

    @Test("Due today fires for today, not for tomorrow or yesterday")
    func dueTodayOnlyForToday() throws {
        let d = try Self.freshDefaults("dueToday")
        let rec = Recorder()
        let n = Self.notifier(d, rec)
        let now = try Self.date("2026-07-16T09:00:00Z")

        // Seed the seen-set so newly-assigned doesn't add noise.
        n.process(issues: [Self.issue("SHA-1", duedate: "2026-07-16"),
                           Self.issue("SHA-2", duedate: "2026-07-17"),
                           Self.issue("SHA-3", duedate: "2026-07-15"),
                           Self.issue("SHA-4", duedate: nil)],
                  sprint: nil, now: now)
        #expect(rec.count == 0)  // first run: silent, including due-today

        rec.reset()
        n.process(issues: [Self.issue("SHA-1", duedate: "2026-07-16"),
                           Self.issue("SHA-2", duedate: "2026-07-17"),
                           Self.issue("SHA-3", duedate: "2026-07-15"),
                           Self.issue("SHA-4", duedate: nil)],
                  sprint: nil, now: now)
        #expect(rec.ids == ["jira.notify.due.SHA-1.2026-07-16"])
    }

    @Test("Due today does not re-fire on a later sync the same day")
    func dueTodayFiresOncePerDay() throws {
        let d = try Self.freshDefaults("dueOncePerDay")
        let rec = Recorder()
        let n = Self.notifier(d, rec)
        let morning = try Self.date("2026-07-16T09:00:00Z")
        let issues = [Self.issue("SHA-1", duedate: "2026-07-16")]

        n.process(issues: issues, sprint: nil, now: morning)
        n.process(issues: issues, sprint: nil, now: morning)
        #expect(rec.count == 1)

        let afternoon = try Self.date("2026-07-16T16:30:00Z")
        n.process(issues: issues, sprint: nil, now: afternoon)
        #expect(rec.count == 1)
    }

    @Test("Due today fires again the next day when the issue is still due that day")
    func dueTodayFiresAgainNextDay() throws {
        let d = try Self.freshDefaults("dueNextDay")
        let rec = Recorder()
        let n = Self.notifier(d, rec)

        // Due 07-17. On 07-16 it's tomorrow (silent), on 07-17 it's today.
        let issues = [Self.issue("SHA-1", duedate: "2026-07-17")]
        n.process(issues: issues, sprint: nil, now: try Self.date("2026-07-16T09:00:00Z"))
        n.process(issues: issues, sprint: nil, now: try Self.date("2026-07-16T18:00:00Z"))
        #expect(rec.count == 0)

        n.process(issues: issues, sprint: nil, now: try Self.date("2026-07-17T09:00:00Z"))
        #expect(rec.ids == ["jira.notify.due.SHA-1.2026-07-17"])

        // An issue whose due date is pushed to a new day nags again on that day.
        rec.reset()
        n.process(issues: [Self.issue("SHA-1", duedate: "2026-07-18")],
                  sprint: nil, now: try Self.date("2026-07-18T09:00:00Z"))
        #expect(rec.ids == ["jira.notify.due.SHA-1.2026-07-18"])
    }

    // MARK: - Sprint ending

    @Test("Sprint ending fires inside the one-day window")
    func sprintEndingFiresInWindow() throws {
        let d = try Self.freshDefaults("sprintIn")
        let rec = Recorder()
        let n = Self.notifier(d, rec)
        let s = Self.sprint(endDate: "2026-07-17T05:00:00.000Z")

        n.process(issues: [], sprint: s, now: try Self.date("2026-07-16T09:00:00Z"))
        #expect(rec.ids == ["jira.notify.sprint.7"])
        #expect(rec.fired[0].body.contains("Sprint 42"))
    }

    @Test("Sprint ending does not fire outside the window or after it ended")
    func sprintEndingSilentOutsideWindow() throws {
        let d = try Self.freshDefaults("sprintOut")
        let rec = Recorder()
        let n = Self.notifier(d, rec)
        let now = try Self.date("2026-07-16T09:00:00Z")

        // Three days out.
        n.process(issues: [], sprint: Self.sprint(id: 1, endDate: "2026-07-19T05:00:00.000Z"),
                  now: now)
        // Already over.
        n.process(issues: [], sprint: Self.sprint(id: 2, endDate: "2026-07-15T05:00:00.000Z"),
                  now: now)
        // No end date at all.
        n.process(issues: [], sprint: Self.sprint(id: 3, endDate: nil), now: now)
        #expect(rec.count == 0)
    }

    @Test("Sprint ending fires at most once per sprint")
    func sprintEndingFiresOncePerSprint() throws {
        let d = try Self.freshDefaults("sprintOnce")
        let rec = Recorder()
        let n = Self.notifier(d, rec)
        let s = Self.sprint(endDate: "2026-07-17T05:00:00.000Z")

        n.process(issues: [], sprint: s, now: try Self.date("2026-07-16T09:00:00Z"))
        n.process(issues: [], sprint: s, now: try Self.date("2026-07-16T10:00:00Z"))
        n.process(issues: [], sprint: s, now: try Self.date("2026-07-16T23:00:00Z"))
        #expect(rec.count == 1)

        // A different sprint still gets its own announcement.
        n.process(issues: [], sprint: Self.sprint(id: 8, name: "Sprint 43",
                                                  endDate: "2026-07-17T05:00:00.000Z"),
                  now: try Self.date("2026-07-16T09:00:00Z"))
        #expect(rec.ids == ["jira.notify.sprint.7", "jira.notify.sprint.8"])
    }

    // MARK: - Toggles

    @Test("Toggling newly-assigned off suppresses only that kind")
    func newAssignedToggleOff() throws {
        let d = try Self.freshDefaults("toggleAssigned")
        d.set(false, forKey: JiraNotifier.notifyNewAssignedDefaultsKey)
        let rec = Recorder()
        let n = Self.notifier(d, rec)
        let now = try Self.date("2026-07-16T09:00:00Z")

        n.process(issues: [Self.issue("SHA-1")], sprint: nil, now: now)
        n.process(issues: [Self.issue("SHA-1"), Self.issue("SHA-2", duedate: "2026-07-16")],
                  sprint: Self.sprint(endDate: "2026-07-17T05:00:00.000Z"), now: now)

        #expect(!rec.ids.contains("jira.notify.assigned.SHA-2"))
        #expect(rec.ids.contains("jira.notify.due.SHA-2.2026-07-16"))
        #expect(rec.ids.contains("jira.notify.sprint.7"))
    }

    @Test("Toggling due-today off suppresses only that kind")
    func dueTodayToggleOff() throws {
        let d = try Self.freshDefaults("toggleDue")
        d.set(false, forKey: JiraNotifier.notifyDueTodayDefaultsKey)
        let rec = Recorder()
        let n = Self.notifier(d, rec)
        let now = try Self.date("2026-07-16T09:00:00Z")

        n.process(issues: [Self.issue("SHA-1")], sprint: nil, now: now)
        n.process(issues: [Self.issue("SHA-1"), Self.issue("SHA-2", duedate: "2026-07-16")],
                  sprint: Self.sprint(endDate: "2026-07-17T05:00:00.000Z"), now: now)

        #expect(rec.ids.contains("jira.notify.assigned.SHA-2"))
        #expect(!rec.ids.contains("jira.notify.due.SHA-2.2026-07-16"))
        #expect(rec.ids.contains("jira.notify.sprint.7"))
    }

    @Test("Toggling sprint-ending off suppresses only that kind")
    func sprintEndingToggleOff() throws {
        let d = try Self.freshDefaults("toggleSprint")
        d.set(false, forKey: JiraNotifier.notifySprintEndingDefaultsKey)
        let rec = Recorder()
        let n = Self.notifier(d, rec)
        let now = try Self.date("2026-07-16T09:00:00Z")

        n.process(issues: [Self.issue("SHA-1")], sprint: nil, now: now)
        n.process(issues: [Self.issue("SHA-1"), Self.issue("SHA-2", duedate: "2026-07-16")],
                  sprint: Self.sprint(endDate: "2026-07-17T05:00:00.000Z"), now: now)

        #expect(rec.ids.contains("jira.notify.assigned.SHA-2"))
        #expect(rec.ids.contains("jira.notify.due.SHA-2.2026-07-16"))
        #expect(!rec.ids.contains("jira.notify.sprint.7"))
    }

    @Test("All three kinds are on by default")
    func togglesDefaultOn() throws {
        let d = try Self.freshDefaults("defaults")
        let n = Self.notifier(d, Recorder())
        #expect(n.isNewAssignedEnabled)
        #expect(n.isDueTodayEnabled)
        #expect(n.isSprintEndingEnabled)
    }

    // MARK: - Suppression state survives a fresh instance

    @Test("Suppression is persisted, not held in memory")
    func suppressionSurvivesNewInstance() throws {
        let d = try Self.freshDefaults("persist")
        let rec = Recorder()
        let now = try Self.date("2026-07-16T09:00:00Z")
        let issues = [Self.issue("SHA-1", duedate: "2026-07-16")]

        Self.notifier(d, rec).process(issues: issues, sprint: nil, now: now)
        // A relaunch: brand-new notifier reading the same defaults.
        Self.notifier(d, rec).process(issues: issues, sprint: nil, now: now)
        #expect(rec.count == 1)
        Self.notifier(d, rec).process(issues: issues, sprint: nil, now: now)
        #expect(rec.count == 1)
    }
}
