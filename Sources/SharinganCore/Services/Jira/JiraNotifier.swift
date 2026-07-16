import Foundation

/// Decides which Jira notifications a sync should fire.
///
/// **Why this is a separate, pure type.** The three things worth interrupting a
/// user for — a ticket landing on their plate, a due date arriving, a sprint
/// closing — are all *diffs against the past*, not properties of a single sync.
/// That state (what has already been announced) is exactly what makes the naive
/// version so annoying: poll every 5 minutes, and "SHA-42 is due today" fires
/// twelve times an hour. So the decision needs memory, and memory needs to be
/// testable — hence `notify` and `defaults` are injected and `now` is a
/// parameter rather than a call to `Date()`. Nothing here touches
/// `NotificationService.shared`, `UserDefaults.standard`, or the system clock;
/// `JiraService` wires those in.
///
/// The issue list is assumed to be *already scoped to the current user* — the
/// sync JQL is `assignee = currentUser() AND statusCategory != Done`, so
/// "present in the list" means "assigned to me and not done". This type
/// deliberately does not re-check `fields.assignee`, which the Agile API often
/// omits.
///
/// `@unchecked Sendable` because of the stored `UserDefaults` (documented
/// thread-safe but not formally `Sendable`), matching `JiraTokenStore`. The type
/// is otherwise immutable, and its state lives entirely in the defaults — so a
/// fresh instance after a relaunch suppresses exactly what the old one would
/// have.
public struct JiraNotifier: @unchecked Sendable {

    // MARK: - Toggle keys

    /// All three default to **on** when the key is absent: a user who connects
    /// Jira asked to be told about their Jira work. `defaults.bool(forKey:)`
    /// answers `false` for a missing key, so every read goes through
    /// `flag(_:)`, which treats absent as on.
    public static let notifyNewAssignedDefaultsKey = "jira.notifyNewAssigned"
    public static let notifyDueTodayDefaultsKey = "jira.notifyDueToday"
    public static let notifySprintEndingDefaultsKey = "jira.notifySprintEnding"

    // MARK: - Suppression state keys

    /// Every issue key ever seen, oldest first. Cumulative rather than "last
    /// sync's keys" on purpose — see `process(issues:sprint:now:)`.
    public static let seenKeysDefaultsKey = "jira.notify.seenKeys"
    /// `[issue key: yyyy-MM-dd]` — the day each issue's due-date reminder fired.
    public static let dueAnnouncedDefaultsKey = "jira.notify.dueAnnounced"
    /// Sprint ids whose "ending soon" has been announced.
    public static let sprintAnnouncedDefaultsKey = "jira.notify.sprintAnnounced"

    // MARK: - Tuning

    /// How close to a sprint's end counts as "ending soon".
    public static let sprintEndingWindow: TimeInterval = 24 * 60 * 60
    /// Cap on the remembered key set. The set only grows, so it needs a bound;
    /// 2000 is far past any realistic assigned-issue history, and trimming the
    /// oldest keys is safe — an issue absent for that long re-announcing is the
    /// correct outcome anyway.
    public static let seenKeysLimit = 2000

    /// `(title, body, identifier)` — deliberately the exact shape of
    /// `NotificationService.notify`, so wiring is `notifier.notify`.
    public typealias Notify = (String, String, String) -> Void

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let notify: Notify

    /// - Parameters:
    ///   - defaults: where suppression state and the toggles live.
    ///   - calendar: supplies the time zone that decides what "today" means.
    ///   - notify: called once per notification to fire.
    public init(defaults: UserDefaults = .standard,
                calendar: Calendar = .current,
                notify: @escaping Notify) {
        self.defaults = defaults
        self.calendar = calendar
        self.notify = notify
    }

    // MARK: - Toggles

    public var isNewAssignedEnabled: Bool { flag(Self.notifyNewAssignedDefaultsKey) }
    public var isDueTodayEnabled: Bool { flag(Self.notifyDueTodayDefaultsKey) }
    public var isSprintEndingEnabled: Bool { flag(Self.notifySprintEndingDefaultsKey) }

    private func flag(_ key: String) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    // MARK: - Entry point

