import Foundation

/// One aggregate row of the per-day focus attribution log: how many pomodoros
/// (and real focus seconds) landed on `taskID` — or on one of its subtasks
/// when `subtaskID` is set — during `day`. The task-level row (subtaskID nil)
/// is the day's source of truth for the task and already INCLUDES any
/// subtask-attributed sessions, mirroring `incrementPomodoro`'s counters;
/// never sum task rows and subtask rows together. `title` is a snapshot taken
/// at credit time so history survives task deletion.
public struct FocusLogEntry: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var day: Date              // start-of-day
    public var taskID: UUID
    public var subtaskID: UUID?
    public var title: String
    public var count: Int
    public var seconds: TimeInterval

    public var id: String {
        "\(day.timeIntervalSince1970)-\(taskID.uuidString)-\(subtaskID?.uuidString ?? "task")"
    }

    public init(day: Date, taskID: UUID, subtaskID: UUID?,
                title: String, count: Int, seconds: TimeInterval) {
        self.day = day
        self.taskID = taskID
        self.subtaskID = subtaskID
        self.title = title
        self.count = count
        self.seconds = seconds
    }
}

/// A Report-table row: one task-level entry with its same-day subtask entries
/// nested, resolved against the live task list for done/deleted/category
/// presentation.
public struct FocusReportRow: Identifiable, Equatable, Sendable {
    public var entry: FocusLogEntry
    public var subrows: [FocusLogEntry]
    public var isDone: Bool
    public var isDeleted: Bool
    public var category: String?
    public var id: String { entry.id }

    public init(entry: FocusLogEntry, subrows: [FocusLogEntry],
                isDone: Bool, isDeleted: Bool, category: String?) {
        self.entry = entry
        self.subrows = subrows
        self.isDone = isDone
        self.isDeleted = isDeleted
        self.category = category
    }
}

/// How the day report's task rows are ordered — the Report view's sort menu.
/// `time` is the original most-focus-first order `FocusReport.rows` produces;
/// the other modes re-rank on their key and keep the time order as a stable
/// tiebreak.
public enum ReportSortMode: String, CaseIterable, Identifiable, Sendable {
    case time, pomodoros, title

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .time:      return "Focus time"
        case .pomodoros: return "Pomodoros"
        case .title:     return "A–Z"
        }
    }

    public var icon: String {
        switch self {
        case .time:      return "clock"
        case .pomodoros: return "circle.circle"
        case .title:     return "textformat.abc"
        }
    }

    public func apply(_ rows: [FocusReportRow]) -> [FocusReportRow] {
        guard self != .time else { return rows }
        return rows.enumerated().sorted { a, b in
            switch self {
            case .time:
                break
            case .pomodoros:
                if a.element.entry.count != b.element.entry.count {
                    return a.element.entry.count > b.element.entry.count
                }
            case .title:
                let c = a.element.entry.title
                    .localizedCaseInsensitiveCompare(b.element.entry.title)
                if c != .orderedSame { return c == .orderedAscending }
            }
            return a.offset < b.offset
        }.map(\.element)
    }
}

public enum FocusReport {
    /// Task-level rows for one day's entries, minutes-descending, each with
    /// its subtask entries attached. `tasks` is the live list used to resolve
    /// done state and category; a missing task marks the row deleted.
    public static func rows(entries: [FocusLogEntry], tasks: [TaskItem]) -> [FocusReportRow] {
        entries.filter { $0.subtaskID == nil }
            .sorted { $0.seconds > $1.seconds }
            .map { e in
                let live = tasks.first { $0.id == e.taskID }
                let subs = entries
                    .filter { $0.taskID == e.taskID && $0.subtaskID != nil }
                    .sorted { $0.seconds > $1.seconds }
                return FocusReportRow(entry: e, subrows: subs,
                                      isDone: live?.isDone ?? false,
                                      isDeleted: live == nil,
                                      category: live?.category)
            }
    }

    /// "42m", "1h 15m", "2h" — minutes rounded from seconds.
    public static func durationLabel(_ seconds: TimeInterval) -> String {
        let m = Int((seconds / 60).rounded())
        if m < 60 { return "\(m)m" }
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
    }
}
