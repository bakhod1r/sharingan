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
