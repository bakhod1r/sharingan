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
    /// User-created categories, persisted alongside (and merged after) the presets.
    @Published public private(set) var customCategories: [TaskCategory] = []

    private let fileURL: URL
    private let categoriesURL: URL

    public init(fileURL: URL? = nil) {
        let resolved: URL
        if let fileURL {
            resolved = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let dir = base.appendingPathComponent("Blink", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir,
                                                     withIntermediateDirectories: true)
            resolved = dir.appendingPathComponent("tasks.json")
        }
        self.fileURL = resolved
        self.categoriesURL = resolved.deletingLastPathComponent()
            .appendingPathComponent("categories.json")
        load()
        loadCategories()
    }

    // MARK: - Categories

    /// Presets, with any custom entry of the same name overriding the preset
    /// (so a preset's color/icon can be customized), plus genuinely new ones.
    public var allCategories: [TaskCategory] {
        var result = TaskCategory.presets
        for custom in customCategories {
            if let i = result.firstIndex(where: { $0.name == custom.name }) {
                result[i] = custom
            } else {
                result.append(custom)
            }
        }
        return result
    }

    /// Hex color for a category name, consulting custom categories then presets.
    public func color(for name: String) -> String {
        allCategories.first { $0.name == name }?.colorHex ?? "#9AA3AF"
    }

    /// SF Symbol for a category name.
    public func icon(for name: String) -> String {
        allCategories.first { $0.name == name }?.icon ?? "folder.fill"
    }

    /// Adds or updates a category (color and/or icon). Works for presets too —
    /// the override is stored as a custom entry. Returns the resolved name.
    @discardableResult
    public func addCategory(name: String, colorHex: String, icon: String = "folder.fill") -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let i = customCategories.firstIndex(where: { $0.name == trimmed }) {
            customCategories[i].colorHex = colorHex
            customCategories[i].icon = icon
        } else {
            customCategories.append(.init(name: trimmed, colorHex: colorHex, icon: icon))
        }
        persistCategories()
        return trimmed
    }

    /// Changes only the color of a category, preserving its icon.
    public func setColor(for name: String, colorHex: String) {
        addCategory(name: name, colorHex: colorHex, icon: icon(for: name))
    }

    /// Changes only the icon of a category, preserving its color.
    public func setIcon(for name: String, icon: String) {
        addCategory(name: name, colorHex: color(for: name), icon: icon)
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

    private func loadCategories() {
        guard let data = try? Data(contentsOf: categoriesURL),
              let decoded = try? JSONDecoder().decode([TaskCategory].self, from: data) else {
            return
        }
        customCategories = decoded
    }

    private func persistCategories() {
        guard let data = try? JSONEncoder().encode(customCategories) else { return }
        try? data.write(to: categoriesURL, options: .atomic)
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
