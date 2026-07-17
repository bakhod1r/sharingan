import SwiftUI
import SharinganCore

/// GitHub-contribution-style yearly heatmap of completed pomodoros, fed from
/// the long-lived `PomodoroStats.history` aggregates (so it's full even for
/// users whose per-session log starts today).
struct AnalyticsHeatmapView: View {
    let stats: PomodoroStats
    var accent: Color
    @State private var selected: DailyCount?

    private var weeks: [[DailyCount?]] {
        AnalyticsEngine.heatmapWeeks(days: stats.recentDays(364))
    }

    /// 0…4 intensity step for a day's count against the year's peak.
    private func level(_ count: Int, peak: Int) -> Int {
        guard count > 0, peak > 0 else { return 0 }
        return min(4, 1 + (count * 3) / peak)
    }

    var body: some View {
        let weeks = self.weeks
        let peak = stats.recentDays(364).map(\.count).max() ?? 0
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 3) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: 3) {
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
