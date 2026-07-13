import Foundation

/// What the expanded island lists — the user's *real* open work, in four tiers,
/// deduped and capped:
///
///   1. the **active task** (`TaskStore.activeTaskID`), always first when set;
///   2. the **focus queue**, in queue order (`FocusQueue.taskIDs`);
///   3. **today's** tasks (the `.today` filter — planned/due/overdue);
///   4. a **fallback** to the rest of the open tasks, in the order the caller
///      hands them (most-recently-relevant first), so the island is never empty
///      while the user has open work.
///
/// Pure, so the ordering is tested without a view. The active id and the queue
/// address tasks by id: an id that resolves to no task in `today`/`fallback` (a
/// task queued for tomorrow, deleted, or completed since) is skipped rather than
/// faulted on. A task shown by an earlier tier is never repeated by a later one,
/// and the cap applies to the merged list, not to any source separately.
///
/// The `.today` filter means *planned today, due today, or overdue* — a task
/// with no date is invisible to it. Tier 4 is what makes an all-undated task
/// list still fill the island: `fallback` is the open (not-done) tasks, and
/// whatever the earlier tiers didn't already claim flows in behind them.
public enum NotchTaskRows {
    /// The island is small: five rows is what fits under the timer row without
    /// the panel needing to scroll.
    public static let defaultLimit = 5

    /// - Parameters:
    ///   - today:    today's tasks (tier 3), in their own list order.
    ///   - queue:    focus-queue ids (tier 2), in queue order.
    ///   - active:   the active task id (tier 1), leads when it resolves.
    ///   - fallback: the rest of the open tasks (tier 4), most-relevant first.
    ///               Also the pool (with `today`) that `active`/`queue` ids
    ///               resolve against, so an open task named by either shows even
    ///               when it is neither queued nor on today's list.
    ///   - limit:    caps the merged, deduped list.
    public static func rows(today: [TaskItem],
                            queue: [UUID],
                            active: UUID? = nil,
                            fallback: [TaskItem] = [],
                            limit: Int = defaultLimit) -> [TaskItem] {
        guard limit > 0 else { return [] }

        // The id-addressed tiers (active, queue) resolve against every item we
        // were handed. `today` is a subset of the open tasks, so writing it last
        // lets today's instance win a tie — immaterial for value-equal structs,
        // but keeps the resolved item deterministic.
        var byID: [UUID: TaskItem] = [:]
        for task in fallback { byID[task.id] = task }
        for task in today { byID[task.id] = task }

        var seen = Set<UUID>()
        var out: [TaskItem] = []

        func take(_ task: TaskItem) {
            guard seen.insert(task.id).inserted else { return }
            out.append(task)
        }

        // 1. the active task, always first when it resolves.
        if let active, let task = byID[active] { take(task) }
        // 2. the focus queue, in order.
        for id in queue {
            guard let task = byID[id] else { continue }
            take(task)
        }
        // 3. today's tasks, in their own order.
        for task in today { take(task) }
        // 4. the rest of the open tasks, in the order the caller ranked them.
        for task in fallback { take(task) }

        return Array(out.prefix(limit))
    }
}
