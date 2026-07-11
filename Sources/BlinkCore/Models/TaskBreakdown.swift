import Foundation

/// Pure aggregation of focus pomodoros credited to tasks, grouped by project
/// or tag — powers the "By project" / "By tags" stats cards.
///
/// Attribution mirrors the "By category" card: all-time `task.pomodorosDone`
/// (there is no per-day project/tag history), tasks with zero pomodoros are
/// ignored, results are sorted by count descending with alphabetical ties.
public enum TaskBreakdown {

    /// Bucket label for tasks without a project.
    public static let noProjectLabel = "No project"

    /// Pomodoros grouped by project. Tasks with a nil/blank project fall into
    /// the "No project" bucket.
    public static func pomodoros(byProject tasks: [TaskItem]) -> [(name: String, count: Int)] {
        var freq: [String: Int] = [:]
        for t in tasks where t.pomodorosDone > 0 {
            let name = t.project?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            freq[name.isEmpty ? noProjectLabel : name, default: 0] += t.pomodorosDone
        }
        return sorted(freq)
    }

    /// Pomodoros grouped by tag. A tag is counted once per task (duplicate
    /// tags on one task don't double-credit); untagged tasks contribute
    /// nothing.
    public static func pomodoros(byTag tasks: [TaskItem]) -> [(name: String, count: Int)] {
        var freq: [String: Int] = [:]
        for t in tasks where t.pomodorosDone > 0 {
            for tag in Set(t.tags) where !tag.isEmpty {
                freq[tag, default: 0] += t.pomodorosDone
            }
        }
        return sorted(freq)
    }

    /// Count descending, ties alphabetical — stable, deterministic order.
    private static func sorted(_ freq: [String: Int]) -> [(name: String, count: Int)] {
        freq.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { (name: $0.key, count: $0.value) }
    }
}
