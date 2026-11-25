import CloudKit
import Foundation

public enum SyncRecordType: String, CaseIterable, Sendable {
    case task = "Task"
    case category = "Category"
    case tag = "Tag"
    case template = "Template"
    case focusLog = "FocusLog"
    case activeTimer = "ActiveTimer"
    case project = "Project"
    case session = "FocusSession"
    case deviceStats = "DeviceStats"
}

/// Row ⇄ CKRecord. Kept pure and separate from the engine so the wire format
/// can be tested exhaustively without an iCloud account.
public enum RecordMapper {
    /// Bumped whenever a field's meaning changes; a record from the future is
    /// decoded on a best-effort basis rather than rejected, and its system
    /// fields are preserved so re-saving it never drops what this build cannot
    /// see (see systemFields).
    public static let schemaVersion = 1

    // MARK: Task

    public static func record(for task: TaskItem,
                              in zoneID: CKRecordZone.ID,
                              systemFields: Data?) -> CKRecord {
        let record = base(recordType: .task, name: task.recordName,
                          zoneID: zoneID, systemFields: systemFields)
        record["title"] = task.title as CKRecordValue
        record["category"] = task.category as CKRecordValue
        record["tags"] = task.tags as CKRecordValue
        record["isDone"] = (task.isDone ? 1 : 0) as CKRecordValue
        record["pomodorosDone"] = task.pomodorosDone as CKRecordValue
        record["createdAt"] = task.createdAt as CKRecordValue
        record["modifiedAt"] = task.modifiedAt as CKRecordValue
        record["dueDate"] = task.dueDate as CKRecordValue?
        record["plannedDate"] = task.plannedDate as CKRecordValue?
        record["completedAt"] = task.completedAt as CKRecordValue?
        record["sortOrder"] = task.sortOrder as CKRecordValue
        record["estimatedPomodoros"] = task.estimatedPomodoros as CKRecordValue?
        record["notes"] = task.notes as CKRecordValue
        record["recurrence"] = task.recurrence.stringValue as CKRecordValue
        record["project"] = task.project as CKRecordValue?
        record["priority"] = task.priority.rawValue as CKRecordValue
        record["pomodoroKind"] = task.pomodoroKind?.rawValue as CKRecordValue?
        record["jiraKey"] = task.jiraKey as CKRecordValue?
        record["jiraIssueID"] = task.jiraIssueID as CKRecordValue?
        record["jiraSiteHost"] = task.jiraSiteHost as CKRecordValue?
        record["jiraIssueType"] = task.jiraIssueType as CKRecordValue?
        record["boardColumnID"] = task.boardColumnID as CKRecordValue?
        // Optional, backward compatible: older peers ignore it, older records lack it.
        record["trashedAt"] = task.trashedAt as CKRecordValue?
        record["originDevice"] = task.originDevice as CKRecordValue
        record["number"] = task.number as CKRecordValue
        // Subtasks are a nested value type with their own evolving shape —
        // JSON keeps them one field instead of a parallel record type whose
        // deletes would have to be tracked separately.
        record["subtasksJSON"] = json(task.subtasks) as CKRecordValue?
        record["allowedAppsJSON"] = json(task.allowedApps) as CKRecordValue?
        record["attentionGuard"] = (task.attentionGuard ? 1 : 0) as CKRecordValue
        record["schemaVersion"] = schemaVersion as CKRecordValue
        return record
    }

