import Foundation
import Combine

/// A reusable task blueprint: a named `TaskItem` shape (title, subtasks,
/// category, tags, estimates, …) with every bit of progress and schedule
/// state stripped — a template describes what a task looks like, not where
/// one particular run of it got to.
public struct TaskTemplate: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var item: TaskItem

    public init(id: UUID = UUID(), name: String, item: TaskItem) {
        self.id = id
        self.name = name
        self.item = item
    }
}

/// Persists reusable task templates to the same SQLite database TaskStore
/// uses (a separate `templates` table). Opens its own `TaskDatabase` handle
/// on that path — WAL mode plus the busy timeout make the shared file safe.
///
/// `instantiate` mints a ready-to-insert `TaskItem` (fresh ids, current
/// creation date); the caller hands it to `TaskStore.insert` to place it in
/// the list.
@MainActor
public final class TemplateStore: ObservableObject {
    /// App-wide instance (mirrors `TaskStore.shared`); tests build their own.
    public static let shared = TemplateStore()

    @Published public private(set) var templates: [TaskTemplate] = []

    private let database: TaskDatabase?

    /// `fileURL`, when given (tests), is the SQLite database path. In the app
    /// it defaults to `Application Support/Blink/blink.sqlite` — the same
    /// database TaskStore uses.
    public init(fileURL: URL? = nil) {
        let dbURL: URL
        if let fileURL {
            dbURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let dir = base.appendingPathComponent("Blink", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir,
                                                     withIntermediateDirectories: true)
            dbURL = dir.appendingPathComponent("blink.sqlite")
        }
        self.database = TaskDatabase(path: dbURL.path)
        templates = database?.loadTemplates() ?? []
    }

    /// Saves a task's shape as a named template. All state is stripped —
    /// done flags, pomodoro counts, completion stamp, due/planned dates, and
    /// subtask progress — while structure (subtasks, estimates, category,
    /// tags, project, priority, notes, recurrence) is kept.
    public func saveTemplate(from task: TaskItem, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var item = task
        item.isDone = false
        item.pomodorosDone = 0
        item.completedAt = nil
        item.dueDate = nil
        item.plannedDate = nil
        for k in item.subtasks.indices {
            item.subtasks[k].isDone = false
            item.subtasks[k].pomodorosDone = 0
        }
        templates.append(TaskTemplate(name: trimmed, item: item))
        persist()
    }

    /// Renames a template. No-op for unknown ids or empty names.
    public func rename(_ id: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let i = templates.firstIndex(where: { $0.id == id }) else { return }
        templates[i].name = trimmed
        persist()
    }

    public func delete(_ id: UUID) {
        templates.removeAll { $0.id == id }
        persist()
    }

    /// A ready-to-insert task from a template: fresh ids for the task and
    /// every subtask (each call mints new ones) and `createdAt` set to now.
    /// The caller inserts it via `TaskStore.insert`, which assigns the sort
    /// order and persists.
    public func instantiate(_ id: UUID) -> TaskItem? {
        guard let template = templates.first(where: { $0.id == id }) else { return nil }
        var task = template.item
        task.id = UUID()
        task.createdAt = Date()
        for k in task.subtasks.indices {
            task.subtasks[k].id = UUID()
        }
        return task
    }

    // MARK: - Persistence

    private func persist() {
        database?.saveTemplates(templates)
    }
}
