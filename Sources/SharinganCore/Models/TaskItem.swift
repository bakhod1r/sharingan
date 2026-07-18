import Foundation

/// A single checklist item under a task.
public struct Subtask: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var isDone: Bool
    /// Planned pomodoros for this step (nil = no estimate).
    public var estimatedPomodoros: Int?
    /// Focus sessions credited to this step.
    public var pomodorosDone: Int
    /// Pomodoro size for this step (nil = inherit the task's, then the app's).
    public var pomodoroKind: PomodoroKind?
    /// Per-step priority flag (`.none` = unflagged, the default).
    public var priority: TaskPriority
    /// Jira issue key when this subtask mirrors a Jira sub-task issue, e.g.
    /// WT-702. Lets worklog and status changes target the sub-task issue itself,
    /// not just its parent. nil for ordinary local subtasks.
    public var jiraKey: String?
    /// Jira's stable issue ID for the mirrored sub-task.
    public var jiraIssueID: String?

    public init(id: UUID = UUID(), title: String, isDone: Bool = false,
                estimatedPomodoros: Int? = nil, pomodorosDone: Int = 0,
                pomodoroKind: PomodoroKind? = nil,
                priority: TaskPriority = .none,
                jiraKey: String? = nil,
                jiraIssueID: String? = nil) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.estimatedPomodoros = estimatedPomodoros
        self.pomodorosDone = pomodorosDone
        self.pomodoroKind = pomodoroKind
        self.priority = priority
        self.jiraKey = jiraKey
        self.jiraIssueID = jiraIssueID
    }

    /// True when this subtask mirrors a Jira sub-task issue.
    public var isJiraLinked: Bool { jiraKey?.isEmpty == false }

    // Pomodoro/priority fields were added after subtasks first shipped —
    // decode them as optional so older persisted rows (subtasks JSON column)
    // still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        estimatedPomodoros = try c.decodeIfPresent(Int.self, forKey: .estimatedPomodoros)
        pomodorosDone = try c.decodeIfPresent(Int.self, forKey: .pomodorosDone) ?? 0
        pomodoroKind = ((try? c.decodeIfPresent(PomodoroKind.self, forKey: .pomodoroKind)) ?? nil)
        priority = try c.decodeIfPresent(TaskPriority.self, forKey: .priority) ?? .none
        jiraKey = try c.decodeIfPresent(String.self, forKey: .jiraKey)
        jiraIssueID = try c.decodeIfPresent(String.self, forKey: .jiraIssueID)
    }
}

/// How a task repeats after completion.
/// Persisted as a single string ("daily", "everyNDays:3", "monthly:15") so
/// rows written by the old `String`-raw-value version decode unchanged, and
/// unknown strings degrade to `.none` instead of dropping the task.
public enum Recurrence: Codable, Equatable, Hashable, Sendable, CaseIterable, Identifiable {
    case none, daily, weekdays, weekly
    /// Every N days (N ≥ 1).
    case everyNDays(Int)
    /// A given day of every month (1…31, clamped to the month's length).
    case monthly(Int)

    /// Menu presets — pickers offer these; the editor refines N / day.
    public static var allCases: [Recurrence] {
        [.none, .daily, .weekdays, .weekly, .everyNDays(2), .everyNDays(3), .monthly(1)]
    }

    public var id: String { stringValue }

    /// The persisted representation.
    public var stringValue: String {
        switch self {
        case .none:     return "none"
        case .daily:    return "daily"
        case .weekdays: return "weekdays"
        case .weekly:   return "weekly"
        case .everyNDays(let n): return "everyNDays:\(n)"
        case .monthly(let d):    return "monthly:\(d)"
        }
    }

