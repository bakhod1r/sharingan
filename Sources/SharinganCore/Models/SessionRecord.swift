import Foundation

/// One finished (or abandoned) timer session — the per-session grain behind
/// analytics: scores, the day timeline, time machine, and burnout detection.
/// Aggregate stats (`PomodoroStats`, `FocusLogEntry`) stay the source of truth
/// for their own surfaces; this log is additive.
public struct SessionRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var start: Date
    public var end: Date
    public var phase: PomodoroPhase
    /// false = the session was skipped or stopped before its planned end.
    public var completed: Bool
    public var taskID: UUID?
    public var subtaskID: UUID?
    /// Snapshot at credit time so history survives task deletion.
    public var taskTitle: String?
    public var plannedSeconds: TimeInterval
    /// Frontmost-app seconds during the session (bundleID → seconds).
    /// Empty when active-app tracking is off for the session.
    public var appUsage: [String: TimeInterval]
    /// The Mac this session ran on (`Host.current().localizedName`), so a
    /// multi-Mac user can slice analytics per machine. nil for pre-1.9 records.
    public var deviceName: String?

    public var seconds: TimeInterval { end.timeIntervalSince(start) }

    public init(id: UUID = UUID(), start: Date, end: Date, phase: PomodoroPhase,
                completed: Bool, taskID: UUID? = nil, subtaskID: UUID? = nil,
                taskTitle: String? = nil, plannedSeconds: TimeInterval,
                appUsage: [String: TimeInterval] = [:],
                deviceName: String? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.phase = phase
        self.completed = completed
        self.taskID = taskID
        self.subtaskID = subtaskID
        self.taskTitle = taskTitle
        self.plannedSeconds = plannedSeconds
        self.appUsage = appUsage
        self.deviceName = deviceName
    }

    // Defensive decoding so adding fields never resets the user's log
    // (same principle as PomodoroStats).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decode(Date.self, forKey: .end)
        phase = try c.decodeIfPresent(PomodoroPhase.self, forKey: .phase) ?? .focus
        completed = try c.decodeIfPresent(Bool.self, forKey: .completed) ?? true
        taskID = try c.decodeIfPresent(UUID.self, forKey: .taskID)
        subtaskID = try c.decodeIfPresent(UUID.self, forKey: .subtaskID)
        taskTitle = try c.decodeIfPresent(String.self, forKey: .taskTitle)
        plannedSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .plannedSeconds)
            ?? end.timeIntervalSince(start)
        appUsage = try c.decodeIfPresent([String: TimeInterval].self, forKey: .appUsage) ?? [:]
        deviceName = try c.decodeIfPresent(String.self, forKey: .deviceName)
    }
}
