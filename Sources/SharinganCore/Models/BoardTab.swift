/// The boards inside the main window's Board section: the local weekly
/// planner, the kanban board, and the project timeline.
///
/// `rawValue` is persisted (the `board.tab` `UserDefaults` key), so the cases
/// and their spellings must stay stable — a rename would silently reset every
/// user back to the default tab.
public enum BoardTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case weekly, kanban, timeline
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .weekly:   return "Weekly"
        case .kanban:   return "Board"
        case .timeline: return "Timeline"
        }
    }

    public var icon: String {
        switch self {
        case .weekly:   return "calendar"
        case .kanban:   return "rectangle.split.3x1"
        case .timeline: return "chart.bar.xaxis"
        }
    }
}
