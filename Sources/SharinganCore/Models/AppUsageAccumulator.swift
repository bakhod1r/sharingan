import Foundation

/// Pure time-attribution core behind active-app tracking: given a stream of
/// "app X became frontmost at time T" events (plus idle/flush ticks), it
/// accumulates focused seconds per app bundle ID. AppKit wiring
/// (`ActiveAppTracker`) feeds it; this stays testable with no I/O.
///
/// Idle handling: while idle the current app earns nothing — the caller sends
/// `idle(at:)` when the user has been away past the threshold, which credits
/// time up to the idle point and then parks (no app current) until the next
/// `activate`.
public struct AppUsageAccumulator: Equatable, Sendable {
    private var usage: [String: TimeInterval] = [:]
    private var current: String?
    private var since: Date?

    public init() {}

    /// The frontmost app changed (or tracking just began). Credits the previous
    /// app up to `date`, then starts counting `bundleID` (nil = nothing to
    /// count, e.g. an untracked app).
    public mutating func activate(bundleID: String?, at date: Date) {
        creditCurrent(upTo: date)
        current = bundleID
        since = bundleID == nil ? nil : date
    }

    /// The user went idle at `date`: credit the current app up to here and stop
    /// counting until the next `activate`.
    public mutating func idle(at date: Date) {
        creditCurrent(upTo: date)
        current = nil
        since = nil
    }

    /// Credit the current app up to `date` without changing what's current —
    /// used when a session ends while an app is still frontmost.
    public mutating func flush(at date: Date) {
        creditCurrent(upTo: date)
        since = date
    }

    private mutating func creditCurrent(upTo date: Date) {
        guard let app = current, let start = since else { return }
        let delta = date.timeIntervalSince(start)
        if delta > 0 { usage[app, default: 0] += delta }
    }

    /// Accumulated seconds per bundle ID so far (excludes any uncredited
    /// in-flight time — call `flush` first to include it).
    public func result() -> [String: TimeInterval] { usage }
}
