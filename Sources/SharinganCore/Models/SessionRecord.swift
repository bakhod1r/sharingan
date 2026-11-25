import CryptoKit
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
    /// Stable per-install id (`DeviceIdentity.current`) of the Mac that ran this
    /// session. nil for records written before sync of the session log.
    public var deviceID: String?

    public var seconds: TimeInterval { end.timeIntervalSince(start) }

    public init(id: UUID = UUID(), start: Date, end: Date, phase: PomodoroPhase,
                completed: Bool, taskID: UUID? = nil, subtaskID: UUID? = nil,
                taskTitle: String? = nil, plannedSeconds: TimeInterval,
                appUsage: [String: TimeInterval] = [:],
                deviceName: String? = nil, deviceID: String? = nil) {
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
        self.deviceID = deviceID
    }

    // Defensive decoding so adding fields never resets the user's log
    // (same principle as PomodoroStats).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decode(Date.self, forKey: .end)
        phase = try c.decodeIfPresent(PomodoroPhase.self, forKey: .phase) ?? .focus
        // A record that predates ids gets one derived from its content, never a
        // random one: it must be the same on every load (and on every Mac), or
        // the session log would mint a new CloudKit identity per launch.
        id = try c.decodeIfPresent(UUID.self, forKey: .id)
            ?? Self.legacyID(start: start, end: end, phase: phase)
        completed = try c.decodeIfPresent(Bool.self, forKey: .completed) ?? true
        taskID = try c.decodeIfPresent(UUID.self, forKey: .taskID)
        subtaskID = try c.decodeIfPresent(UUID.self, forKey: .subtaskID)
        taskTitle = try c.decodeIfPresent(String.self, forKey: .taskTitle)
        plannedSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .plannedSeconds)
            ?? end.timeIntervalSince(start)
        appUsage = try c.decodeIfPresent([String: TimeInterval].self, forKey: .appUsage) ?? [:]
        deviceName = try c.decodeIfPresent(String.self, forKey: .deviceName)
        deviceID = try c.decodeIfPresent(String.self, forKey: .deviceID)
    }

    /// Deterministic UUID (version-5 style, SHA-256 truncated) for a record
    /// with no stored id. Two Macs decoding the same legacy bytes agree.
    public static func legacyID(start: Date, end: Date, phase: PomodoroPhase) -> UUID {
        let key = "session|\(start.timeIntervalSince1970)|\(end.timeIntervalSince1970)|\(phase.rawValue)"
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5],
                           bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
