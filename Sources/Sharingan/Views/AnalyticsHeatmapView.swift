import SwiftUI
import SharinganCore

/// GitHub-contribution-style yearly heatmap of completed pomodoros, fed from
/// the long-lived `PomodoroStats.history` aggregates (so it's full even for
/// users whose per-session log starts today).
struct AnalyticsHeatmapView: View {
    let stats: PomodoroStats
    var accent: Color
    /// When a filter narrows the sessions, the aggregate history no longer
    /// applies — the caller passes a session-derived daily series instead.
    var override: [DailyCount]? = nil
    @State private var selected: DailyCount?

    /// The daily series to render: the filtered override, else the full
    /// 364-day aggregate history (padded so idle days still show).
    private var days: [DailyCount] {
        if let override {
            // Pad to a full 364-day window so the grid shape stays stable.
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let byDay = Dictionary(uniqueKeysWithValues: override.map { ($0.day, $0.count) })
            return (0..<364).reversed().compactMap { back in
                guard let d = cal.date(byAdding: .day, value: -back, to: today)
                else { return nil }
                return DailyCount(day: d, count: byDay[d] ?? 0)
            }
        }
        return stats.recentDays(364)
    }

    private var weeks: [[DailyCount?]] {
        AnalyticsEngine.heatmapWeeks(days: days)
    }

    /// 0…4 intensity step for a day's count against the year's peak.
    private func level(_ count: Int, peak: Int) -> Int {
        guard count > 0, peak > 0 else { return 0 }
        return min(4, 1 + (count * 3) / peak)
    }

    var body: some View {
        let days = self.days
        let weeks = AnalyticsEngine.heatmapWeeks(days: days)
        let peak = days.map(\.count).max() ?? 0
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 4) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: 4) {
                            ForEach(0..<7, id: \.self) { slot in
                                cell(week[slot], peak: peak)
                            }
                        }
                    }
                }
                .padding(2)
            }
            HStack(spacing: 12) {
                if let sel = selected {
                    Text("\(sel.count) 🍅 · \(sel.day.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .contentTransition(.numericText())
                } else {
                    Text("Hover a day for details")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                legend
            }
        }
        .padding(14)
        .glassRounded(DS.Radius.xl, material: .regular)
        .liquidShadow(radius: 12, y: 6)
    }

    @ViewBuilder
    private func cell(_ day: DailyCount?, peak: Int) -> some View {
        if let day {
            let lvl = level(day.count, peak: peak)
            RoundedRectangle(cornerRadius: 2.5)
                .fill(lvl == 0 ? Color.white.opacity(0.06)
                      : accent.opacity(0.25 + Double(lvl) * 0.19))
                .frame(width: 11, height: 11)
                .onHover { inside in
                    if inside { selected = day }
                }
        } else {
            Color.clear.frame(width: 11, height: 11)
        }
    }

    private var legend: some View {
        HStack(spacing: 3) {
            Text("Less")
            ForEach(0..<5, id: \.self) { lvl in
                RoundedRectangle(cornerRadius: 2)
                    .fill(lvl == 0 ? Color.white.opacity(0.06)
                          : accent.opacity(0.25 + Double(lvl) * 0.19))
                    .frame(width: 9, height: 9)
            }
            Text("More")
        }
        .font(.system(.caption2, design: .rounded))
        .foregroundStyle(.white.opacity(0.5))
    }
}
