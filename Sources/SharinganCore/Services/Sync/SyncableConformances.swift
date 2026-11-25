import Foundation

/// Record names are the CloudKit primary keys — they must be stable for the
/// life of the object, or an edit becomes a delete + create and every other
/// Mac sees the task blink out and reappear.
extension TaskItem: SyncableRecord {
    public var recordName: String { id.uuidString }

    /// Everything synced, and nothing else: modifiedAt is deliberately
    /// excluded so that touching a task without editing it costs no upload.
    public var contentHash: String {
        SyncShadow.hash(SyncPayload(
            title: title, category: category, tags: tags, isDone: isDone,
            pomodorosDone: pomodorosDone, createdAt: createdAt, dueDate: dueDate,
            sortOrder: sortOrder, estimatedPomodoros: estimatedPomodoros,
            plannedDate: plannedDate, notes: notes, subtasks: subtasks,
            recurrence: recurrence.stringValue, project: project,
            priority: priority.rawValue, completedAt: completedAt,
            pomodoroKind: pomodoroKind?.rawValue, jiraKey: jiraKey,
            jiraIssueID: jiraIssueID, jiraSiteHost: jiraSiteHost,
            jiraIssueType: jiraIssueType,
            boardColumnID: boardColumnID, trashedAt: trashedAt,
            allowedApps: allowedApps.isEmpty ? nil : allowedApps))
    }

    // originDevice and number are deliberately NOT hashed: both are immutable
    // and set locally at creation, so two Macs that assign their own value for
    // a task created before the field existed must not read as "changed" and
    // sync-fight. (For number that fight would be endless: each Mac backfills
    // its own sequence, stamps modifiedAt, pushes, and the other backfills
    // back.) Both still travel in the CKRecord (see RecordMapper) — the hash
    // just doesn't gate on them.
    private struct SyncPayload: Encodable {
        let title: String, category: String, tags: [String], isDone: Bool
        let pomodorosDone: Int, createdAt: Date, dueDate: Date?
        let sortOrder: Int, estimatedPomodoros: Int?, plannedDate: Date?
        let notes: String, subtasks: [Subtask], recurrence: String
        let project: String?, priority: Int, completedAt: Date?, pomodoroKind: String?
        let jiraKey: String?, jiraIssueID: String?, jiraSiteHost: String?
        // nil when absent, so existing hashes are unchanged.
        let jiraIssueType: String?
        let boardColumnID: String?, trashedAt: Date?
        // nil when empty so tasks without an allow-list keep their existing hash
        // (no fleet-wide re-upload on upgrade).
        let allowedApps: [BlockedApp]?
    }
}

extension TaskCategory: SyncableRecord {
    public var recordName: String { name }
    public var contentHash: String { SyncShadow.hash(self) }
}

extension TaskTemplate: SyncableRecord {
    public var recordName: String { id.uuidString }
    public var contentHash: String { SyncShadow.hash(self) }
}

/// One record per (day, task, subtask) — the same triple from two Macs is the
/// same record whose counts merge (see MergePolicy), never two rival rows.
extension FocusLogEntry: SyncableRecord {
    public var recordName: String {
        "\(Int(day.timeIntervalSince1970))|\(taskID.uuidString)|\(subtaskID?.uuidString ?? "")"
    }
    public var contentHash: String { SyncShadow.hash(self) }
}

/// Tags are bare Strings in the store; a wrapper keeps SyncableRecord from
/// leaking onto every String in the codebase.
public struct SyncableTag: SyncableRecord, Equatable, Sendable {
    public let name: String
    public init(_ name: String) { self.name = name }
    public var recordName: String { name }
    public var contentHash: String { name }
}

/// A custom project. Same payload as a category, but its own record type AND a
/// prefixed record name: CloudKit record names are unique per zone regardless
/// of type, so a project "Work" and a category "Work" would otherwise be the
/// same record. Rename = delete old + create new, exactly like categories.
public struct SyncableProject: SyncableRecord, Equatable, Sendable {
    public let category: TaskCategory
    public init(_ category: TaskCategory) { self.category = category }
    public static func recordName(forName name: String) -> String { "project|\(name)" }
    public var recordName: String { Self.recordName(forName: category.name) }
    public var contentHash: String { SyncShadow.hash(category) }
}

/// Session records are immutable and keyed by their own unique id, so the same
/// session from two Macs is one record and merging is a plain union.
extension SessionRecord: SyncableRecord {
    public var recordName: String { "session|\(id.uuidString)" }

    /// Timestamps are hashed at millisecond precision: CloudKit stores dates to
    /// the millisecond, so hashing the raw Double would make the record the
    /// server hands back differ from the local one forever (a push loop).
    public var contentHash: String {
        SyncShadow.hash(SyncPayload(
            id: id, startMS: Int((start.timeIntervalSince1970 * 1000).rounded()),
            endMS: Int((end.timeIntervalSince1970 * 1000).rounded()),
            phase: phase.rawValue, completed: completed, taskID: taskID,
            subtaskID: subtaskID, taskTitle: taskTitle, plannedSeconds: plannedSeconds,
            appUsage: appUsage, deviceName: deviceName, deviceID: deviceID))
    }

    private struct SyncPayload: Encodable {
        let id: UUID, startMS: Int, endMS: Int, phase: String, completed: Bool
        let taskID: UUID?, subtaskID: UUID?, taskTitle: String?
        let plannedSeconds: Double, appUsage: [String: Double]
        let deviceName: String?, deviceID: String?
    }
}
