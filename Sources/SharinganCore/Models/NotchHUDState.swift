import Foundation

/// A transient announcement the island makes on its own, then collapses.
public enum NotchActivity: Equatable, Sendable {
    case sessionDone
    case breakStarted
    case taskDone(String)

    public var message: String {
        switch self {
        case .sessionDone:        return "Session complete"
        case .breakStarted:       return "Break time"
        case .taskDone(let title): return "Done: \(title)"
        }
    }

    public var systemImage: String {
        switch self {
        case .sessionDone:  return "checkmark.circle.fill"
        case .breakStarted: return "cup.and.saucer.fill"
        case .taskDone:     return "checkmark.circle.fill"
        }
    }

    /// The announcement a timer phase flip earns, if any. `nil` when the
    /// phases match (no flip) or the flip isn't into or out of a break — e.g.
    /// `.focus` to `.paused`. Pure so it can be tested without a running
    /// timer; the manager's job is just to call this on every phase change it
    /// observes and feed the result to `announce(_:)`.
    public static func forPhaseTransition(from: PomodoroPhase,
                                          to: PomodoroPhase) -> NotchActivity? {
        guard from != to else { return nil }
        if to.isBreak { return .breakStarted }
        if from.isBreak { return .sessionDone }
        return nil
    }
}

/// Inputs in, one shape out. Every rule about what the island shows lives here
/// so it can be tested without a window: the manager only feeds it events.
public struct NotchHUDState: Equatable, Sendable {
    /// User setting: the HUD is installed at all.
    public var enabled: Bool = true
    /// User setting: transient announcements are allowed.
    public var liveActivityEnabled: Bool = true
    /// Pointer is inside the island (after the open/close debounce).
    public var hovering: Bool = false
    /// A session is running, or paused part-way through one.
    public var engaged: Bool = false
    /// The full-screen break overlay is up — the HUD would be drawing on top
    /// of it, so it stands down.
    public var breakOverlayUp: Bool = false
    /// The announcement currently being made, if any.
    public var activity: NotchActivity? = nil

    public init() {}

    public var size: NotchHUDSize {
        guard enabled, !breakOverlayUp else { return .hidden }
        if hovering { return .expanded }
        if activity != nil, liveActivityEnabled { return .activity }
        if engaged { return .live }
        return .idle
    }
}
