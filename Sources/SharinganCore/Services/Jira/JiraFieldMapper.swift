import Foundation

/// The fields a merge decided to send back to Jira. A nil member means "don't
/// push this field" — distinct from "push an empty value", which Jira treats as
/// a clear.
public struct JiraPushFields: Equatable, Sendable {
    public var summary: String?
    /// Jira's priority *name* ("High"/"Medium"/"Low"). `TaskPriority.none` has
    /// no Jira equivalent, so it never pushes.
    public var priorityName: String?
    /// The full label array — Jira replaces labels wholesale, so this is the
    /// merged set, not a delta.
    public var labels: [String]?
    /// `yyyy-MM-dd`, UTC.
    public var duedate: String?
    /// `timeoriginalestimate`, in seconds.
    public var timeoriginalestimate: Int?

    public init(summary: String? = nil,
                priorityName: String? = nil,
                labels: [String]? = nil,
                duedate: String? = nil,
                timeoriginalestimate: Int? = nil) {
        self.summary = summary
        self.priorityName = priorityName
        self.labels = labels
        self.duedate = duedate
        self.timeoriginalestimate = timeoriginalestimate
    }

    /// True when the merge found nothing to send — the caller skips the PUT.
    public var isEmpty: Bool {
        summary == nil && priorityName == nil && labels == nil
            && duedate == nil && timeoriginalestimate == nil
    }
}

/// The result of reconciling one task against one issue.
public struct JiraMergeOutcome: Equatable, Sendable {
    /// The task as it should now be stored locally.
    public var mergedTask: TaskItem
    /// What to send to Jira; nil members = don't push.
    public var fieldsToPush: JiraPushFields
    /// Jira field names where both sides changed and Jira's value won, so the
    /// UI can toast ("Jira's summary replaced yours").
    public var conflicts: [String]

    public init(mergedTask: TaskItem,
                fieldsToPush: JiraPushFields = JiraPushFields(),
                conflicts: [String] = []) {
        self.mergedTask = mergedTask
        self.fieldsToPush = fieldsToPush
        self.conflicts = conflicts
    }
}

/// Pure, I/O-free translation between a `JiraIssue` and a `TaskItem`.
///
/// Everything here is a static function over values so the merge rules can be
/// tested exhaustively without a network or a database in sight.
///
/// Deliberate non-mappings:
/// - **Status never touches `isDone`.** Jira workflows are per-project and
///   arbitrary ("Done", "Released", "Won't Fix"); guessing completion from them
///   would tick off the user's tasks behind their back. Status rides along in
///   the cache and is shown as its own chip.
/// - **Components and project are Jira→local only** in v1: pushing them needs
///   allowed-value validation from `editmeta`, which M2 doesn't do.
public enum JiraFieldMapper {

    /// One pomodoro, in seconds — the unit Jira estimates are converted through.
    public static let pomodoroSeconds = 1500

    // MARK: - Priority

    /// Jira priority name → local flag. Jira sites can rename or add priorities
    /// freely, so anything unrecognized (and an absent priority) maps to
    /// `.none` rather than guessing a middle value.
    public static func priority(fromJiraName name: String?) -> TaskPriority {
        guard let name else { return .none }
        switch name.trimmingCharacters(in: .whitespaces).lowercased() {
        case "highest", "high":  return .high     // 3
        case "medium":           return .medium   // 2
        case "low", "lowest":    return .low      // 1
        default:                 return .none     // 0
        }
    }

    /// Local flag → Jira priority name. `.none` returns nil: the user clearing
    /// a flag locally means "no opinion", not "set Jira's priority to nothing",
    /// and most sites make priority required anyway.
    public static func jiraPriorityName(from priority: TaskPriority) -> String? {
        switch priority.rawValue {
        case 3:  return "High"
        case 2:  return "Medium"
        case 1:  return "Low"
        default: return nil
        }
    }

    // MARK: - Labels / tags