    public static func task(from record: CKRecord) -> TaskItem? {
        guard record.recordType == SyncRecordType.task.rawValue,
              let id = UUID(uuidString: record.recordID.recordName),
              let title = record["title"] as? String,
              let category = record["category"] as? String,
              let createdAt = record["createdAt"] as? Date
        else { return nil }

        var task = TaskItem(id: id, title: title, category: category)
        task.createdAt = createdAt
        task.modifiedAt = record["modifiedAt"] as? Date ?? createdAt
        task.tags = record["tags"] as? [String] ?? []
        task.isDone = (record["isDone"] as? Int ?? 0) == 1
        task.pomodorosDone = record["pomodorosDone"] as? Int ?? 0
        task.dueDate = record["dueDate"] as? Date
        task.plannedDate = record["plannedDate"] as? Date
        task.completedAt = record["completedAt"] as? Date
        task.sortOrder = record["sortOrder"] as? Int ?? 0
        task.estimatedPomodoros = record["estimatedPomodoros"] as? Int
        task.notes = record["notes"] as? String ?? ""
        if let raw = record["recurrence"] as? String {
            task.recurrence = Recurrence(string: raw)
        }
        task.project = record["project"] as? String
        if let priority = record["priority"] as? Int {
            task.priority = TaskPriority(rawValue: priority)
        }
        if let kind = record["pomodoroKind"] as? String {
            task.pomodoroKind = PomodoroKind(rawValue: kind)
        }
        task.jiraKey = record["jiraKey"] as? String
        task.jiraIssueID = record["jiraIssueID"] as? String
        task.jiraSiteHost = record["jiraSiteHost"] as? String
        task.jiraIssueType = record["jiraIssueType"] as? String
        task.boardColumnID = record["boardColumnID"] as? String
        task.trashedAt = record["trashedAt"] as? Date
        if let raw = record["subtasksJSON"] as? String {
            task.subtasks = decode([Subtask].self, from: raw) ?? []
        }
        task.allowedApps = (record["allowedAppsJSON"] as? String)
            .flatMap { decode([BlockedApp].self, from: $0) } ?? []
        task.attentionGuard = (record["attentionGuard"] as? Int ?? 0) == 1
        // Keep the creator's device; a record from a peer that predates origin
        // tracking has none, so fall back to this Mac rather than crashing.
        task.originDevice = record["originDevice"] as? String ?? DeviceIdentity.name
        // A record written before numbering carries no number; it lands as 0 and
        // this Mac's store backfills one.
        task.number = record["number"] as? Int ?? 0
        return task
    }

    // MARK: Focus log

    public static func record(for entry: FocusLogEntry,
                              in zoneID: CKRecordZone.ID,
                              systemFields: Data?) -> CKRecord {
        let record = base(recordType: .focusLog, name: entry.recordName,
                          zoneID: zoneID, systemFields: systemFields)
        record["day"] = entry.day as CKRecordValue
        record["taskID"] = entry.taskID.uuidString as CKRecordValue
        record["subtaskID"] = entry.subtaskID?.uuidString as CKRecordValue?
        record["title"] = entry.title as CKRecordValue
        record["count"] = entry.count as CKRecordValue
        record["seconds"] = entry.seconds as CKRecordValue
        record["schemaVersion"] = schemaVersion as CKRecordValue
        return record
    }

    public static func focusLog(from record: CKRecord) -> FocusLogEntry? {
        guard record.recordType == SyncRecordType.focusLog.rawValue,
              let day = record["day"] as? Date,
              let rawTask = record["taskID"] as? String,
              let taskID = UUID(uuidString: rawTask)
        else { return nil }
        return FocusLogEntry(
            day: day,
            taskID: taskID,
            subtaskID: (record["subtaskID"] as? String).flatMap(UUID.init(uuidString:)),
            title: record["title"] as? String ?? "",
            count: record["count"] as? Int ?? 0,
            seconds: record["seconds"] as? Double ?? 0)
    }

    // MARK: Category / Tag / Template

    public static func record(for category: TaskCategory,
                              in zoneID: CKRecordZone.ID,
                              systemFields: Data?) -> CKRecord {
        let record = base(recordType: .category, name: category.recordName,
                          zoneID: zoneID, systemFields: systemFields)
        record["name"] = category.name as CKRecordValue
        record["colorHex"] = category.colorHex as CKRecordValue
        record["icon"] = category.icon as CKRecordValue
        record["schemaVersion"] = schemaVersion as CKRecordValue
        return record
    }

    public static func category(from record: CKRecord) -> TaskCategory? {
        guard record.recordType == SyncRecordType.category.rawValue,
              let name = record["name"] as? String,
              let colorHex = record["colorHex"] as? String,
              let icon = record["icon"] as? String
        else { return nil }
        return TaskCategory(name: name, colorHex: colorHex, icon: icon)
    }

    public static func record(for tag: SyncableTag,
                              in zoneID: CKRecordZone.ID,
                              systemFields: Data?) -> CKRecord {
        let record = base(recordType: .tag, name: tag.recordName,
                          zoneID: zoneID, systemFields: systemFields)
        record["name"] = tag.name as CKRecordValue
        record["schemaVersion"] = schemaVersion as CKRecordValue
        return record
    }

