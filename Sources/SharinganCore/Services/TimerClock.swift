import Foundation
import Combine

/// The ticking half of `PomodoroTimer`: the countdown values that change
/// once a second for the whole session. Split out so only views that show
/// the time observe it — anything observing `PomodoroTimer` itself (task
/// list, settings, menu bar popover, main window chrome) re-renders on real
/// state changes (phase, running, settings…) instead of every second. A
/// full main-window rebuild per tick cost ~20–30% CPU with a long task list.
@MainActor
public final class TimerClock: ObservableObject {
    @Published public internal(set) var remainingSeconds: TimeInterval = 0
    @Published public internal(set) var elapsedSeconds: TimeInterval = 0

    nonisolated public init() {}
}
