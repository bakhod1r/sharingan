import SwiftUI
import SharinganCore

/// GitHub-contribution-style heatmap of completed pomodoros: week columns,
/// Monday-first rows, month labels along the top and weekday labels down the
/// left. Fed from the aggregate `PomodoroStats.history`, or a session-derived
/// series when a filter narrows the data.
struct AnalyticsHeatmapView: View {
    let stats: PomodoroStats
    var accent: Color
    /// Session-derived daily series used when a filter is active (the aggregate
    /// history can't be narrowed by task/completion).
    var override: [DailyCount]? = nil
    /// How many days the grid spans (from the selected range).
    var spanDays: Int = 364
    @State private var selected: DailyCount?

    private let cell: CGFloat = 13
    private let gap: CGFloat = 4
    private let weekdayLabels = ["Mon", "", "Wed", "", "Fri", "", ""]

    /// The daily series to render, padded to `spanDays` so idle days show.
    private var days: [DailyCount] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let byDay: [Date: Int]
        if let override {
            byDay = Dictionary(override.map { ($0.day, $0.count) },
                               uniquingKeysWith: +)
        } else {
            byDay = Dictionary(stats.recentDays(spanDays).map { ($0.day, $0.count) },
                               uniquingKeysWith: +)
        }
        return (0..<spanDays).reversed().compactMap { back in
            guard let d = cal.date(byAdding: .day, value: -back, to: today)
            else { return nil }
            return DailyCount(day: d, count: byDay[d] ?? 0)
        }
    }

    private func level(_ count: Int, peak: Int) -> Int {
        guard count > 0, peak > 0 else { return 0 }
        return min(4, 1 + (count * 3) / peak)
    }

    private func color(_ level: Int) -> Color {
        level == 0 ? Color.white.opacity(0.06)
                   : accent.opacity(0.28 + Double(level) * 0.18)
    }

    var body: some View {
        let days = self.days
        let weeks = AnalyticsEngine.heatmapWeeks(days: days)
        let peak = days.map(\.count).max() ?? 0
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: gap) {
                    monthHeader(weeks: weeks)
                    HStack(alignment: .top, spacing: gap) {
                        weekdayColumn
                        ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                            VStack(spacing: gap) {
                                ForEach(0..<7, id: \.self) { slot in
                                    cellView(week[slot], peak: peak)
                                }
                            }
                        }
                    }
                }
                .padding(2)
            }
            footer
        }
        .padding(16)
        .glassRounded(DS.Radius.xl, material: .regular)
        .liquidShadow(radius: 12, y: 6)
    }

    // MARK: - Grid pieces

    private func cellView(_ day: DailyCount?, peak: Int) -> some View {
        Group {
            if let day {
                RoundedRectangle(cornerRadius: 3)
                    .fill(color(level(day.count, peak: peak)))
                    .frame(width: cell, height: cell)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(selected?.day == day.day ? .white : .clear,
                                    lineWidth: 1.5))
                    .onHover { if $0 { selected = day } }
            } else {
                Color.clear.frame(width: cell, height: cell)
            }
        }
    }

    private var weekdayColumn: some View {
        VStack(spacing: gap) {
            ForEach(0..<7, id: \.self) { i in
                Text(weekdayLabels[i])
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 26, height: cell, alignment: .leading)
            }
        }
    }

    /// Month abbreviation above the first week column that begins each month.
    private func monthHeader(weeks: [[DailyCount?]]) -> some View {
        let cal = Calendar.current
        let fmt = DateFormatter(); fmt.dateFormat = "MMM"
        var labels: [String] = []
        var lastMonth = -1
        for week in weeks {
            let firstDay = week.compactMap { $0?.day }.first
            if let d = firstDay {
                let m = cal.component(.month, from: d)
                if m != lastMonth { labels.append(fmt.string(from: d)); lastMonth = m }
                else { labels.append("") }
            } else { labels.append("") }
        }
        return HStack(spacing: gap) {
            Color.clear.frame(width: 26, height: 12)          // weekday-column gutter
            ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: cell, height: 12, alignment: .leading)
            }
        }
    }

    private var footer: some View {
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
            HStack(spacing: 3) {
                Text("Less")
                ForEach(0..<5, id: \.self) { lvl in
                    RoundedRectangle(cornerRadius: 2).fill(color(lvl))
                        .frame(width: 11, height: 11)
                }
                Text("More")
            }
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(.white.opacity(0.5))
        }
    }
}
