import Foundation

/// The Floating widget's pomodoro dot row — pure decision logic extracted
/// (like `FloatingWidgetStartAction`) so it is unit-testable without a live
/// `PomodoroTimer`/`TaskStore`.
///
/// Which count the dots show, in priority order:
/// 1. The active task's estimate (`effectiveEstimate`) when it has one —
///    filled dots are that task's `pomodorosDone`.
/// 2. The user's finite repeat selection (Repeat ×N) — filled dots are the
///    sessions already completed in the run (`repeatIndex`).
/// 3. Neither → the classic 3-pomodoro default, filled by the focus sessions
///    completed since the last reset (`cyclesCompletedInRound`).
public struct FloatingWidgetPomodoroDots: Equatable, Sendable {
    /// Dots shown when neither the task nor repeat pins a count.
    public static let defaultCount = 3
    /// Display cap so a 20-pomodoro estimate can't stretch the pill.
    public static let maxDots = 8

    public let total: Int
    public let filled: Int

    public static func plan(taskEstimate: Int?, taskDone: Int,
                            repeatEnabled: Bool, repeatEndless: Bool,
                            repeatCount: Int, sessionsDone: Int)
        -> FloatingWidgetPomodoroDots
    {
        let total: Int
        let done: Int
        if let est = taskEstimate {
            total = est
            done = taskDone
        } else if repeatEnabled && !repeatEndless {
            total = repeatCount
            done = sessionsDone
        } else {
            total = defaultCount
            done = sessionsDone
        }
        let clampedTotal = min(max(1, total), maxDots)
        return .init(total: clampedTotal,
                     filled: min(max(0, done), clampedTotal))
    }

    init(total: Int, filled: Int) {
        self.total = total
        self.filled = filled
    }
}
