import Foundation

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

    public init(id: UUID = UUID(),
                title: String,
                category: String = TaskCategory.presets[0].name,
                tags: [String] = [],
                isDone: Bool = false,
                pomodorosDone: Int = 0,
                createdAt: Date = Date(),
                dueDate: Date? = nil) {
        self.id = id
        self.title = title
        self.category = category
        self.tags = tags
        self.isDone = isDone
        self.pomodorosDone = pomodorosDone
        self.createdAt = createdAt
        self.dueDate = dueDate
    }

    /// True when the task has a past deadline and isn't finished.
    public func isOverdue(now: Date = Date()) -> Bool {
        guard let dueDate, !isDone else { return false }
        return dueDate < now
    }
}

/// A named, color-coded bucket for tasks.
public struct TaskCategory: Identifiable, Codable, Equatable, Sendable {
    public var name: String
    public var colorHex: String

    public var id: String { name }

    public init(name: String, colorHex: String) {
        self.name = name
        self.colorHex = colorHex
    }

    public static let presets: [TaskCategory] = [
        .init(name: "Work",     colorHex: "#4F8DFD"),
        .init(name: "Study",    colorHex: "#A66BFF"),
        .init(name: "Personal", colorHex: "#3FD07F"),
        .init(name: "Health",   colorHex: "#FF6FA5"),
        .init(name: "Other",    colorHex: "#9AA3AF"),
    ]

    public static func color(for name: String) -> String {
        presets.first { $0.name == name }?.colorHex ?? "#9AA3AF"
    }
}
