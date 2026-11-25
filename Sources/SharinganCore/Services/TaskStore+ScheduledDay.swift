import Foundation

/// The week boards' single placement rule. A task's scheduled day is
/// `plannedDate ?? dueDate`: plannedDate is the app-wide planning concept,
/// dueDate is the fallback so tasks placed by deadline stay visible.
public extension TaskStore {
    /// Open tasks whose scheduled day is `day`, in list order.
    func tasksScheduled(on day: Date) -> [TaskItem] {
        let cal = Calendar.current
        return tasks
            .filter { t in
                guard t.trashedAt == nil, !t.isDone,
                      let scheduled = t.plannedDate ?? t.dueDate else { return false }
                return cal.isDate(scheduled, inSameDayAs: day)
            }
            .sorted(by: Self.inListOrder)
    }

    /// Open tasks with neither a planned day nor a due date.
    var boardBacklogTasks: [TaskItem] {
        tasks.filter { $0.trashedAt == nil && !$0.isDone
            && $0.plannedDate == nil && $0.dueDate == nil }
            .sorted(by: Self.inListOrder)
    }

    /// Puts a task on `day`. The deadline (dueDate) is left untouched.
    func schedule(_ id: UUID, on day: Date) {
        setPlannedDate(id, day)
    }

    /// Takes a task off the board: clears plannedDate; when it was on the
    /// board only through its dueDate, clears that instead.
    func unschedule(_ id: UUID) {
        guard let t = tasks.first(where: { $0.id == id }) else { return }
        if t.plannedDate != nil {
            setPlannedDate(id, nil)
        } else if t.dueDate != nil {
            clearDueDate(id)
        }
    }
}
