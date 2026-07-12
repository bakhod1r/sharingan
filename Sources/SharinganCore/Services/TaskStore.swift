import Foundation
import Combine

/// A smart view over the task list — the top-level filter in the Tasks screen.
public enum TaskFilter: String, CaseIterable, Identifiable, Sendable {
    case today, upcoming, all, completed
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .today:     return "Today"
        case .upcoming:  return "Upcoming"
        case .all:       return "All"
        case .completed: return "Done"
        }
    }
    public var icon: String {
        switch self {
        case .today:     return "sun.max"
        case .upcoming:  return "calendar"
        case .all:       return "tray.full"
        case .completed: return "checkmark.circle"
        }
    }
}

/// Persists the user's task list to a local SQLite database in Application
/// Support (via `TaskDatabase`) and tracks which task the active focus session
/// is running against.
///
/// The in-memory `@Published` model and the whole public API are storage-
/// agnostic: mutations funnel through `persist()` / `persistCategories()`, which
/// write the tables inside a transaction. A first launch with the old JSON files
/// present migrates them automatically (see `migrateLegacyJSONIfNeeded`).
@MainActor
public final class TaskStore: ObservableObject {
    public static let shared = TaskStore()

    @Published public private(set) var tasks: [TaskItem] = []
    @Published public var activeTaskID: UUID?
    /// Subtask of the active task the current focus session is aimed at.
    /// Transient session state, like `activeTaskID` — never persisted.
    @Published public var activeSubtaskID: UUID?
    /// User-created categories, persisted alongside (and merged after) the presets.
    @Published public private(set) var customCategories: [TaskCategory] = []

    private let database: TaskDatabase?

    /// `fileURL`, when given (tests), is the SQLite database path. In the app it
    /// defaults to `Application Support/Blink/blink.sqlite`.
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
        load()
        loadCategories()
        migrateLegacyJSONIfNeeded(dbDir: dbURL.deletingLastPathComponent())
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

    /// True for user-created categories (presets can be recolored but not renamed
    /// or deleted).
    public func isCustomCategory(_ name: String) -> Bool {
        !TaskCategory.presets.contains { $0.name == name }
    }

