import Foundation

/// What tapping ▶︎ on the Dock widget should do — pure decision logic
/// extracted (like `DockWidgetGeometry`) so it is unit-testable without a
/// live `PomodoroTimer`/`TaskStore`.
///
/// Starting must never be blocked by the mini task picker: a paused session
/// always resumes in place rather than re-routing through task selection,
/// and an empty today list starts immediately too, since a picker with
/// nothing to choose from is just a dialog in the way.
public enum DockWidgetStartAction: Equatable, Sendable {
    /// Resume the paused session, or start fresh with today empty — either
    /// way `startFocusSession()` (no kind override, active task untouched).
    case startImmediately
    /// Show the mini picker of today's open tasks; the user's choice (or its
    /// "Start without task" row) decides how `startFocusSession` is called.
    case showPicker

    public static func decide(isPaused: Bool, todayTaskCount: Int) -> DockWidgetStartAction {
        guard !isPaused else { return .startImmediately }
        return todayTaskCount > 0 ? .showPicker : .startImmediately
    }
}
