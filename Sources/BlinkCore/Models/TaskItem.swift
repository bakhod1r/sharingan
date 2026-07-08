import Foundation

/// A single checklist item under a task.
public struct Subtask: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var isDone: Bool

    public init(id: UUID = UUID(), title: String, isDone: Bool = false) {
        self.id = id
        self.title = title
        self.isDone = isDone
    }
}

/// How a task repeats after completion.
public enum Recurrence: String, Codable, Sendable, CaseIterable, Identifiable {
    case none, daily, weekdays, weekly
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .none:     return "Does not repeat"
        case .daily:    return "Every day"
        case .weekdays: return "Weekdays"
        case .weekly:   return "Every week"
        }
    }
    /// The next occurrence date after `date`.
    public func nextDate(after date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .none:  return date
        case .daily: return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .weekly: return calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .weekdays:
            var d = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            while calendar.isDateInWeekend(d) {
                d = calendar.date(byAdding: .day, value: 1, to: d) ?? d
            }
            return d
        }
    }
}

/// Task priority, Todoist-style: P1 (urgent, red) … P4 (none). Higher rawValue
/// = more urgent, so sorting descending puts P1 first.
public enum TaskPriority: Int, Codable, Sendable, CaseIterable, Identifiable {
    case none = 0   // P4 — no flag
    case low  = 1   // P3 — blue
    case medium = 2 // P2 — orange
    case high = 3   // P1 — red

    public var id: Int { rawValue }

    /// "P1"…"P4".
    public var label: String { "P\(4 - rawValue)" }

    /// Menu label.
    public var menuLabel: String {
        switch self {
        case .none:   return "No priority"
        case .low:    return "P3 · Low"
        case .medium: return "P2 · Medium"
        case .high:   return "P1 · Urgent"
        }
    }

    /// Flag color hex, or nil for `.none`.
    public var colorHex: String? {
        switch self {
        case .none:   return nil
        case .low:    return "#4F8DFD"
        case .medium: return "#FFB020"
        case .high:   return "#FF5E5B"
        }
    }
}

/// A task the user can run focus pomodoros against.
public struct TaskItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var category: String
    public var tags: [String]
    public var isDone: Bool
    public var pomodorosDone: Int
    public var createdAt: Date
    public var dueDate: Date?
    /// Manual ordering position within the list (lower = higher up).
    public var sortOrder: Int
    /// Planned number of pomodoros for this task (nil = no estimate).
    public var estimatedPomodoros: Int?
    /// Start-of-day this task is planned for (nil = not on a daily plan).
    public var plannedDate: Date?
    /// Free-form notes.
    public var notes: String
    /// Checklist items.
    public var subtasks: [Subtask]
    /// Repeat rule applied when the task is completed.
    public var recurrence: Recurrence
    /// Optional project grouping (a second axis above category).
    public var project: String?
    /// Todoist-style priority flag.
    public var priority: TaskPriority

    public init(id: UUID = UUID(),
                title: String,
                category: String = TaskCategory.presets[0].name,
                tags: [String] = [],
                isDone: Bool = false,
                pomodorosDone: Int = 0,
                createdAt: Date = Date(),
                dueDate: Date? = nil,
                sortOrder: Int = 0,
                estimatedPomodoros: Int? = nil,
                plannedDate: Date? = nil,
                notes: String = "",
                subtasks: [Subtask] = [],
                recurrence: Recurrence = .none,
                project: String? = nil,
                priority: TaskPriority = .none) {
        self.id = id
        self.title = title
        self.category = category
        self.tags = tags
        self.isDone = isDone
        self.pomodorosDone = pomodorosDone
        self.createdAt = createdAt
        self.dueDate = dueDate
        self.sortOrder = sortOrder
        self.estimatedPomodoros = estimatedPomodoros
        self.plannedDate = plannedDate
        self.notes = notes
        self.subtasks = subtasks
        self.recurrence = recurrence
        self.project = project
        self.priority = priority
    }

    // Defensive decoding: several fields (category, tags, pomodorosDone) were
    // added after the first release. Without this, an older tasks.json missing
    // any of them throws `keyNotFound`, TaskStore.load() swallows it, and the
    // next mutation persists an EMPTY list — silently wiping every task.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        category = try c.decodeIfPresent(String.self, forKey: .category)
            ?? TaskCategory.presets[0].name
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        pomodorosDone = try c.decodeIfPresent(Int.self, forKey: .pomodorosDone) ?? 0
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        estimatedPomodoros = try c.decodeIfPresent(Int.self, forKey: .estimatedPomodoros)
        plannedDate = try c.decodeIfPresent(Date.self, forKey: .plannedDate)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        subtasks = try c.decodeIfPresent([Subtask].self, forKey: .subtasks) ?? []
        recurrence = try c.decodeIfPresent(Recurrence.self, forKey: .recurrence) ?? .none
        project = try c.decodeIfPresent(String.self, forKey: .project)
        priority = try c.decodeIfPresent(TaskPriority.self, forKey: .priority) ?? .none
    }

    /// True when the task has a past deadline and isn't finished.
    public func isOverdue(now: Date = Date()) -> Bool {
        guard let dueDate, !isDone else { return false }
        return dueDate < now
    }

    /// Completed subtasks over total, e.g. (2, 5). Zero total when no subtasks.
    public var subtaskProgress: (done: Int, total: Int) {
        (subtasks.filter(\.isDone).count, subtasks.count)
    }

    /// True when this task is on today's plan.
    public func isPlannedToday(now: Date = Date()) -> Bool {
        guard let plannedDate else { return false }
        return Calendar.current.isDate(plannedDate, inSameDayAs: now)
    }
}

/// A named, color-coded, icon-tagged bucket for tasks.
public struct TaskCategory: Identifiable, Codable, Equatable, Sendable {
    public var name: String
    public var colorHex: String
    /// SF Symbol name shown alongside the category.
    public var icon: String

    public var id: String { name }

    public init(name: String, colorHex: String, icon: String = "folder.fill") {
        self.name = name
        self.colorHex = colorHex
        self.icon = icon
    }

    // `icon` was added later — decode it as optional so older saved
    // categories.json (without the key) still loads.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        colorHex = try c.decode(String.self, forKey: .colorHex)
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "folder.fill"
    }

    public static let presets: [TaskCategory] = [
        .init(name: "Work",     colorHex: "#4F8DFD", icon: "briefcase.fill"),
        .init(name: "Study",    colorHex: "#A66BFF", icon: "book.fill"),
        .init(name: "Personal", colorHex: "#3FD07F", icon: "person.fill"),
        .init(name: "Health",   colorHex: "#FF6FA5", icon: "heart.fill"),
        .init(name: "Other",    colorHex: "#9AA3AF", icon: "folder.fill"),
    ]

    public static func color(for name: String) -> String {
        presets.first { $0.name == name }?.colorHex ?? "#9AA3AF"
    }

    /// Swatches offered when creating a custom category.
    public static let palette: [String] = [
        "#4F8DFD", "#A66BFF", "#3FD07F", "#FF6FA5",
        "#FFB020", "#22C3B8", "#FF6B5E", "#9AA3AF",
    ]

    /// SF Symbols offered when choosing a category icon.
    public static let iconChoices: [String] = [
        "briefcase.fill", "book.fill", "person.fill", "heart.fill",
        "folder.fill", "star.fill", "flame.fill", "bolt.fill",
        "cart.fill", "house.fill", "gamecontroller.fill", "dumbbell.fill",
        "cup.and.saucer.fill", "airplane", "pencil", "paintbrush.fill",
    ]
}
