import Foundation

/// What the sync layer is doing right now, for the Settings status line.
/// Deliberately a value the UI can render directly — the engine never asks
/// the UI to interpret CKError codes.
public enum SyncStatus: Equatable, Sendable {
    /// Sync is switched off (the default) — the app behaves as if the
    /// feature did not exist.
    case disabled
    /// Sync is on but cannot run: no iCloud account, the build carries no
    /// iCloud entitlement, the container is unreachable. The string is the
    /// human-readable reason, already phrased for the status line.
    case unavailable(String)
    /// Nothing in flight. `lastSynced` is nil before the first round trip.
    case idle(lastSynced: Date?)
    case syncing
    case failed(String)

    public var isActive: Bool {
        if case .syncing = self { return true }
        return false
    }

    /// The Settings status line.
    public func label(now: Date = Date()) -> String {
        switch self {
        case .disabled:
            return "Off"
        case .unavailable(let reason):
            return reason
        case .syncing:
            return "Syncing…"
        case .failed(let message):
            return message
        case .idle(let lastSynced):
            guard let lastSynced else { return "Waiting for first sync" }
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return "Last synced \(formatter.localizedString(for: lastSynced, relativeTo: now))"
        }
    }
}
