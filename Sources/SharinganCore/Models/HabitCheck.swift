import Foundation

/// A manual tick: `taskID`'s habit was done on `day` (start of day).
public struct HabitCheck: Codable, Equatable, Hashable, Sendable {
    public var day: Date
    public var taskID: UUID

    public init(day: Date, taskID: UUID) {
        self.day = day
        self.taskID = taskID
    }
}