    /// Parses a persisted string; anything unrecognized becomes `.none`.
    public init(string: String) {
        switch string {
        case "none":     self = .none
        case "daily":    self = .daily
        case "weekdays": self = .weekdays
        case "weekly":   self = .weekly
        default:
            let parts = string.split(separator: ":")
            if parts.count == 2, let n = Int(parts[1]), n >= 1 {
                switch parts[0] {
                case "everyNDays": self = .everyNDays(n); return
                case "monthly":    self = .monthly(min(n, 31)); return
                default: break
                }
            }
            self = .none
        }
    }

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        self = Recurrence(string: s)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(stringValue)
    }

    public var label: String {
        switch self {
        case .none:     return "Does not repeat"
        case .daily:    return "Every day"
        case .weekdays: return "Weekdays"
        case .weekly:   return "Every week"
        case .everyNDays(let n): return "Every \(n) days"
        case .monthly(let d):    return "Monthly (day \(d))"
        }
    }

    /// The next occurrence date after `date` (time of day preserved).
    public func nextDate(after date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .none:  return date
        case .daily: return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .weekly: return calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .weekdays:
            var d = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            while calendar.isDateInWeekend(d) {
                d = calendar.date(byAdding: .day, value: 1, to: d) ?? d
            }
            return d
        case .everyNDays(let n):
            return calendar.date(byAdding: .day, value: max(1, n), to: date) ?? date
        case .monthly(let dayOfMonth):
            let day = max(1, min(dayOfMonth, 31))
            let time = calendar.dateComponents([.hour, .minute, .second], from: date)
            var ym = calendar.dateComponents([.year, .month], from: date)
            // Walk month by month (clamping to each month's length) until we
            // pass `date`; 25 iterations bounds the search safely.
            for _ in 0..<25 {
                guard let monthStart = calendar.date(from: ym),
                      let dayRange = calendar.range(of: .day, in: .month, for: monthStart)
                else { break }
                var c = ym
                c.day = min(day, dayRange.count)
                c.hour = time.hour; c.minute = time.minute; c.second = time.second
                if let candidate = calendar.date(from: c), candidate > date {
                    return candidate
                }
                ym.month! += 1
            }
            return date
        }
    }
}

/// Task priority, Todoist-style: P1 (urgent, red) … P4 (none). Higher rawValue
/// = more urgent, so sorting descending puts P1 first.
///
/// Was an `Int` enum; now a struct so users can add their own levels ABOVE P1
/// (rawValues 4+, stored in `PomodoroSettings.customPriorityLevels`). The four
/// built-ins keep their rawValues (0…3) and static accessors, and Codable
/// encodes the bare `Int` — byte-identical to the old enum, so persisted JSON
/// blobs and SQLite rows decode unchanged.
public struct TaskPriority: RawRepresentable, Codable, Hashable, Sendable, Identifiable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public var id: Int { rawValue }

    public static let none     = TaskPriority(rawValue: 0)   // no flag
    public static let lowest   = TaskPriority(rawValue: 1)   // P5 — teal
    public static let low      = TaskPriority(rawValue: 2)   // P4 — blue
    public static let medium   = TaskPriority(rawValue: 3)   // P3 — amber
    public static let high     = TaskPriority(rawValue: 4)   // P2 — orange
    public static let critical = TaskPriority(rawValue: 5)   // P1 — red

    /// The built-in flagged levels, lowest raw first.
    public static let builtIns: [Int] = [1, 2, 3, 4, 5]

    // Encode/decode as a single bare Int (matching the old enum) so old data
    // round-trips identically. The default struct synthesis would emit a
    // keyed `{"rawValue": 3}` object instead, breaking compatibility.
    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(Int.self)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    /// All levels, most-urgent first, ending with `.none`. Built-ins (1…3)
    /// plus the user's custom levels (rawValues stored in settings).
    public static func levels(custom: [Int]) -> [TaskPriority] {
        let flagged = (builtIns + custom).sorted(by: >).map(TaskPriority.init(rawValue:))
        return flagged + [.none]
    }

    /// "P1"…"P5" for the built-ins (P1 = most urgent = highest raw). Custom
    /// levels have no fixed rank in isolation — UI shows their rank via
    /// `PomodoroSettings.priorityShortLabel`.
    public var label: String {
        switch rawValue {
        case 1...5: return "P\(6 - rawValue)"
        default:    return rawValue == 0 ? "" : "P!"
        }
    }

    /// Menu label — the built-in default; custom levels always carry a
    /// user-supplied name in settings, so "Custom" is rarely seen.
    public var menuLabel: String {
        switch rawValue {
        case 0:  return "No priority"
        case 1:  return "P5 · Lowest"
        case 2:  return "P4 · Low"
        case 3:  return "P3 · Medium"
        case 4:  return "P2 · High"
        case 5:  return "P1 · Critical"
        default: return "Custom"
        }
    }

    /// Flag color hex for the built-ins; nil for `.none` and for custom levels
    /// (whose colors live in settings, read via `priorityColorHex`).
    public var colorHex: String? {
        switch rawValue {
        case 1:  return "#34C7B5"   // Lowest — teal
        case 2:  return "#4F8DFD"   // Low — blue
        case 3:  return "#FFB020"   // Medium — amber
        case 4:  return "#FF8A3D"   // High — orange
        case 5:  return "#FF5E5B"   // Critical — red
        default: return nil
        }
    }
}