    public static func tag(from record: CKRecord) -> SyncableTag? {
        guard record.recordType == SyncRecordType.tag.rawValue,
              let name = record["name"] as? String else { return nil }
        return SyncableTag(name)
    }

    public static func record(for template: TaskTemplate,
                              in zoneID: CKRecordZone.ID,
                              systemFields: Data?) -> CKRecord {
        let record = base(recordType: .template, name: template.recordName,
                          zoneID: zoneID, systemFields: systemFields)
        record["name"] = template.name as CKRecordValue
        record["json"] = (json(template) ?? "") as CKRecordValue
        record["schemaVersion"] = schemaVersion as CKRecordValue
        return record
    }

    public static func template(from record: CKRecord) -> TaskTemplate? {
        guard record.recordType == SyncRecordType.template.rawValue,
              let raw = record["json"] as? String else { return nil }
        return decode(TaskTemplate.self, from: raw)
    }

    // MARK: Project

    public static func record(for project: SyncableProject,
                              in zoneID: CKRecordZone.ID,
                              systemFields: Data?) -> CKRecord {
        let record = base(recordType: .project, name: project.recordName,
                          zoneID: zoneID, systemFields: systemFields)
        record["name"] = project.category.name as CKRecordValue
        record["colorHex"] = project.category.colorHex as CKRecordValue
        record["icon"] = project.category.icon as CKRecordValue
        record["schemaVersion"] = schemaVersion as CKRecordValue
        return record
    }

    public static func project(from record: CKRecord) -> TaskCategory? {
        guard record.recordType == SyncRecordType.project.rawValue,
              let name = record["name"] as? String,
              let colorHex = record["colorHex"] as? String,
              let icon = record["icon"] as? String
        else { return nil }
        return TaskCategory(name: name, colorHex: colorHex, icon: icon)
    }

    // MARK: Focus session

    public static func record(for session: SessionRecord,
                              in zoneID: CKRecordZone.ID,
                              systemFields: Data?) -> CKRecord {
        let record = base(recordType: .session, name: session.recordName,
                          zoneID: zoneID, systemFields: systemFields)
        record["sessionID"] = session.id.uuidString as CKRecordValue
        record["start"] = session.start as CKRecordValue
        record["end"] = session.end as CKRecordValue
        record["phase"] = session.phase.rawValue as CKRecordValue
        record["completed"] = (session.completed ? 1 : 0) as CKRecordValue
        record["taskID"] = session.taskID?.uuidString as CKRecordValue?
        record["subtaskID"] = session.subtaskID?.uuidString as CKRecordValue?
        record["taskTitle"] = session.taskTitle as CKRecordValue?
        record["plannedSeconds"] = session.plannedSeconds as CKRecordValue
        record["appUsageJSON"] = (session.appUsage.isEmpty ? nil : json(session.appUsage)) as CKRecordValue?
        record["deviceName"] = session.deviceName as CKRecordValue?
        record["deviceID"] = session.deviceID as CKRecordValue?
        record["attentionAwayEvents"] = session.attentionAwayEvents as CKRecordValue?
        record["attentionAwaySeconds"] = session.attentionAwaySeconds as CKRecordValue?
        record["schemaVersion"] = schemaVersion as CKRecordValue
        return record
    }

    public static func sessionRecord(from record: CKRecord) -> SessionRecord? {
        guard record.recordType == SyncRecordType.session.rawValue,
              let rawID = record["sessionID"] as? String,
              let id = UUID(uuidString: rawID),
              let start = record["start"] as? Date,
              let end = record["end"] as? Date,
              let rawPhase = record["phase"] as? String,
              let phase = PomodoroPhase(rawValue: rawPhase)
        else { return nil }
        var session = SessionRecord(
            id: id, start: start, end: end, phase: phase,
            completed: (record["completed"] as? Int ?? 1) == 1,
            taskID: (record["taskID"] as? String).flatMap(UUID.init(uuidString:)),
            subtaskID: (record["subtaskID"] as? String).flatMap(UUID.init(uuidString:)),
            taskTitle: record["taskTitle"] as? String,
            plannedSeconds: record["plannedSeconds"] as? Double ?? end.timeIntervalSince(start),
            appUsage: (record["appUsageJSON"] as? String)
                .flatMap { decode([String: TimeInterval].self, from: $0) } ?? [:],
            deviceName: record["deviceName"] as? String,
            deviceID: record["deviceID"] as? String)
        session.attentionAwayEvents = record["attentionAwayEvents"] as? Int
        session.attentionAwaySeconds = record["attentionAwaySeconds"] as? Double
        return session
    }

