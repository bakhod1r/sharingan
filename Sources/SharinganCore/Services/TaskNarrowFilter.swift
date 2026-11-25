import Foundation

/// Which sidebar/menu narrowing dimensions are active on the task list.
/// Pure, so the "is anything narrowed" and chip-picking rules are testable.
public struct TaskNarrowFilter: Equatable, Sendable {
    public var category: String?
    public var project: String?
    public var tag: String?
    public var priority: TaskPriority?
    public var device: String?

    public init(category: String? = nil, project: String? = nil, tag: String? = nil,
                priority: TaskPriority? = nil, device: String? = nil) {
        self.category = category
        self.project = project
        self.tag = tag
        self.priority = priority
        self.device = device
    }

    public enum Chip: Equatable, Sendable {
        case category(String), project(String), tag(String)
        case priority(TaskPriority), device(String)

        /// Symbol shown before the label. Matches the composer's parser
        /// vocabulary: tags are `#`, projects are `@`.
        public var symbol: String {
            switch self {
            case .category: return "●"
            case .project: return "@"
            case .tag: return "#"
            case .priority: return "⚑"
            case .device: return "💻"
            }
        }
    }

    /// True when any dimension is set.
    public var isActive: Bool { chip != nil }

    /// The chip to show: first active dimension, in the order
    /// category, project, tag, priority, device.
    public var chip: Chip? {
        if let c = category { return .category(c) }
        if let p = project { return .project(p) }
        if let t = tag { return .tag(t) }
        if let p = priority { return .priority(p) }
        if let d = device { return .device(d) }
        return nil
    }
}
