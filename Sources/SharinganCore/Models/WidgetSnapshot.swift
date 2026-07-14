import Foundation

/// Everything the WidgetKit extension can show, frozen into one small value.
///
/// The widget runs in its own process and can't observe `PomodoroTimer`; the
/// app writes this snapshot (see `WidgetSnapshotPublisher`) on every state
/// change and the widget's timeline provider reads it back. Live countdown
/// comes from `Text(timerInterval:)` on `endDate`, so a running session needs
/// no rewrites while it ticks.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// `PomodoroPhase` plus `idle` — the widget's "fresh timer, nothing
    /// engaged" state, which the engine expresses as (not running, remaining
    /// == total) rather than as a phase of its own.
    public enum Phase: String, Codable, Sendable {
        case focus, shortBreak, longBreak, paused, idle

        public var label: String {
            switch self {
            case .focus:      return "Focus"
            case .shortBreak: return "Break"
            case .longBreak:  return "Long break"
            case .paused:     return "Paused"
            case .idle:       return "Ready"
            }
        }
    }

    /// Bumped on breaking shape changes; the widget ignores newer schemas
    /// rather than misrendering them.
    public var schemaVersion: Int
    public var phase: Phase
    public var isRunning: Bool
    /// Countdown target while running; nil when paused or idle.
    public var endDate: Date?
    /// Static remaining seconds for the paused/idle rendering (and the
    /// fallback if `endDate` is missing).
    public var remainingSeconds: TimeInterval
    public var totalSeconds: TimeInterval
    public var taskTitle: String?
    public var todayPomodoros: Int
    /// 0 = no daily goal configured.
    public var dailyGoal: Int
    public var streakDays: Int
    public var updatedAt: Date

    public static let currentSchemaVersion = 1

    public init(phase: Phase,
                isRunning: Bool,
                endDate: Date? = nil,
                remainingSeconds: TimeInterval,
                totalSeconds: TimeInterval,
                taskTitle: String? = nil,
                todayPomodoros: Int = 0,
                dailyGoal: Int = 0,
                streakDays: Int = 0,
                updatedAt: Date) {
        self.schemaVersion = Self.currentSchemaVersion
        self.phase = phase
        self.isRunning = isRunning
        self.endDate = endDate
        self.remainingSeconds = remainingSeconds
        self.totalSeconds = totalSeconds
        self.taskTitle = taskTitle
        self.todayPomodoros = todayPomodoros
        self.dailyGoal = dailyGoal
        self.streakDays = streakDays
        self.updatedAt = updatedAt
    }

    // MARK: - Reading-side repair

    /// What the widget should actually render at `now`. A snapshot outlives
    /// the app that wrote it, so two things can rot: a "running" session whose
    /// end has passed (app force-quit mid-pomodoro) renders as idle, and a
    /// today-count written on a previous day renders as 0.
    public func normalized(now: Date = Date(),
                           calendar: Calendar = .current) -> WidgetSnapshot {
        var s = self
        if s.isRunning, (s.endDate ?? .distantPast) <= now { s = s.idled() }
        if !calendar.isDate(s.updatedAt, inSameDayAs: now) { s.todayPomodoros = 0 }
        return s
    }

    /// The same stats with the timer put back to a fresh, not-running state.
    public func idled() -> WidgetSnapshot {
        var s = self
        s.phase = .idle
        s.isRunning = false
        s.endDate = nil
        s.remainingSeconds = s.totalSeconds
        return s
    }

    /// Ring fill at `date` — live for a running session, static otherwise.
    public func progress(at date: Date) -> Double {
        guard totalSeconds > 0 else { return 0 }
        let remaining: TimeInterval
        if isRunning, let end = endDate {
            remaining = max(0, end.timeIntervalSince(date))
        } else {
            remaining = max(0, remainingSeconds)
        }
        return min(1, max(0, 1 - remaining / totalSeconds))
    }

    // MARK: - Canned states

    /// Rendered when no snapshot exists yet (app never launched since install).
    public static func empty(now: Date = Date()) -> WidgetSnapshot {
        WidgetSnapshot(phase: .idle, isRunning: false,
                       remainingSeconds: 25 * 60, totalSeconds: 25 * 60,
                       updatedAt: now)
    }

    /// Gallery/placeholder preview — a lively mid-session state.
    public static func sample(now: Date = Date()) -> WidgetSnapshot {
        WidgetSnapshot(phase: .focus, isRunning: true,
                       endDate: now.addingTimeInterval(24 * 60 + 37),
                       remainingSeconds: 24 * 60 + 37, totalSeconds: 25 * 60,
                       taskTitle: "Design review",
                       todayPomodoros: 4, dailyGoal: 8, streakDays: 12,
                       updatedAt: now)
    }
}
