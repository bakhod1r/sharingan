import Foundation

/// One habit due (or done) today, ready for a compact UI strip.
public struct HabitTodayItem: Equatable, Sendable, Identifiable {
    public var id: UUID { taskID }
    public let taskID: UUID
    public let title: String
    /// The user may tick today by hand (manual / both).
    public let allowsCheck: Bool
    public let progress: Double
    public let isDone: Bool
    /// A manual check row exists today (it only counts when `allowsCheck`).
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
            let target = h.habit.mode.pomodoroTarget
            return HabitTodayItem(
                taskID: h.taskID, title: h.title, allowsCheck: h.habit.mode.allowsManualCheck,
                progress: progress(on: t, habit: h.habit, taskID: h.taskID, focusLog: focusLog,
                                   checks: checks, calendar: calendar),
                isDone: s == .done,
                isChecked: checks.contains { $0.taskID == h.taskID && calendar.startOfDay(for: $0.day) == t },
                pomodoroCount: target == nil ? 0 : pomodoroCount(taskID: h.taskID, on: t, focusLog: focusLog, calendar: calendar),
                pomodoroTarget: target)
        }
    }
}
