import Foundation
import Combine

/// Persists the user's task list to a JSON file in Application Support and
/// tracks which task the active focus session is running against.
///
/// (SQLite would be overkill at this scale; a Codable JSON store keeps it simple,
/// dependency-free, and easy to test.)
@MainActor
public final class TaskStore: ObservableObject {
    public static let shared = TaskStore()

    @Published public private(set) var tasks: [TaskItem] = []
    @Published public var activeTaskID: UUID?

    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let dir = base.appendingPathComponent("Blink", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir,
                                                     withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("tasks.json")
        }
        load()
    }

    // MARK: - Derived

    public var activeTask: TaskItem? {
        guard let id = activeTaskID else { return nil }
        return tasks.first { $0.id == id }
    }

    /// Tasks grouped by category, in preset order (custom categories last).
    public func grouped() -> [(category: String, items: [TaskItem])] {
        let order = TaskCategory.presets.map(\.name)
        let names = Array(Set(tasks.map(\.category)))
            .sorted { (order.firstIndex(of: $0) ?? .max, $0) < (order.firstIndex(of: $1) ?? .max, $1) }
        return names.map { name in
            (name, tasks.filter { $0.category == name }
                .sorted { !$0.isDone && $1.isDone })
        }
    }

    // MARK: - Mutations

    public func add(title: String,
                    category: String = TaskCategory.presets[0].name,
                    tags: [String] = [],
                    dueDate: Date? = nil) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let task = TaskItem(title: trimmed, category: category, tags: tags, dueDate: dueDate)
        tasks.append(task)
        scheduleDueNotification(task)
        persist()
    }

    public func toggleDone(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].isDone.toggle()
        if tasks[i].isDone { NotificationService.shared.cancel(identifier: dueNoteID(id)) }
        persist()
    }

    public func delete(_ id: UUID) {
        NotificationService.shared.cancel(identifier: dueNoteID(id))
        tasks.removeAll { $0.id == id }
        if activeTaskID == id { activeTaskID = nil }
        persist()
    }

    public func update(_ item: TaskItem) {
        guard let i = tasks.firstIndex(where: { $0.id == item.id }) else { return }
        tasks[i] = item
        persist()
    }

    /// Records one completed pomodoro against the given task.
    public func incrementPomodoro(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].pomodorosDone += 1
        persist()
    }

    public func setActive(_ id: UUID?) {
        activeTaskID = id
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([TaskItem].self, from: data) else {
            return
        }
        tasks = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Deadlines

    private func dueNoteID(_ id: UUID) -> String { "blink.task.due.\(id.uuidString)" }

    private func scheduleDueNotification(_ task: TaskItem) {
        guard let due = task.dueDate, !task.isDone else { return }
        NotificationService.shared.schedule(
            title: "Task due",
            body: task.title,
            identifier: dueNoteID(task.id),
            at: due)
    }

    // MARK: - Export

    /// The full task list as CSV (title, category, tags, status, pomodoros, due, created).
    public func csv() -> String {
        func esc(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let iso = ISO8601DateFormatter()
        var rows = ["title,category,tags,done,pomodoros,due,created"]
        for t in tasks {
            rows.append([
                esc(t.title),
                esc(t.category),
                esc(t.tags.joined(separator: " ")),
                t.isDone ? "yes" : "no",
                String(t.pomodorosDone),
                t.dueDate.map { iso.string(from: $0) } ?? "",
                iso.string(from: t.createdAt),
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }
}
