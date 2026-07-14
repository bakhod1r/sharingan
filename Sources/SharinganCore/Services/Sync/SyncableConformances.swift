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
            pomodoroKind: pomodoroKind?.rawValue))
    }

    private struct SyncPayload: Encodable {
        let title: String, category: String, tags: [String], isDone: Bool
        let pomodorosDone: Int, createdAt: Date, dueDate: Date?
        let sortOrder: Int, estimatedPomodoros: Int?, plannedDate: Date?
        let notes: String, subtasks: [Subtask], recurrence: String
        let project: String?, priority: Int, completedAt: Date?, pomodoroKind: String?
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
