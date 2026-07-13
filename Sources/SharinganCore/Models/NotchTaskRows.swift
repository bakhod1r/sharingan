import Foundation

/// What the expanded island lists: whatever the user queued for focus, in queue
/// order, then the rest of today's tasks in their own order. Pure, so the
/// ordering is tested without a view.
///
/// The queue may name ids that are not in today's set (a task queued for
/// tomorrow, or one deleted since) — those are skipped rather than faulted on,
/// and the cap applies to the merged list, not to either source separately.
public enum NotchTaskRows {
    /// The island is small: five rows is what fits under the timer row without
    /// the panel needing to scroll.
    public static let defaultLimit = 5

    public static func rows(today: [TaskItem], queue: [UUID],
                            limit: Int = defaultLimit) -> [TaskItem] {
        guard limit > 0 else { return [] }
        let byID = Dictionary(today.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<UUID>()
        var out: [TaskItem] = []

        for id in queue {
            guard let task = byID[id], seen.insert(id).inserted else { continue }
            out.append(task)
        }
        for task in today where seen.insert(task.id).inserted {
            out.append(task)
        }
        return Array(out.prefix(limit))
    }
}
