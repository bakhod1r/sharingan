import Foundation

/// A stable per-Mac identity, so a fetched ActiveTimer record can be told
/// apart from an echo of this Mac's own write.
public enum DeviceIdentity {
    static let defaultsKey = "sync.deviceID"

    /// Minted once and persisted; deliberately NOT synced (see SettingsSync's
    /// exclusion list) — two Macs sharing an id would defeat echo suppression.
    public static var current: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: defaultsKey) { return existing }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: defaultsKey)
        return fresh
    }

    /// The user-visible machine name, for "Focus running on <name>" UI.
    public static var name: String {
        Host.current().localizedName ?? "Mac"
    }
}

/// The one live-timer record (`recordName == "active"`): whichever Mac wrote
/// last owns the current session, and every other Mac mirrors it in lockstep.
///
/// Wall-clock contract:
///   - running: `endsAt` is the absolute deadline — receivers align to it, so
///     both Macs end the phase at the same moment regardless of fetch latency.
///   - paused: `endsAt` is frozen relative to `updatedAt` (the pause moment);
///     `remaining(now:)` therefore reads the same on every Mac no matter when
///     the record arrives, and a paused session is never "stale" by clock.
///   - stopped/reset: `phase == ActiveTimerState.idlePhase`, `endsAt == nil`.
public struct ActiveTimerState: Codable, Equatable, Sendable {
    /// One record, not one per Mac — the constant CloudKit record name.
    public static let recordName = "active"
    /// The phase string for a stopped/reset timer (PomodoroPhase has no such
    /// case — an idle timer shows a pending focus, which is not a session).
    public static let idlePhase = "idle"

    public let deviceID: String
    public let deviceName: String
    /// PomodoroPhase rawValue of the *effective* phase (never "paused" —
    /// `isPaused` carries that separately), or `idlePhase`.
    public let phase: String
    public let startedAt: Date
    public let endsAt: Date?
    public let isPaused: Bool
    public let taskTitle: String?
    public let updatedAt: Date

    public init(deviceID: String, deviceName: String, phase: String,
                startedAt: Date, endsAt: Date?, isPaused: Bool,
                taskTitle: String?, updatedAt: Date) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.phase = phase
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.isPaused = isPaused
        self.taskTitle = taskTitle
        self.updatedAt = updatedAt
    }

    /// Seconds left in the mirrored session as of `now` — the pause contract
    /// above, in one place, so publisher and receiver cannot disagree.
    public func remaining(now: Date = Date()) -> TimeInterval {
        guard let endsAt else { return 0 }
        return max(0, endsAt.timeIntervalSince(isPaused ? updatedAt : now))
    }

    public var isIdle: Bool { phase == Self.idlePhase }

    /// Stable hash for the sync shadow.
    public var contentHash: String { SyncShadow.hash(self) }

    /// Whether two states describe the same session moment, ignoring
    /// timestamps' sub-second jitter — the publisher's dedup, so a re-fired
    /// Combine sink doesn't re-upload an identical record.
    public func samePayload(as other: ActiveTimerState,
                            tolerance: TimeInterval = 2) -> Bool {
        func close(_ a: Date?, _ b: Date?) -> Bool {
            switch (a, b) {
            case (nil, nil): return true
            case let (x?, y?): return abs(x.timeIntervalSince(y)) <= tolerance
            default: return false
            }
        }
        return deviceID == other.deviceID
            && phase == other.phase
            && isPaused == other.isPaused
            && taskTitle == other.taskTitle
            && close(startedAt, other.startedAt)
            && close(endsAt, other.endsAt)
    }
}