    // MARK: Device stats

    public static func record(for stats: DeviceDailyStats,
                              in zoneID: CKRecordZone.ID,
                              systemFields: Data?) -> CKRecord {
        let record = base(recordType: .deviceStats, name: stats.recordName,
                          zoneID: zoneID, systemFields: systemFields)
        record["deviceID"] = stats.deviceID as CKRecordValue
        record["deviceName"] = stats.deviceName as CKRecordValue
        record["dayStamps"] = stats.days.map { Int($0.day.timeIntervalSince1970) } as CKRecordValue
        record["dayCounts"] = stats.days.map(\.count) as CKRecordValue
        record["hourCounts"] = stats.hourCounts as CKRecordValue
        record["schemaVersion"] = schemaVersion as CKRecordValue
        return record
    }

    public static func deviceStats(from record: CKRecord) -> DeviceDailyStats? {
        guard record.recordType == SyncRecordType.deviceStats.rawValue,
              let deviceID = record["deviceID"] as? String,
              let stamps = record["dayStamps"] as? [Int],
              let counts = record["dayCounts"] as? [Int],
              stamps.count == counts.count
        else { return nil }
        let days = zip(stamps, counts).map {
            DailyCount(day: Date(timeIntervalSince1970: TimeInterval($0)), count: $1)
        }
        return DeviceDailyStats(deviceID: deviceID,
                                deviceName: record["deviceName"] as? String ?? "Mac",
                                days: days,
                                hourCounts: record["hourCounts"] as? [Int] ?? [])
    }

    // MARK: Active timer

    public static func record(for state: ActiveTimerState,
                              in zoneID: CKRecordZone.ID,
                              systemFields: Data?) -> CKRecord {
        let record = base(recordType: .activeTimer, name: ActiveTimerState.recordName,
                          zoneID: zoneID, systemFields: systemFields)
        record["deviceID"] = state.deviceID as CKRecordValue
        record["deviceName"] = state.deviceName as CKRecordValue
        record["phase"] = state.phase as CKRecordValue
        record["startedAt"] = state.startedAt as CKRecordValue
        record["endsAt"] = state.endsAt as CKRecordValue?
        record["isPaused"] = (state.isPaused ? 1 : 0) as CKRecordValue
        record["taskTitle"] = state.taskTitle as CKRecordValue?
        record["updatedAt"] = state.updatedAt as CKRecordValue
        record["schemaVersion"] = schemaVersion as CKRecordValue
        return record
    }

    public static func activeTimer(from record: CKRecord) -> ActiveTimerState? {
        guard record.recordType == SyncRecordType.activeTimer.rawValue,
              let deviceID = record["deviceID"] as? String,
              let phase = record["phase"] as? String,
              let startedAt = record["startedAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date
        else { return nil }
        return ActiveTimerState(
            deviceID: deviceID,
            deviceName: record["deviceName"] as? String ?? "Mac",
            phase: phase,
            startedAt: startedAt,
            endsAt: record["endsAt"] as? Date,
            isPaused: (record["isPaused"] as? Int ?? 0) == 1,
            taskTitle: record["taskTitle"] as? String,
            updatedAt: updatedAt)
    }

    // MARK: Plumbing

    /// Re-hydrating a record from its archived system fields is what makes a
    /// save an UPDATE rather than a clobbering overwrite: CloudKit compares
    /// the record's change tag and rejects a stale write, which is how the
    /// engine learns a conflict happened at all.
    private static func base(recordType: SyncRecordType, name: String,
                             zoneID: CKRecordZone.ID, systemFields: Data?) -> CKRecord {
        if let systemFields,
           let coder = try? NSKeyedUnarchiver(forReadingFrom: systemFields) {
            coder.requiresSecureCoding = true
            if let record = CKRecord(coder: coder) {
                coder.finishDecoding()
                return record
            }
        }
        return CKRecord(recordType: recordType.rawValue,
                        recordID: CKRecord.ID(recordName: name, zoneID: zoneID))
    }

    public static func systemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        return coder.encodedData
    }

    private static func json<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from raw: String) -> T? {
        guard let data = raw.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }
}
