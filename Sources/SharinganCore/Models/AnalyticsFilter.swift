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
    /// Selected Mac names (empty = every device). Sessions carry `deviceName`.
    public var devices: Set<String>
    /// A custom day span (inclusive) that overrides `range` when both are set —
    /// the calendar "from → to" picker. Days are start-of-day.
    public var customStart: Date?
    public var customEnd: Date?

    public init(range: Range = .today, completedOnly: Bool = false,
                categories: Set<String> = [], projects: Set<String> = [],
                tags: Set<String> = [], devices: Set<String> = [],
                customStart: Date? = nil, customEnd: Date? = nil) {
        self.range = range
        self.completedOnly = completedOnly
        self.categories = categories
        self.projects = projects
        self.tags = tags
        self.devices = devices
        self.customStart = customStart
        self.customEnd = customEnd
    }

    public var hasAttributionFilter: Bool {
        !categories.isEmpty || !projects.isEmpty || !tags.isEmpty
    }

    public var hasDeviceFilter: Bool { !devices.isEmpty }

    /// True when the calendar picker is driving the window instead of a preset.
    public var isCustomRange: Bool { customStart != nil && customEnd != nil }

    /// True when anything narrows the raw session list.
    public var narrowsSessions: Bool {
        completedOnly || hasAttributionFilter || hasDeviceFilter
    }

    /// The inclusive [start, end] window the current selection covers.
    public func interval(now: Date = Date()) -> DateInterval {
        let cal = Calendar.current
        if let s = customStart, let e = customEnd {
            let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: e))
                ?? e
            return DateInterval(start: cal.startOfDay(for: min(s, e)),
                                end: max(end, cal.startOfDay(for: min(s, e))))
        }
        let end = now
        let start = cal.date(byAdding: .day, value: -(range.days - 1),
                             to: cal.startOfDay(for: now)) ?? cal.startOfDay(for: now)
        return DateInterval(start: start, end: end)
    }

    /// Number of calendar days the current window spans (≥1) — the score loop's
    /// bound, honouring a custom range.
    public var spanDays: Int {
        guard let s = customStart, let e = customEnd else { return range.days }
        let cal = Calendar.current
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: min(s, e)),
                                      to: cal.startOfDay(for: max(s, e))).day ?? 0
        return max(1, days + 1)
    }

    /// Heatmap span honouring a custom range (floored to 4 weeks, capped a year).
    public var heatmapSpanDays: Int { min(364, max(28, spanDays)) }

    public mutating func clearAttribution() {
        categories.removeAll(); projects.removeAll(); tags.removeAll()
    }
}