/// A task the user can run focus pomodoros against.
public struct TaskItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var category: String
    public var tags: [String]
    public var isDone: Bool
    public var pomodorosDone: Int
    public var createdAt: Date
    /// Last edit, for sync's last-writer-wins. Defaults to `createdAt` so
    /// pre-1.3.0 tasks (SQLite rows and exported JSON alike) decode unchanged.
    public var modifiedAt: Date
    public var dueDate: Date?
    /// Manual ordering position within the list (lower = higher up).
    public var sortOrder: Int
    /// Planned number of pomodoros for this task (nil = no estimate).
    public var estimatedPomodoros: Int?
    /// Start-of-day this task is planned for (nil = not on a daily plan).
    public var plannedDate: Date?
    /// Free-form notes.
    public var notes: String
    /// Checklist items.
    public var subtasks: [Subtask]
    /// Repeat rule applied when the task is completed.
    public var recurrence: Recurrence
    /// Optional project grouping (a second axis above category).
    public var project: String?
    /// Todoist-style priority flag.
    public var priority: TaskPriority
    /// When the task was completed (nil while open; cleared on un-complete).
    public var completedAt: Date?
    /// Pomodoro size to run against this task (nil = app default).
    public var pomodoroKind: PomodoroKind?
    /// Jira issue key, e.g. SHR-123.
    public var jiraKey: String?
    /// Jira's stable issue ID string.
    public var jiraIssueID: String?
    /// Site host only (not a full URL), e.g. example.atlassian.net.
    public var jiraSiteHost: String?
    /// The Jira issue type this task came from ("Epic", "Story", "Bug", "Task",
    /// "Sub-task"). Drives the type badge; nil for tasks not from Jira.
    public var jiraIssueType: String?

    /// Which Sharingan-board column this task sits in (`BoardColumn.id`).
    /// `nil` renders in the first column. Local + synced (CloudKit field).
    public var boardColumnID: String?
    /// When the task was moved to Trash (nil = live). A trashed task stays in
    /// the store so it can be restored, but every normal query filters it out.
    public var trashedAt: Date?
    /// The Mac this task was first created on. Immutable: it travels with the
    /// record over sync and is never overwritten when another Mac edits it.
    public var originDevice: String
    /// The task's issue number — what `code` renders as "T-42". Assigned once,
    /// by `TaskStore` (see `assignMissingNumbers`), and never reused or
    /// renumbered afterwards. 0 means "not assigned yet": a task decoded from a
    /// pre-numbering record, waiting for the store's next backfill pass.
    ///
    /// Numbers are handed out per Mac, so two Macs creating tasks offline can
    /// both mint the same one. The number is display-only — nothing is looked
    /// up or stored by it — so a duplicate reads oddly but breaks nothing.
    public var number: Int

    public init(id: UUID = UUID(),
                title: String,
                category: String = TaskCategory.presets[0].name,
                tags: [String] = [],
                isDone: Bool = false,
                pomodorosDone: Int = 0,
                createdAt: Date = Date(),
                modifiedAt: Date? = nil,
                dueDate: Date? = nil,
                sortOrder: Int = 0,
                estimatedPomodoros: Int? = nil,
                plannedDate: Date? = nil,
                notes: String = "",
                subtasks: [Subtask] = [],
                recurrence: Recurrence = .none,
                project: String? = nil,
                priority: TaskPriority = .none,
                completedAt: Date? = nil,
                pomodoroKind: PomodoroKind? = nil,
                jiraKey: String? = nil,
                jiraIssueID: String? = nil,
                jiraSiteHost: String? = nil,
                jiraIssueType: String? = nil,
                boardColumnID: String? = nil,
                trashedAt: Date? = nil,
                originDevice: String = DeviceIdentity.name,
                number: Int = 0) {
        self.id = id
        self.title = title
        self.category = category
        self.tags = tags
        self.isDone = isDone
        self.pomodorosDone = pomodorosDone
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
        self.dueDate = dueDate
        self.sortOrder = sortOrder
        self.estimatedPomodoros = estimatedPomodoros
        self.plannedDate = plannedDate
        self.notes = notes
        self.subtasks = subtasks
        self.recurrence = recurrence
        self.project = project
        self.priority = priority
        self.completedAt = completedAt
        self.pomodoroKind = pomodoroKind
        self.jiraKey = jiraKey
        self.jiraIssueID = jiraIssueID
        self.jiraSiteHost = jiraSiteHost
        self.jiraIssueType = jiraIssueType
        self.boardColumnID = boardColumnID
        self.trashedAt = trashedAt
        self.originDevice = originDevice
        self.number = number
    }

    // Defensive decoding: several fields (category, tags, pomodorosDone) were
    // added after the first release. Without this, an older tasks.json missing
    // any of them throws `keyNotFound`, TaskStore.load() swallows it, and the
    // next mutation persists an EMPTY list — silently wiping every task.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        category = try c.decodeIfPresent(String.self, forKey: .category)
            ?? TaskCategory.presets[0].name
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        pomodorosDone = try c.decodeIfPresent(Int.self, forKey: .pomodorosDone) ?? 0
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        estimatedPomodoros = try c.decodeIfPresent(Int.self, forKey: .estimatedPomodoros)
        plannedDate = try c.decodeIfPresent(Date.self, forKey: .plannedDate)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        subtasks = try c.decodeIfPresent([Subtask].self, forKey: .subtasks) ?? []
        recurrence = try c.decodeIfPresent(Recurrence.self, forKey: .recurrence) ?? .none
        project = try c.decodeIfPresent(String.self, forKey: .project)
        priority = try c.decodeIfPresent(TaskPriority.self, forKey: .priority) ?? .none
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        pomodoroKind = ((try? c.decodeIfPresent(PomodoroKind.self, forKey: .pomodoroKind)) ?? nil)
        jiraKey = try c.decodeIfPresent(String.self, forKey: .jiraKey)
        jiraIssueID = try c.decodeIfPresent(String.self, forKey: .jiraIssueID)
        jiraSiteHost = try c.decodeIfPresent(String.self, forKey: .jiraSiteHost)
        jiraIssueType = try c.decodeIfPresent(String.self, forKey: .jiraIssueType)
        boardColumnID = try c.decodeIfPresent(String.self, forKey: .boardColumnID)
        trashedAt = try c.decodeIfPresent(Date.self, forKey: .trashedAt)
        // Older records predate origin tracking — attribute them to this Mac.
        originDevice = try c.decodeIfPresent(String.self, forKey: .originDevice) ?? DeviceIdentity.name
        // Records written before numbering land as 0 and are backfilled by the
        // store on its next persist.
        number = try c.decodeIfPresent(Int.self, forKey: .number) ?? 0
    }

    /// True while the task is in the Trash.
    public var isTrashed: Bool { trashedAt != nil }

    /// The task's issue code — "T-42" — shown wherever a task needs to be named
    /// in one glance: the notch, the widget, the menu bar, the board, the task
    /// list, the report. nil until the store has assigned a `number`.
    /// Subtasks read as "T-42.1" (1-based) — see `TaskStore.activeShortLabel`.
    public var code: String? { number > 0 ? "T-\(number)" : nil }

    /// Every word a free-text search can land on: the code, the text fields, and
    /// the human names of the things the UI shows as chips (priority, repeat,
    /// pomodoro size, status, due date). Lowercased, so callers compare against
    /// a lowercased query.
    ///
    /// Dates go in twice — "2026-07-17" and "17 jul 2026" — so both a typed
    /// number and a typed month name hit, alongside the relative words ("today",
    /// "overdue") the user actually reads in the list.
    public func searchHaystack(now: Date = Date()) -> String {
        var parts: [String] = [title, category, notes]
        if let code { parts.append(code) }
        parts.append(contentsOf: tags)
        if let project { parts.append(project) }
        parts.append(contentsOf: subtasks.map(\.title))
        parts.append(originDevice)

        if priority != .none { parts += [priority.label, priority.menuLabel] }
        if recurrence != .none { parts += [recurrence.label, recurrence.stringValue] }
        // Both the display label ("Deep Work") and the stable rawValue ("big")
        // so search keeps matching either.
        if let pomodoroKind { parts += [pomodoroKind.label, pomodoroKind.rawValue] }
        if let estimatedPomodoros { parts.append("\(estimatedPomodoros)p") }

        parts.append(isDone ? "done completed" : "open todo")
        if isTrashed { parts.append("trash trashed deleted") }
        if isOverdue(now: now) { parts.append("overdue late") }

        for (date, prefix) in [(dueDate, "due"), (plannedDate, "planned")] {
            guard let date else { continue }
            parts.append(prefix)
            parts += [Self.numericDay.string(from: date), Self.namedDay.string(from: date)]
            let cal = Calendar.current
            if cal.isDateInToday(date) { parts.append("today") }
            if cal.isDateInTomorrow(date) { parts.append("tomorrow") }
            if cal.isDateInYesterday(date) { parts.append("yesterday") }
        }
        return parts.joined(separator: " ").lowercased()
    }

    /// True when every whitespace-separated word of `query` appears somewhere in
    /// `searchHaystack` — so "urgent design" narrows to tasks that are both,
    /// in either order, rather than matching one long literal.
    public func matchesSearch(_ query: String, now: Date = Date()) -> Bool {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let hay = searchHaystack(now: now)
        return words.allSatisfy { hay.contains($0) }
    }

    private static let numericDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let namedDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM yyyy EEEE"
        return f
    }()

    /// True when the task has a past deadline and isn't finished. A date-only
    /// due (midnight, no time of day) is missed only once its whole day has
    /// passed — otherwise every date-only "today" deadline would read overdue
    /// from the first second of the day.
    public func isOverdue(now: Date = Date()) -> Bool {
        guard let dueDate, !isDone else { return false }
        if DueDate.isDateOnly(dueDate) {
            let cal = Calendar.current
            return cal.startOfDay(for: dueDate) < cal.startOfDay(for: now)
        }
        return dueDate < now
    }

    /// Completed subtasks over total, e.g. (2, 5). Zero total when no subtasks.
    public var subtaskProgress: (done: Int, total: Int) {
        (subtasks.filter(\.isDone).count, subtasks.count)
    }

    /// Sum of subtask estimates, nil when no subtask has one.
    public var subtaskEstimateTotal: Int? {
        let ests = subtasks.compactMap(\.estimatedPomodoros)
        return ests.isEmpty ? nil : ests.reduce(0, +)
    }

    /// Estimate shown for the task: its own when it has no subtasks;
    /// otherwise the sum of subtask estimates (falling back to its own
    /// when no subtask carries one).
    public var effectiveEstimate: Int? { subtaskEstimateTotal ?? estimatedPomodoros }

    /// True when this task is on today's plan.
    public func isPlannedToday(now: Date = Date()) -> Bool {
        guard let plannedDate else { return false }
        return Calendar.current.isDate(plannedDate, inSameDayAs: now)
    }

    public var isJiraLinked: Bool {
        guard let jiraKey, let jiraSiteHost else { return false }
        return !jiraKey.isEmpty && !jiraSiteHost.isEmpty
    }

    public var jiraBrowseURL: URL? {
        guard let jiraKey, let jiraSiteHost, !jiraKey.isEmpty, !jiraSiteHost.isEmpty else { return nil }
        return URL(string: "https://\(jiraSiteHost)/browse/\(jiraKey)")
    }
}

