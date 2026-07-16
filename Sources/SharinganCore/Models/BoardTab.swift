/// The two boards inside the main window's Board section: the local weekly
/// planner and the Jira sprint board.
///
/// `rawValue` is persisted (the `board.tab` `UserDefaults` key), so the cases
/// and their spellings must stay stable — a rename would silently reset every
/// user back to the default tab.
public enum BoardTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case weekly, jira
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .weekly: return "Weekly"
        case .jira:   return "Jira"
        }
    }
}
