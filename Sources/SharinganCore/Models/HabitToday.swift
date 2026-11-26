import Foundation

/// One habit due (or done) today, ready for a compact UI strip.
public struct HabitTodayItem: Equatable, Sendable, Identifiable {
    public var id: UUID { taskID }
    public let taskID: UUID
    public let title: String
    public let isManual: Bool
    public let progress: Double
    public let isDone: Bool
    /// A manual check exists today (any mode).
    public let isChecked: Bool
    public let pomodoroCount: Int
    public let pomodoroTarget: Int?
}

extension HabitEngine {
    /// Habits done or still pending today, in input order.
    public static func todayItems(habits: [HabitInput], focusLog: [FocusLogEntry], checks: [HabitCheck],
                                  today: Date, calendar: Calendar) -> [HabitTodayItem] {
        let t = calendar.startOfDay(for: today)
        return habits.compactMap { h in
            let s = status(for: t, habit: h.habit, taskID: h.taskID, focusLog: focusLog, checks: checks,
                           today: t, calendar: calendar)
            switch s {
            case .done: break
            case .pending:
                guard isPendingToday(habit: h.habit, taskID: h.taskID, focusLog: focusLog,
                                     checks: checks, today: t, calendar: calendar) else { return nil }
            default: return nil
            }
            var target: Int?
            if case .pomodoro(let n) = h.habit.mode { target = n }
            return HabitTodayItem(
                taskID: h.taskID, title: h.title, isManual: target == nil,
                progress: progress(on: t, habit: h.habit, taskID: h.taskID, focusLog: focusLog,
                                   checks: checks, calendar: calendar),
                isDone: s == .done,
                isChecked: checks.contains { $0.taskID == h.taskID && calendar.startOfDay(for: $0.day) == t },
                pomodoroCount: target == nil ? 0 : pomodoroCount(taskID: h.taskID, on: t, focusLog: focusLog, calendar: calendar),
                pomodoroTarget: target)
        }
    }
}
