import Foundation

public extension TaskStore {
    /// Quick-add through the natural-language parser (title, tags, due date,
    /// estimate, recurrence, project, priority) — same behaviour as the menu
    /// bar popover. Returns false when nothing was added.
    @discardableResult
    func addParsed(_ raw: String, now: Date = Date()) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        let parsed = TaskInputParser.parse(t, now: now)
        let title = parsed.title.isEmpty ? t : parsed.title
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        add(title: title, tags: parsed.tags, dueDate: parsed.dueDate,
            estimatedPomodoros: parsed.estimatedPomodoros, recurrence: parsed.recurrence,
            project: parsed.project, priority: parsed.priority)
        return true
    }
}
