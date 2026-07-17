import Foundation

/// The Analytics page's shared filter state: a time range, multi-select
/// task-attribution facets (categories / projects / tags — OR within a facet,
/// AND across facets), and a completed-only toggle. Resolving the facets to
/// sessions needs the live task list, so the view turns them into a
/// `Set<UUID>` of matching task IDs and hands that to `AnalyticsEngine.filter`.
public struct AnalyticsFilter: Equatable, Sendable {
    public enum Range: String, CaseIterable, Identifiable, Sendable {
        case today   = "Today"
        case week    = "1W"
        case month   = "1M"
        case quarter = "3M"
        case year    = "1Y"
        public var id: String { rawValue }

        /// Days back the Overview averages over (today included).
        public var days: Int {
            switch self {
            case .today:   return 1
            case .week:    return 7
            case .month:   return 30
            case .quarter: return 91
            case .year:    return 365
            }
        }

        /// Days the heatmap spans — floored to 4 weeks so short ranges still
        /// render a readable grid, capped at a year.
        public var heatmapDays: Int { min(364, max(28, days)) }

        /// Rolling window (days) for the focus-load average line.
        public var loadAverageDays: Int { max(7, days) }
    }

    public var range: Range
    public var completedOnly: Bool
    public var categories: Set<String>
    public var projects: Set<String>
    public var tags: Set<String>

    public init(range: Range = .today, completedOnly: Bool = false,
                categories: Set<String> = [], projects: Set<String> = [],
                tags: Set<String> = []) {
        self.range = range
        self.completedOnly = completedOnly
        self.categories = categories
        self.projects = projects
        self.tags = tags
    }

    public var hasAttributionFilter: Bool {
        !categories.isEmpty || !projects.isEmpty || !tags.isEmpty
    }

    /// True when anything narrows the raw session list.
    public var narrowsSessions: Bool { completedOnly || hasAttributionFilter }

    public mutating func clearAttribution() {
        categories.removeAll(); projects.removeAll(); tags.removeAll()
    }
}
