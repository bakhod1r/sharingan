import Foundation

/// A transient announcement the island makes on its own, then collapses.
///
/// `Hashable` so the island can use the announcement itself as the view's
/// identity: one announcement replacing another mid-flight is a *new* thing
/// arriving, not the old one's text changing, and the motion has to say so.
public enum NotchActivity: Hashable, Sendable {
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

    /// The announcement a *live phase flip* earns, if any — the rule behind the
    /// manager's `timer.$phase` sink.
    ///
    /// Only arriving in a break qualifies. The sink sees every write to `phase`,
    /// including the ones that are not phase changes at all: `pause()` writes
    /// `.paused` and resuming writes the real phase back, so `.shortBreak →
    /// .paused` and `.paused → .shortBreak` are one break, not two events —
    /// anything touching `.paused` is silent. And *leaving* a break says nothing
    /// about a break having finished: `stop()` (the Reset button, and every task
    /// row's play button, which calls it internally) also jumps straight to
    /// `.focus`. Real completions come from `.phaseDidComplete` instead — see
    /// `forCompletedPhase(_:)`.
    ///
    /// Pure, so it is tested without a running timer.
    public static func forPhaseChange(from: PomodoroPhase,
                                      to: PomodoroPhase) -> NotchActivity? {
        guard from != to else { return nil }
        // A pause or a resume is not a phase change worth announcing.
        guard from != .paused, to != .paused else { return nil }
        return to.isBreak ? .breakStarted : nil
    }

    /// The announcement a phase that *actually ran to zero* earns — the rule
    /// behind the manager's `.phaseDidComplete` sink. `PomodoroTimer` posts that
    /// notification from `phaseComplete()` only; `pause()`, `stop()` and `skip()`
    /// never do, which is exactly why the completed-phase signal, and not the
    /// phase sink, is what may claim something finished.
    ///
    /// A finished break is the end of the whole focus → break cycle: the island
    /// says "Session complete" as focus comes back. A finished *focus* phase is
    /// not announced here — the break it rolls into announces itself one beat
    /// later via `forPhaseChange`, and two announcements would only fight over
    /// the island's single 2-second slot.
    public static func forCompletedPhase(_ phase: PomodoroPhase) -> NotchActivity? {
        phase.isBreak ? .sessionDone : nil
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

    /// Forget the pointer and the announcement — everything that is true only
    /// *while the island is on screen*.
    ///
    /// **Every suspension of the HUD has to call this, or the island comes back
    /// expanded over a menu bar the pointer left long ago.** `hovering` and
    /// `activity` are set by events the island itself receives; while it is
    /// hidden it receives none, so whatever was true at the moment it went away
    /// stays true. Hide it mid-hover — the HUD switched off, or a break overlay
    /// (a `.screenSaver`-level window) drawn over the notch, which can swallow
    /// the `mouseExited` that would have closed it — and `hovering` is still
    /// set when it returns: `size` reads `.expanded`, the panel's ~340×290
    /// hit-test mask goes live over the menu bar, and nothing takes it back
    /// down, because the only thing that would (`mouseMoved`) fires when the
    /// pointer moves *inside* the island. A menu bar that silently eats clicks.
    ///
    /// `engaged` is deliberately kept: a session that was running is still
    /// running, and the timer re-publishes it anyway.
    public mutating func clearTransientInteraction() {
        hovering = false
        activity = nil
    }
}
