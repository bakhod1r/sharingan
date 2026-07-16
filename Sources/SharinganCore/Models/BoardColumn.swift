import Foundation

/// A user-defined column on the Sharingan board. The column list is stored in
/// the synced settings blob; a task names its column through
/// `TaskItem.boardColumnID`.
///
/// Columns are pure buckets with one exception: a column whose `role` is
/// `.done` also drives `TaskItem.isDone` — dropping a task into it completes
/// the task, dragging it out reopens it. Everything else is just grouping.
public struct BoardColumn: Identifiable, Codable, Equatable, Sendable {

    public enum Role: String, Codable, Sendable {
        /// An ordinary bucket — membership has no side effect.
        case plain
        /// Dropping a task here sets `isDone`; removing it clears `isDone`.
        case done
    }

    /// Stable id. Seeded columns use a slug ("today"); user-added columns use a
    /// UUID string. Persisted and referenced by `TaskItem.boardColumnID`, so it
    /// must never change once created.
    public var id: String
    public var name: String
    public var order: Int
    public var isEnabled: Bool
    public var role: Role

    public init(id: String = UUID().uuidString, name: String, order: Int,
                isEnabled: Bool = true, role: Role = .plain) {
        self.id = id
        self.name = name
        self.order = order
        self.isEnabled = isEnabled
        self.role = role
    }

    /// Fields added incrementally decode as optional so a future older build
    /// still loads a newer synced column list.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 0
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        role = try c.decodeIfPresent(Role.self, forKey: .role) ?? .plain
    }

    // MARK: - Seed

    /// Fixed slugs for the seeded columns, so migration and the `.done`
    /// coupling can find them by id.
    public enum Seed {
        public static let today = "today"
        public static let thisWeek = "this-week"
        public static let inProgress = "in-progress"
        public static let paused = "paused"
        public static let done = "done"
        public static let cancelled = "cancelled"
    }

    /// The default column set, in display order, seeded on first run.
    public static let defaults: [BoardColumn] = [
        BoardColumn(id: Seed.today,      name: "Today",       order: 0),
        BoardColumn(id: Seed.thisWeek,   name: "This Week",   order: 1),
        BoardColumn(id: Seed.inProgress, name: "In Progress", order: 2),
        BoardColumn(id: Seed.paused,     name: "Paused",      order: 3),
        BoardColumn(id: Seed.done,       name: "Done",        order: 4, role: .done),
        BoardColumn(id: Seed.cancelled,  name: "Cancelled",   order: 5),
    ]

    /// The id a task lands in when migrated from the pre-columns board:
    /// completed tasks go to the Done column, everything else stays unassigned
    /// (rendered in the first column).
    public static func migratedColumnID(isDone: Bool) -> String? {
        isDone ? Seed.done : nil
    }
}

public extension Array where Element == BoardColumn {
    /// Enabled columns in display order — what the board actually renders.
    var enabledInOrder: [BoardColumn] {
        filter(\.isEnabled).sorted { $0.order < $1.order }
    }

    /// The column a task with this stored id renders in: its own column when
    /// that column is enabled, otherwise the first enabled column (the "inbox"
    /// fallback for nil / disabled / deleted ids).
    func resolvedColumn(for storedID: String?) -> BoardColumn? {
        let enabled = enabledInOrder
        if let storedID, let match = enabled.first(where: { $0.id == storedID }) {
            return match
        }
        return enabled.first
    }
}
