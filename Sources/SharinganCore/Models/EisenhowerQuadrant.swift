import Foundation

/// The four cells of the Eisenhower matrix — a smart view that sorts open
/// tasks by urgency (deadline pressure) × importance (priority flag).
///
/// Classification is pure and side-effect free: it looks only at the task's
/// fields and the supplied `now`. Filtering out completed tasks is the
/// caller's responsibility.
public enum EisenhowerQuadrant: CaseIterable, Identifiable, Sendable {
    /// Urgent and important — do it now.
    case doFirst
    /// Important but not urgent — put it on the calendar.
    case schedule
    /// Urgent but not important — hand it off (or knock it out fast).
    case delegate
    /// Neither — later, maybe never.
    case eliminate

    public var id: Self { self }

    /// Card title.
    public var label: String {
        switch self {
        case .doFirst:   return "Do first"
        case .schedule:  return "Schedule"
        case .delegate:  return "Delegate"
        case .eliminate: return "Later"
        }
    }

    /// One-line reading of the axis combination, for card subtitles/help.
    public var subtitle: String {
        switch self {
        case .doFirst:   return "Urgent · important"
        case .schedule:  return "Important, not urgent"
        case .delegate:  return "Urgent, not important"
        case .eliminate: return "Neither"
        }
    }

    /// SF Symbol shown in the card header.
    public var icon: String {
        switch self {
        case .doFirst:   return "flame.fill"
        case .schedule:  return "calendar"
        case .delegate:  return "person.2.fill"
        case .eliminate: return "tray"
        }
    }

    /// Card tint — matches the app's task palette (P1 red, P3 blue, P2 amber,
    /// neutral gray).
    public var tintHex: String {
        switch self {
        case .doFirst:   return "#FF5E5B"
        case .schedule:  return "#4F8DFD"
        case .delegate:  return "#FFB020"
        case .eliminate: return "#9AA3AF"
        }
    }

    /// Maps a task onto its quadrant.
    ///
    /// - urgent: has a due date that is overdue or within 48 hours of `now`,
    ///   or the task is on today's plan.
    /// - important: priority is P1 (.high) or P2 (.medium).
    public static func classify(_ task: TaskItem, now: Date = Date()) -> EisenhowerQuadrant {
        let urgent = isUrgent(task, now: now)
        // Important = P2 (medium) or higher — custom levels sit above P1, so a
        // `>=` on rawValue folds them into "important" automatically.
        let important = task.priority.rawValue >= TaskPriority.medium.rawValue
        switch (urgent, important) {
        case (true,  true):  return .doFirst
        case (false, true):  return .schedule
        case (true,  false): return .delegate
        case (false, false): return .eliminate
        }
    }

    private static let urgentWindow: TimeInterval = 48 * 3600

    private static func isUrgent(_ task: TaskItem, now: Date) -> Bool {
        if task.isPlannedToday(now: now) { return true }
        guard let due = task.dueDate else { return false }
        return due.timeIntervalSince(now) <= urgentWindow   // overdue or ≤ 48h out
    }
}
