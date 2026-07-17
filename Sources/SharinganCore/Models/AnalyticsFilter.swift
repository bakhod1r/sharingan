import Foundation

/// The Analytics page's shared filter state: a time range (drives the Overview
/// scores), one optional task-attribution dimension (category / project / tag,
/// mirroring the app's one-dimension-at-a-time filter idiom), and a
/// completed-only toggle. Applying the attribution dimension to sessions needs
/// the live task list, so the view resolves it to a `Set<UUID>` and hands that
/// to `AnalyticsEngine.filter`.
public struct AnalyticsFilter: Equatable, Sendable {
    public enum Range: String, CaseIterable, Identifiable, Sendable {
        case today   = "Today"
        case week    = "1W"
        case month   = "1M"
        case quarter = "3M"
        case year    = "1Y"
        public var id: String { rawValue }

        /// How many days back the Overview averages over (today included).
        public var days: Int {
            switch self {
            case .today:   return 1
            case .week:    return 7
            case .month:   return 30
            case .quarter: return 91
            case .year:    return 365
            }
        }
    }

    public enum Dimension: Equatable, Sendable {
        case category(String)
        case project(String)
        case tag(String)

        public var label: String {
            switch self {
            case .category(let c): return c
            case .project(let p):  return p
            case .tag(let t):      return "#\(t)"
            }
        }
    }

    public var range: Range
    public var completedOnly: Bool
    public var dimension: Dimension?

    public init(range: Range = .today, completedOnly: Bool = false,
                dimension: Dimension? = nil) {
        self.range = range
        self.completedOnly = completedOnly
        self.dimension = dimension
    }

    /// True when anything narrows the raw session list (so surfaces that
    /// otherwise read the aggregate history know to recompute from sessions).
    public var narrowsSessions: Bool { completedOnly || dimension != nil }
}