    /// Local tag → Jira label. Jira rejects labels containing spaces, so they
    /// collapse to dashes; the pull direction is the identity, which makes the
    /// round-trip stable after the first push ("code review" → "code-review" →
    /// "code-review").
    public static func jiraLabel(from tag: String) -> String {
        tag.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "-")
    }

    // MARK: - Dates

    /// Jira `duedate` is a bare calendar day with no zone, so it's parsed and
    /// formatted in UTC — using the local zone would shift the day for anyone
    /// west of Greenwich.
    private static let dueDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    public static func date(fromJiraDueDate string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return dueDateFormatter.date(from: string)
    }

    public static func jiraDueDate(from date: Date?) -> String? {
        guard let date else { return nil }
        return dueDateFormatter.string(from: date)
    }

    // MARK: - Estimates

    /// Jira seconds → pomodoros, always rounding **up**: a 1501-second estimate
    /// is two pomodoros of work, not one. Zero and absent both mean "no
    /// estimate" (Jira writes 0 where the UI shows blank).
    public static func pomodoros(fromEstimateSeconds seconds: Int?) -> Int? {
        guard let seconds, seconds > 0 else { return nil }
        return Int(ceil(Double(seconds) / Double(pomodoroSeconds)))
    }

    public static func estimateSeconds(fromPomodoros pomodoros: Int?) -> Int? {
        guard let pomodoros, pomodoros > 0 else { return nil }
        return pomodoros * pomodoroSeconds
    }

    // MARK: - Snapshot

    /// The last-seen row to store after a fetch: every Jira-owned field exactly
    /// as it arrived, which is what makes the next merge three-way.
    public static func snapshot(from issue: JiraIssue,
                                siteHost: String,
                                fetchedAt: Date = Date()) -> CachedJiraIssue {
        let fields = issue.fields
        return CachedJiraIssue(
            issueID: issue.id,
            issueKey: issue.key,
            siteHost: siteHost,
            summary: fields.summary ?? "",
            statusID: nil,
            statusName: fields.status?.name,
            statusCategory: fields.status?.statusCategory.key,
            issueType: fields.issuetype?.name,
            priorityName: fields.priority?.name,
            assigneeName: fields.assignee?.displayName,
            labels: fields.labels ?? [],
            components: (fields.components ?? []).map(\.name),
            projectKey: fields.project?.key,
            dueDate: fields.duedate,
            estimateSeconds: fields.timeoriginalestimate,
            descriptionADF: fields.description.flatMap {
                (try? JSONEncoder().encode($0)).flatMap { String(data: $0, encoding: .utf8) }
            },
            jiraUpdated: iso8601Date(fields.updated),
            fetchedAt: fetchedAt)
    }

    /// Jira's `updated` is ISO-8601 with milliseconds and a numeric zone
    /// ("2026-07-15T09:31:04.123+0000"), which `.withInternetDateTime` alone
    /// won't parse — try with fractional seconds first.
    private static func iso8601Date(_ string: String?) -> Date? {
        guard let string else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: string) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    // MARK: - Import

    /// A fresh task from an issue Sharingan has never seen. Everything Jira owns
    /// wins by definition — there's no local side to preserve yet.
    public static func taskItem(from issue: JiraIssue, siteHost: String) -> TaskItem {
        let fields = issue.fields
        let labels = fields.labels ?? []
        let components = (fields.components ?? []).map(\.name)
        return TaskItem(
            title: fields.summary ?? issue.key,
            category: fields.project?.key ?? TaskCategory.presets[0].name,
            tags: mergeUnique(labels, components),
            dueDate: date(fromJiraDueDate: fields.duedate),
            estimatedPomodoros: pomodoros(fromEstimateSeconds: fields.timeoriginalestimate),
            project: fields.project?.key,
            priority: priority(fromJiraName: fields.priority?.name),
            jiraKey: issue.key,
            jiraIssueID: issue.id,
            jiraSiteHost: siteHost)
    }

    // MARK: - Three-way merge

    /// Which way a single field resolved.
    private enum Resolution<T> {
        /// Jira changed, the user didn't — take Jira's value.
        case pull(T)
        /// The user changed, Jira didn't — send ours.
        case push(T)
        /// Both changed and disagree — Jira wins, and we say so.
        case conflict(T)
        /// Nothing to do.
        case noop
    }

    /// The core rule, applied per field.
    ///
    /// `lastSeen == nil` means this task has never been reconciled against the
    /// issue (a link that was just created). There's no base to diff against, so
    /// "who changed it?" is unanswerable — Jira wins, but silently: adopting the
    /// issue's values on first link is the expected behavior, not a conflict
    /// worth toasting.
    private static func resolve<T: Equatable>(local: T, remote: T, lastSeen: T?) -> Resolution<T> {
        guard let lastSeen else {
            return local == remote ? .noop : .pull(remote)
        }
        let localChanged = local != lastSeen
        let remoteChanged = remote != lastSeen
        switch (localChanged, remoteChanged) {
        case (false, false): return .noop
        case (false, true):  return .pull(remote)
        case (true, false):  return .push(local)
        case (true, true):
            // Both moved. Converging on the same value isn't a conflict.
            return local == remote ? .noop : .conflict(remote)
        }
    }

    /// Reconcile a task against its Jira issue.
    ///
    /// - Parameters:
    ///   - local: the task as it stands on this Mac.
    ///   - remote: the issue as just fetched.
    ///   - lastSeen: the snapshot stored the last time these two agreed.
    ///   - pushEstimate: whether a locally-changed estimate may overwrite Jira's
    ///     `timeoriginalestimate`. Off by default — an estimate in pomodoros is
    ///     a coarser unit than Jira's seconds, so pushing it back rounds the
    ///     team's number to the nearest 25 minutes. The pull direction always
    ///     runs.
    public static func merge(local: TaskItem,
                             remote: JiraIssue,
                             lastSeen: CachedJiraIssue?,
                             pushEstimate: Bool = false) -> JiraMergeOutcome {
        var merged = local
        var push = JiraPushFields()
        var conflicts: [String] = []

        // Keep the identity columns fresh: an issue key changes when the issue
        // is moved between projects, and the ID is what survives that.
        merged.jiraKey = remote.key
        merged.jiraIssueID = remote.id

        // summary ↔ title
        switch resolve(local: local.title,
                       remote: remote.fields.summary ?? "",
                       lastSeen: lastSeen?.summary) {
        case .pull(let v):     merged.title = v
        case .push(let v):     push.summary = v
        case .conflict(let v): merged.title = v; conflicts.append("summary")
        case .noop:            break
        }

        // priority — compared in local flag space so renamed-but-equivalent
        // Jira names ("Highest" vs "High") don't read as a change.
        switch resolve(local: local.priority,
                       remote: priority(fromJiraName: remote.fields.priority?.name),
                       lastSeen: lastSeen.map { priority(fromJiraName: $0.priorityName) }) {
        case .pull(let v):     merged.priority = v
        case .push(let v):     push.priorityName = jiraPriorityName(from: v)
        case .conflict(let v): merged.priority = v; conflicts.append("priority")
        case .noop:            break
        }

        // duedate — compared as yyyy-MM-dd strings, so a local time-of-day edit
        // isn't mistaken for a due-date change (and survives a push/noop).
        switch resolve(local: jiraDueDate(from: local.dueDate),
                       remote: remote.fields.duedate,
                       lastSeen: lastSeen.map(\.dueDate)) {
        case .pull(let v):     merged.dueDate = date(fromJiraDueDate: v)
        case .push(let v):     push.duedate = v
        case .conflict(let v): merged.dueDate = date(fromJiraDueDate: v); conflicts.append("duedate")
        case .noop:            break
        }

        // timeoriginalestimate ↔ estimatedPomodoros, compared in pomodoros.
        switch resolve(local: local.estimatedPomodoros,
                       remote: pomodoros(fromEstimateSeconds: remote.fields.timeoriginalestimate),
                       lastSeen: lastSeen.map { pomodoros(fromEstimateSeconds: $0.estimateSeconds) }) {
        case .pull(let v):
            merged.estimatedPomodoros = v
        case .push(let v):
            if pushEstimate { push.timeoriginalestimate = estimateSeconds(fromPomodoros: v) }
        case .conflict(let v):
            merged.estimatedPomodoros = v
            conflicts.append("timeoriginalestimate")
        case .noop:
            break
        }

        // labels ↔ tags — set-diff, not last-writer-wins.
        let labelMerge = mergeLabels(localTags: local.tags,
                                     remoteLabels: remote.fields.labels ?? [],
                                     lastSeen: lastSeen)
        merged.tags = labelMerge.tags
        if let labels = labelMerge.labelsToPush { push.labels = labels }

        // Jira→local only.
        if let projectKey = remote.fields.project?.key {
            merged.project = projectKey
            merged.category = projectKey
        }

        return JiraMergeOutcome(mergedTask: merged, fieldsToPush: push, conflicts: conflicts)
    }

    // MARK: - Label set-diff

    /// Labels merge as **sets of adds and removes against the snapshot**, so a
    /// tag the user added locally and a label someone added in Jira both
    /// survive — replacing the whole array with one side's value would silently
    /// drop the other's. That also means labels can't conflict: two adds of
    /// different labels compose, and nobody can remove a label that wasn't in
    /// the base.
    ///
    /// Component-derived tags are held out of the diff entirely. Components are
    /// Jira→local only, so a component sitting in `tags` would otherwise look
    /// like a local label add and get pushed to Jira as a label.
    private static func mergeLabels(localTags: [String],
                                    remoteLabels: [String],
                                    lastSeen: CachedJiraIssue?) -> (tags: [String], labelsToPush: [String]?) {
        let componentTags = lastSeen?.components ?? []
        let componentSet = Set(componentTags)

        // The diff runs in Jira-label space: a local "code review" and a remote
        // "code-review" are the same label, and comparing raw would push a
        // pointless update on every sync.
        let localLabels = localTags
            .filter { !componentSet.contains($0) }
            .map(jiraLabel(from:))
        let remote = remoteLabels

        guard let base = lastSeen?.labels else {
            // No snapshot: union both sides rather than picking one — a first
            // link should never lose a label.
            let tags = mergeUnique(mergeUnique(remote, localLabels), componentTags)
            let labels = mergeUnique(remote, localLabels)
            return (tags, Set(labels) == Set(remote) ? nil : labels)
        }

        let baseSet = Set(base)
        let localSet = Set(localLabels)
        let remoteSet = Set(remote)

        let localAdds = localSet.subtracting(baseSet)
        let localRemoves = baseSet.subtracting(localSet)
        let remoteAdds = remoteSet.subtracting(baseSet)
        let remoteRemoves = baseSet.subtracting(remoteSet)

        let mergedSet = baseSet
            .union(localAdds).union(remoteAdds)
            .subtracting(localRemoves).subtracting(remoteRemoves)

        // Order: keep the local order the user arranged, then append whatever
        // Jira contributed, so the merge doesn't shuffle the tag row.
        var ordered = localLabels.filter { mergedSet.contains($0) }
        for label in remote where mergedSet.contains(label) && !ordered.contains(label) {
            ordered.append(label)
        }
        for label in base where mergedSet.contains(label) && !ordered.contains(label) {
            ordered.append(label)
        }

        let tags = mergeUnique(ordered, (lastSeen?.components ?? []).filter { componentSet.contains($0) })
        return (tags, mergedSet == remoteSet ? nil : ordered)
    }

    /// Concatenation that drops duplicates and keeps first-seen order.
    private static func mergeUnique(_ first: [String], _ second: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for value in first + second where seen.insert(value).inserted {
            out.append(value)
        }
        return out
    }
}