/// A named, color-coded, icon-tagged bucket for tasks.
public struct TaskCategory: Identifiable, Codable, Equatable, Sendable {
    public var name: String
    public var colorHex: String
    /// SF Symbol name shown alongside the category.
    public var icon: String

    public var id: String { name }

    public init(name: String, colorHex: String, icon: String = "folder.fill") {
        self.name = name
        self.colorHex = colorHex
        self.icon = icon
    }

    // `icon` was added later — decode it as optional so older saved
    // categories.json (without the key) still loads.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        colorHex = try c.decode(String.self, forKey: .colorHex)
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "folder.fill"
    }

    public static let presets: [TaskCategory] = [
        .init(name: "Work",     colorHex: "#4F8DFD", icon: "briefcase.fill"),
        .init(name: "Study",    colorHex: "#A66BFF", icon: "book.fill"),
        .init(name: "Personal", colorHex: "#3FD07F", icon: "person.fill"),
        .init(name: "Health",   colorHex: "#FF6FA5", icon: "heart.fill"),
        .init(name: "Other",    colorHex: "#9AA3AF", icon: "folder.fill"),
    ]

    public static func color(for name: String) -> String {
        presets.first { $0.name == name }?.colorHex ?? "#9AA3AF"
    }

    /// Swatches offered when creating a custom category.
    public static let palette: [String] = [
        "#4F8DFD", "#A66BFF", "#3FD07F", "#FF6FA5",
        "#FFB020", "#22C3B8", "#FF6B5E", "#9AA3AF",
    ]

    /// Default fallback icon for a category with no custom icon set — the
    /// connected-nodes graph glyph.
    public static let defaultCategoryIcon = "point.3.connected.trianglepath.dotted"
    /// Default fallback icon for a project with no custom icon set — the grid.
    public static let defaultProjectIcon = "square.grid.2x2.fill"

    /// SF Symbols offered when choosing a category or project icon. The graph
    /// and grid glyphs lead so the two new defaults are one tap away.
    public static let iconChoices: [String] = [
        "point.3.connected.trianglepath.dotted", "square.grid.2x2.fill",
        "briefcase.fill", "book.fill", "person.fill", "heart.fill",
        "folder.fill", "star.fill", "flame.fill", "bolt.fill",
        "cart.fill", "house.fill", "gamecontroller.fill", "dumbbell.fill",
        "cup.and.saucer.fill", "airplane", "pencil", "paintbrush.fill",
        "graduationcap.fill", "chart.bar.fill", "tag.fill", "flag.fill",
    ]
}