    /// Fires whatever this sync warrants and records it so the next sync stays
    /// quiet.
    ///
    /// Safe to call from `@MainActor` code and cheap enough to run on every
    /// poll: it does no I/O beyond the injected defaults.
    ///
    /// Three deliberate semantics, each of which is the difference between
    /// useful and infuriating:
    ///
    /// - **First run announces nothing.** With no stored key set, every one of
    ///   the user's (often 100+) issues looks new. So the first run only
    ///   records the baseline. An absent key set is distinguished from an empty
    ///   one, which is why this reads `array(forKey:)` for nil rather than
    ///   checking `isEmpty`.
    /// - **The key set is cumulative, so a reappearing issue stays quiet.** An
    ///   issue drops out of the sync whenever it's moved to Done or briefly
    ///   reassigned, and JQL churn like that is not news. Remembering every key
    ///   ever seen means only a genuinely first-time key announces.
    /// - **Due-today is keyed by (issue, day).** Once per issue per day: silent
    ///   for the rest of today, and if the issue is still due tomorrow —
    ///   because the date got pushed — tomorrow's reminder is a new, wanted one.
    public func process(issues: [JiraIssue], sprint: JiraSprint?, now: Date) {
        // Sampled once, before `announceNewlyAssigned` writes the baseline —
        // otherwise the due-date pass would see the set it just created and
        // conclude this was not the first run.
        let isFirstRun = defaults.array(forKey: Self.seenKeysDefaultsKey) == nil
        announceNewlyAssigned(issues, isFirstRun: isFirstRun)
        announceDueToday(issues, now: now, isFirstRun: isFirstRun)
        announceSprintEnding(sprint, now: now)
    }

    // MARK: - Newly assigned

    private func announceNewlyAssigned(_ issues: [JiraIssue], isFirstRun: Bool) {
        let seen = (defaults.array(forKey: Self.seenKeysDefaultsKey) as? [String]) ?? []
        let seenSet = Set(seen)

        defer {
            // Record the baseline even when the toggle is off, so switching the
            // toggle on later doesn't replay the whole backlog as "new".
            var merged = seen
            var known = seenSet
            for key in issues.map(\.key) where known.insert(key).inserted {
                merged.append(key)
            }
            defaults.set(Array(merged.suffix(Self.seenKeysLimit)),
                         forKey: Self.seenKeysDefaultsKey)
        }

        // First run: baseline only.
        guard !isFirstRun, isNewAssignedEnabled else { return }

        for issue in issues where !seenSet.contains(issue.key) {
            let summary = issue.fields.summary ?? ""
            notify("Assigned to you",
                   summary.isEmpty ? issue.key : "\(issue.key) — \(summary)",
                   "jira.notify.assigned.\(issue.key)")
        }
    }

    // MARK: - Due today

    private func announceDueToday(_ issues: [JiraIssue], now: Date, isFirstRun: Bool) {
        // Nothing is "due today" on the first run either — the user just
        // connected; a burst of due dates is noise, not news.
        guard isDueTodayEnabled, !isFirstRun else { return }

        let today = dayStamp(now)
        var announced = (defaults.dictionary(forKey: Self.dueAnnouncedDefaultsKey)
                         as? [String: String]) ?? [:]
        var changed = false

        for issue in issues {
            // `duedate` is a plain `yyyy-MM-dd` date with no time zone, so it is
            // compared as a string against today's stamp in the caller's
            // calendar. Parsing it to a `Date` would only invent a midnight and
            // a zone to get the comparison wrong at the edges.
            guard let due = issue.fields.duedate, due == today else { continue }
            guard announced[issue.key] != today else { continue }

            let summary = issue.fields.summary ?? ""
            notify("Due today",
                   summary.isEmpty ? issue.key : "\(issue.key) — \(summary)",
                   "jira.notify.due.\(issue.key).\(today)")
            announced[issue.key] = today
            changed = true
        }

        if changed {
            defaults.set(announced, forKey: Self.dueAnnouncedDefaultsKey)
        }
    }

    /// `now` rendered as `yyyy-MM-dd` in the injected calendar's time zone —
    /// the same shape Jira's `duedate` uses.
    private func dayStamp(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: - Sprint ending

    private func announceSprintEnding(_ sprint: JiraSprint?, now: Date) {
        guard isSprintEndingEnabled,
              let sprint,
              let endText = sprint.endDate,
              let end = Self.parseTimestamp(endText) else { return }

        // Inside the window and not already over. A sprint whose end has passed
        // but which Jira still calls active is a stale board, not a deadline.
        let remaining = end.timeIntervalSince(now)
        guard remaining >= 0, remaining <= Self.sprintEndingWindow else { return }

        var announced = (defaults.array(forKey: Self.sprintAnnouncedDefaultsKey)
                         as? [Int]) ?? []
        guard !announced.contains(sprint.id) else { return }

        notify("Sprint ending",
               "\(sprint.name) ends within a day.",
               "jira.notify.sprint.\(sprint.id)")
        announced.append(sprint.id)
        defaults.set(Array(announced.suffix(Self.seenKeysLimit)),
                     forKey: Self.sprintAnnouncedDefaultsKey)
    }

    /// Jira's Agile API stamps sprint dates with fractional seconds
    /// (`2026-07-17T05:00:00.000Z`) but not always, so try both spellings.
    static func parseTimestamp(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: text) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }
}