    /// Renames a custom category and moves every task in it to the new name.
    /// No-op for presets, empty names, or collisions with an existing category.
    @discardableResult
    public func renameCategory(_ old: String, to newName: String) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isCustomCategory(old), !trimmed.isEmpty, trimmed != old,
              !allCategories.contains(where: { $0.name == trimmed }) else { return false }
        if let i = customCategories.firstIndex(where: { $0.name == old }) {
            customCategories[i].name = trimmed
        }
        for j in tasks.indices where tasks[j].category == old {
            tasks[j].category = trimmed
        }
        persistCategories()
        persist()
        return true
    }

    /// Deletes a custom category, reassigning its tasks to the first preset.
    /// No-op for presets.
    public func deleteCategory(_ name: String) {
        guard isCustomCategory(name) else { return }
        let fallback = TaskCategory.presets[0].name
        customCategories.removeAll { $0.name == name }
        for j in tasks.indices where tasks[j].category == name {
            tasks[j].category = fallback
        }
        persistCategories()
        persist()
    }

    // MARK: - Derived

    public var activeTask: TaskItem? {
        guard let id = activeTaskID else { return nil }
        return tasks.first { $0.id == id }
    }

    /// Canonical ordering: open tasks before done, then manual `sortOrder`, then
    /// creation time as a stable tiebreak.
    public static func inListOrder(_ a: TaskItem, _ b: TaskItem) -> Bool {
        if a.isDone != b.isDone { return !a.isDone }
        if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
        return a.createdAt < b.createdAt
    }

    /// Tasks grouped by category, in preset order (custom categories last).
    public func grouped() -> [(category: String, items: [TaskItem])] {
        let order = TaskCategory.presets.map(\.name)
        let names = Array(Set(tasks.map(\.category)))
            .sorted { (order.firstIndex(of: $0) ?? .max, $0) < (order.firstIndex(of: $1) ?? .max, $1) }
        return names.map { name in
            (name, tasks.filter { $0.category == name }.sorted(by: Self.inListOrder))
        }
    }

    /// Whether a task belongs in a given smart view.
    private func matches(_ task: TaskItem, _ filter: TaskFilter, now: Date = Date()) -> Bool {
        let cal = Calendar.current
        switch filter {
        case .all:
            return !task.isDone
        case .completed:
            return task.isDone
        case .today:
            guard !task.isDone else { return false }
            if task.isPlannedToday(now: now) { return true }
            if let due = task.dueDate { return cal.isDateInToday(due) || due < now }  // today or overdue
            return false
        case .upcoming:
            guard !task.isDone, let due = task.dueDate else { return false }
            return due >= now && !cal.isDateInToday(due)   // a future day
        }
    }

    /// Number of tasks in a smart view — powers the filter-bar counts.
    public func count(_ filter: TaskFilter) -> Int {
        tasks.filter { matches($0, filter) }.count
    }

    /// Tasks for a smart view, narrowed by a free-text query (title / tags /
    /// project / notes), grouped by category in the usual order.
    public func grouped(filter: TaskFilter, search: String = "") -> [(category: String, items: [TaskItem])] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = tasks.filter { task in
            guard matches(task, filter) else { return false }
            guard !q.isEmpty else { return true }
            return task.title.lowercased().contains(q)
                || task.tags.contains { $0.lowercased().contains(q) }
                || (task.project?.lowercased().contains(q) ?? false)
                || task.notes.lowercased().contains(q)
        }
        let order = TaskCategory.presets.map(\.name)
        let names = Array(Set(filtered.map(\.category)))
            .sorted { (order.firstIndex(of: $0) ?? .max, $0) < (order.firstIndex(of: $1) ?? .max, $1) }
        return names.map { name in
            (name, filtered.filter { $0.category == name }.sorted(by: Self.inListOrder))
        }
    }

    /// Deletes every completed task (the Done view's "Clear" action).
    public func clearCompleted() {
        for id in tasks.filter(\.isDone).map(\.id) {
            cancelDueNotifications(for: id)
            if activeTaskID == id { activeTaskID = nil; activeSubtaskID = nil }
        }
        tasks.removeAll(where: \.isDone)
        persist()
    }

    // MARK: - Mutations

    public func add(title: String,
                    category: String = TaskCategory.presets[0].name,
                    tags: [String] = [],
                    dueDate: Date? = nil,
                    estimatedPomodoros: Int? = nil,
                    recurrence: Recurrence = .none,
                    project: String? = nil,
                    notes: String = "",
                    priority: TaskPriority = .none) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // New tasks go to the bottom of the manual order.
        let nextOrder = (tasks.map(\.sortOrder).max() ?? 0) + 1
        let cleanProject = project?.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = TaskItem(title: trimmed, category: category, tags: tags, dueDate: dueDate,
                            sortOrder: nextOrder, estimatedPomodoros: estimatedPomodoros,
                            notes: notes, recurrence: recurrence,
                            project: (cleanProject?.isEmpty ?? true) ? nil : cleanProject,
                            priority: priority)
        tasks.append(task)
        syncDueNotifications(for: task)
        persist()
    }

    /// Inserts a fully-formed task (e.g. one instantiated from a template) at
    /// the bottom of the manual order, schedules its deadline reminders, and
    /// persists. The caller is responsible for ids/createdAt (see
    /// `TemplateStore.instantiate`).
    public func insert(_ task: TaskItem) {
        var task = task
        task.sortOrder = (tasks.map(\.sortOrder).max() ?? 0) + 1
        tasks.append(task)
        syncDueNotifications(for: task)
        persist()
    }

    /// Deep-copies a task: fresh ids for the task and every subtask, a
    /// " (copy)" title suffix, and all progress state reset (not done, zero
    /// pomodoros, no completion stamp) while metadata — category, tags,
    /// project, priority, due/planned dates, estimates, notes, recurrence —
    /// is kept. The copy slots directly after the original in the manual
    /// order. Returns the new task's id, or nil for an unknown id.
    @discardableResult
    public func duplicate(_ id: UUID) -> UUID? {
        guard let original = tasks.first(where: { $0.id == id }) else { return nil }
        var copy = original
        copy.id = UUID()
        copy.title = original.title + " (copy)"
        copy.isDone = false
        copy.pomodorosDone = 0
        copy.completedAt = nil
        copy.createdAt = Date()
        for k in copy.subtasks.indices {
            copy.subtasks[k].id = UUID()
            copy.subtasks[k].isDone = false
            copy.subtasks[k].pomodorosDone = 0   // keep estimates, reset progress
        }
        // Open a gap right after the original so the copy lands next to it.
        for i in tasks.indices where tasks[i].sortOrder > original.sortOrder {
            tasks[i].sortOrder += 1
        }
        copy.sortOrder = original.sortOrder + 1
        tasks.append(copy)
        syncDueNotifications(for: copy)
        persist()
        return copy.id
    }

    // MARK: - Planning

    /// Moves a task one place up or down within its own category (open tasks).
    public func move(_ id: UUID, up: Bool) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        let siblings = tasks
            .filter { $0.category == task.category && !$0.isDone }
            .sorted(by: Self.inListOrder)
        guard let idx = siblings.firstIndex(where: { $0.id == id }) else { return }
        let swapIdx = up ? idx - 1 : idx + 1
        guard swapIdx >= 0, swapIdx < siblings.count else { return }
        let other = siblings[swapIdx]
        guard let i = tasks.firstIndex(where: { $0.id == id }),
              let j = tasks.firstIndex(where: { $0.id == other.id }) else { return }
        let tmp = tasks[i].sortOrder
        tasks[i].sortOrder = tasks[j].sortOrder
        tasks[j].sortOrder = tmp
        persist()
    }

    /// Applies a drag reorder (`onMove`) within one category's open tasks.
    public func reorder(category: String, from source: IndexSet, to destination: Int) {
        var items = tasks
            .filter { $0.category == category && !$0.isDone }
            .sorted(by: Self.inListOrder)
        items.move(fromOffsets: source, toOffset: destination)
        // Reassign a compact, contiguous order block for this category.
        let base = items.map(\.sortOrder).min() ?? 0
        for (offset, item) in items.enumerated() {
            if let i = tasks.firstIndex(where: { $0.id == item.id }) {
                tasks[i].sortOrder = base + offset
            }
        }
        persist()
    }

    /// Drag reorder: places `id` immediately before `targetID` within their shared
    /// category's open tasks. No-op across categories or when ids match.
    public func moveTask(_ id: UUID, before targetID: UUID) {
        guard id != targetID,
              let moving = tasks.first(where: { $0.id == id }),
              let target = tasks.first(where: { $0.id == targetID }),
              moving.category == target.category, !moving.isDone, !target.isDone else { return }
        var items = tasks
            .filter { $0.category == moving.category && !$0.isDone }
            .sorted(by: Self.inListOrder)
        guard let from = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: from)
        guard let to = items.firstIndex(where: { $0.id == targetID }) else { return }
        items.insert(moving, at: to)
        let base = items.map(\.sortOrder).min() ?? 0
        for (offset, item) in items.enumerated() {
            if let i = tasks.firstIndex(where: { $0.id == item.id }) {
                tasks[i].sortOrder = base + offset
            }
        }
        persist()
    }

    public func setEstimate(_ id: UUID, _ pomodoros: Int?) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].estimatedPomodoros = pomodoros.map { max(1, $0) }
        persist()
    }

    /// Toggles whether a task is on today's plan.
    public func togglePlannedToday(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].plannedDate = tasks[i].isPlannedToday() ? nil : Calendar.current.startOfDay(for: Date())
        persist()
    }

    /// Sets (or clears, with nil) the day a task is planned for. Normalizes to
    /// start-of-day. Powers the weekly board's drag-to-reschedule.
    public func setPlannedDate(_ id: UUID, _ date: Date?) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].plannedDate = date.map { Calendar.current.startOfDay(for: $0) }
        persist()
    }

    /// Open tasks planned for the given day, in list order.
    public func tasksPlanned(on day: Date) -> [TaskItem] {
        let cal = Calendar.current
        return tasks
            .filter { !$0.isDone && ($0.plannedDate.map { cal.isDate($0, inSameDayAs: day) } ?? false) }
            .sorted(by: Self.inListOrder)
    }

    /// Open tasks with no planned day — the weekly board's backlog column.
    public var unscheduledTasks: [TaskItem] {
        tasks.filter { !$0.isDone && $0.plannedDate == nil }.sorted(by: Self.inListOrder)
    }

    public func toggleDone(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].isDone.toggle()
        if tasks[i].isDone {
            tasks[i].completedAt = Date()
            cancelDueNotifications(for: id)
            // A recurring task spawns its next occurrence when completed.
            if tasks[i].recurrence != .none {
                spawnNextOccurrence(of: tasks[i])
            }
        } else {
            tasks[i].completedAt = nil
            // Un-completing restores the deadline reminders that toggling done cancelled.
            syncDueNotifications(for: tasks[i])
        }
        persist()
    }

    /// Creates the next occurrence of a recurring task: a fresh copy (new id, not
    /// done, counters and subtasks reset) with its due date advanced.
    private func spawnNextOccurrence(of task: TaskItem) {
        var next = task
        next.id = UUID()
        next.isDone = false
        next.completedAt = nil
        next.pomodorosDone = 0
        next.createdAt = Date()
        next.plannedDate = nil
        next.sortOrder = (tasks.map(\.sortOrder).max() ?? 0) + 1
        for k in next.subtasks.indices {
            next.subtasks[k].isDone = false
            next.subtasks[k].pomodorosDone = 0   // keep estimates, reset progress
        }
        // Only carry a due date forward if the task had one. Advancing from the
        // later of the old due date and now keeps a long-overdue task's next
        // occurrence in the future instead of spawning another past copy. A task
        // with no deadline stays deadline-free (no surprise reminder gets scheduled).
        if let due = task.dueDate {
            next.dueDate = task.recurrence.nextDate(after: max(due, Date()))
        } else {
            next.dueDate = nil
        }
        tasks.append(next)
        syncDueNotifications(for: next)
    }

    // MARK: - Snooze / overdue

    /// Moves a task's due date to `newDay`'s day while keeping the original due
    /// time-of-day (09:00 when the task had no due date). A set `plannedDate`
    /// follows to the same day; a nil one stays nil. No-op on done tasks — they
    /// have nothing left to remind about. Reschedules notifications and persists.
    public func snooze(_ id: UUID, to newDay: Date) {
        guard let i = tasks.firstIndex(where: { $0.id == id }), !tasks[i].isDone else { return }
        let cal = Calendar.current
        let day = cal.startOfDay(for: newDay)
        var hour = 9, minute = 0
        if let due = tasks[i].dueDate {
            let time = cal.dateComponents([.hour, .minute], from: due)
            hour = time.hour ?? 9
            minute = time.minute ?? 0
        }
        tasks[i].dueDate = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        if tasks[i].plannedDate != nil {
            tasks[i].plannedDate = day
        }
        syncDueNotifications(for: tasks[i])
        persist()
    }

    /// Snoozes to the day after `now`.
    public func snoozeTomorrow(_ id: UUID, now: Date = Date()) {
        guard let day = Calendar.current.date(byAdding: .day, value: 1, to: now) else { return }
        snooze(id, to: day)
    }

    /// Snoozes to one week after `now`.
    public func snoozeNextWeek(_ id: UUID, now: Date = Date()) {
        guard let day = Calendar.current.date(byAdding: .day, value: 7, to: now) else { return }
        snooze(id, to: day)
    }

    /// Count of open tasks whose due date has passed — powers the overdue digest.
    public func overdueCount(now: Date = Date()) -> Int {
        tasks.filter { !$0.isDone && ($0.dueDate.map { $0 < now } ?? false) }.count
    }

    // MARK: - Subtasks / notes / recurrence / project

    public func addSubtask(_ taskID: UUID, title: String, estimate: Int? = nil) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let i = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[i].subtasks.append(Subtask(title: trimmed,
                                         estimatedPomodoros: estimate.map { max(1, $0) }))
        persist()
    }

    public func toggleSubtask(_ taskID: UUID, _ subID: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == taskID }),
              let j = tasks[i].subtasks.firstIndex(where: { $0.id == subID }) else { return }
        tasks[i].subtasks[j].isDone.toggle()
        // Completing the focus target ends its targeting (un-completing does not restore it).
        if tasks[i].subtasks[j].isDone && subID == activeSubtaskID { activeSubtaskID = nil }
        persist()
    }

    public func deleteSubtask(_ taskID: UUID, _ subID: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[i].subtasks.removeAll { $0.id == subID }
        if subID == activeSubtaskID { activeSubtaskID = nil }
        persist()
    }

    /// Applies a drag reorder (`onMove`) within one task's checklist.
    public func reorderSubtasks(_ taskID: UUID, from source: IndexSet, to destination: Int) {
        guard let i = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[i].subtasks.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    /// Lifts a checklist item out into a full task of its own: the new task
    /// takes the subtask's title, estimate, and pomodoro credit, inherits the
    /// parent's category, project, tags, and priority, and starts open (a
    /// promotion implies remaining work, even for a checked-off step). No
    /// dates, recurrence, notes, or subtasks carry over. The new task slots
    /// directly after its former parent in the manual order (same gap trick
    /// as `duplicate`). Returns the new task's id, or nil for unknown ids.
    @discardableResult
    public func promoteSubtask(_ taskID: UUID, _ subID: UUID) -> UUID? {
        guard let i = tasks.firstIndex(where: { $0.id == taskID }),
              let j = tasks[i].subtasks.firstIndex(where: { $0.id == subID }) else { return nil }
        let parent = tasks[i]
        let sub = parent.subtasks[j]
        // Open a gap right after the parent so the promoted task lands next to it.
        for k in tasks.indices where tasks[k].sortOrder > parent.sortOrder {
            tasks[k].sortOrder += 1
        }
        let promoted = TaskItem(title: sub.title,
                                category: parent.category,
                                tags: parent.tags,
                                pomodorosDone: sub.pomodorosDone,
                                sortOrder: parent.sortOrder + 1,
                                estimatedPomodoros: sub.estimatedPomodoros,
                                project: parent.project,
                                priority: parent.priority)
        tasks[i].subtasks.remove(at: j)
        tasks.append(promoted)
        if subID == activeSubtaskID { activeSubtaskID = nil }
        persist()
        return promoted.id
    }

    public func setNotes(_ id: UUID, _ notes: String) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].notes = notes
        persist()
    }

    public func setRecurrence(_ id: UUID, _ recurrence: Recurrence) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].recurrence = recurrence
        persist()
    }

    public func setPriority(_ id: UUID, _ priority: TaskPriority) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].priority = priority
        persist()
    }

    public func setProject(_ id: UUID, _ project: String?) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = project?.trimmingCharacters(in: .whitespacesAndNewlines)
        tasks[i].project = (trimmed?.isEmpty ?? true) ? nil : trimmed
        persist()
    }

    /// Distinct project names currently in use, sorted.
    public var projects: [String] {
        Array(Set(tasks.compactMap(\.project))).sorted()
    }

    /// Removes a tag from every task — the sidebar's "delete label". Tags have
    /// no standalone registry (they exist only on tasks), so this erases the
    /// label everywhere at once.
    public func removeTag(_ tag: String) {
        var touched = false
        for i in tasks.indices where tasks[i].tags.contains(tag) {
            tasks[i].tags.removeAll { $0 == tag }
            touched = true
        }
        if touched { persist() }
    }

    /// Distinct tags across all tasks, most-used first — powers tag suggestions.
    public var allTags: [String] {
        var freq: [String: Int] = [:]
        for t in tasks { for tag in t.tags { freq[tag, default: 0] += 1 } }
        return freq.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map(\.key)
    }

    public func delete(_ id: UUID) {
        cancelDueNotifications(for: id)
        tasks.removeAll { $0.id == id }
        if activeTaskID == id { activeTaskID = nil; activeSubtaskID = nil }
        persist()
    }

    public func update(_ item: TaskItem) {
        guard let i = tasks.firstIndex(where: { $0.id == item.id }) else { return }
        tasks[i] = item
        // An edit can remove or complete the focus-target subtask.
        if item.id == activeTaskID, let sid = activeSubtaskID,
           !item.subtasks.contains(where: { $0.id == sid && !$0.isDone }) {
            activeSubtaskID = nil
        }
        // Re-sync the deadline reminders: a due date added/changed via edit would
        // otherwise never fire (they were only scheduled at creation time).
        syncDueNotifications(for: item)
        persist()
    }

    /// Records one completed pomodoro against the given task. The task counter
    /// is the aggregate source of truth; the active subtask (if any, and still
    /// open) additionally receives an attribution credit.
    public func incrementPomodoro(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].pomodorosDone += 1
        if id == activeTaskID, let sid = activeSubtaskID {
            if let j = tasks[i].subtasks.firstIndex(where: { $0.id == sid && !$0.isDone }) {
                tasks[i].subtasks[j].pomodorosDone += 1
            } else {
                activeSubtaskID = nil   // stale: deleted or completed mid-session
            }
        }
        persist()
    }

    public func setActive(_ id: UUID?) {
        if activeTaskID != id { activeSubtaskID = nil }
        activeTaskID = id
    }

    /// Marks one subtask as the focus target (also activates its parent task).
    /// Pass nil to clear the target while keeping the task active.
    public func setActiveSubtask(taskID: UUID, subtaskID: UUID?) {
        setActive(taskID)
        activeSubtaskID = subtaskID
    }

    // MARK: - Persistence

    private func load() {
        tasks = database?.loadTasks() ?? []
    }

    private func persist() {
        database?.saveTasks(tasks)
    }

    private func loadCategories() {
        customCategories = database?.loadCategories() ?? []
    }

    private func persistCategories() {
        database?.saveCategories(customCategories)
    }

    /// One-time import of the pre-SQLite JSON files sitting next to the database.
    /// Runs only when the DB side is still empty, then renames each JSON to
    /// `*.migrated` so it's kept as a backup but never re-imported.
    private func migrateLegacyJSONIfNeeded(dbDir: URL) {
        let fm = FileManager.default
        let tasksJSON = dbDir.appendingPathComponent("tasks.json")
        if tasks.isEmpty,
           let data = try? Data(contentsOf: tasksJSON),
           let decoded = try? JSONDecoder().decode([TaskItem].self, from: data),
           !decoded.isEmpty {
            tasks = decoded
            persist()
            try? fm.moveItem(at: tasksJSON, to: tasksJSON.appendingPathExtension("migrated"))
        }
        let catsJSON = dbDir.appendingPathComponent("categories.json")
        if customCategories.isEmpty,
           let data = try? Data(contentsOf: catsJSON),
           let decoded = try? JSONDecoder().decode([TaskCategory].self, from: data),
           !decoded.isEmpty {
            customCategories = decoded
            persistCategories()
            try? fm.moveItem(at: catsJSON, to: catsJSON.appendingPathExtension("migrated"))
        }
    }

    // MARK: - Deadlines

    /// UserDefaults key for the "Due soon" pre-reminder offset in minutes.
    /// Absent key means the default of 10; 0 disables the pre-reminder.
    public static let preReminderDefaultsKey = "blink.task.preReminderMinutes"

    private func dueNoteID(_ id: UUID) -> String { "blink.task.due.\(id.uuidString)" }
    private func preNoteID(_ id: UUID) -> String { "blink.task.pre.\(id.uuidString)" }

    private var preReminderMinutes: Int {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.preReminderDefaultsKey) != nil else { return 10 }
        return defaults.integer(forKey: Self.preReminderDefaultsKey)
    }

    private func cancelDueNotifications(for id: UUID) {
        NotificationService.shared.cancel(identifier: dueNoteID(id))
        NotificationService.shared.cancel(identifier: preNoteID(id))
    }

    /// Single source of truth for a task's deadline reminders: cancels both the
    /// due-time and pre-reminder notifications, then reschedules them when the
    /// task is open with a future due date. Every mutation that touches
    /// `dueDate` or completion state must route through here (deletes cancel).
    private func syncDueNotifications(for task: TaskItem) {
        cancelDueNotifications(for: task.id)
        guard let due = task.dueDate, !task.isDone, due > Date() else { return }
        NotificationService.shared.schedule(
            title: "Task due",
            body: task.title,
            identifier: dueNoteID(task.id),
            at: due)
        let offset = preReminderMinutes
        let preFire = due.addingTimeInterval(TimeInterval(-offset * 60))
        if offset > 0, preFire > Date() {
            NotificationService.shared.schedule(
                title: "Due soon",
                body: "\(task.title) — in \(offset) min",
                identifier: preNoteID(task.id),
                at: preFire)
        }
    }

    // MARK: - Export

    /// The full task list as CSV (title, category, tags, status, pomodoros, due,
    /// created, completed).
    public func csv() -> String {
        func esc(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let iso = ISO8601DateFormatter()
        var rows = ["title,category,tags,done,pomodoros,due,created,completed"]
        for t in tasks {
            rows.append([
                esc(t.title),
                esc(t.category),
                esc(t.tags.joined(separator: " ")),
                t.isDone ? "yes" : "no",
                String(t.pomodorosDone),
                t.dueDate.map { iso.string(from: $0) } ?? "",
                iso.string(from: t.createdAt),
                t.completedAt.map { iso.string(from: $0) } ?? "",
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }
}
