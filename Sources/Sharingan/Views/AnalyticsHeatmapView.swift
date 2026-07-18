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
    /// Extra space inserted before the week column that starts a new month, so
    /// months read as separated blocks.
    private let monthGap: CGFloat = 12
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
        let peak = days.map(\.count).max() ?? 0
        let byDay = Dictionary(days.map { ($0.day, $0.count) }, uniquingKeysWith: +)
        VStack(alignment: .leading, spacing: 14) {
            statsHeader(days)
            ScrollView(.horizontal, showsIndicators: false) {
                // LeetCode-style: one self-contained block per month, a clear gap
                // between them, and the month name centred under its block.
                HStack(alignment: .top, spacing: monthGap) {
                    weekdayColumn
                    ForEach(months(days), id: \.self) { month in
                        monthBlock(month, byDay: byDay, peak: peak)
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

    // MARK: - LeetCode-style month blocks

    /// First-of-month for every month the visible span touches, chronological.
    private func months(_ days: [DailyCount]) -> [Date] {
        let cal = Calendar.current
        guard let first = days.first?.day, let last = days.last?.day else { return [] }
        var out: [Date] = []
        var cursor = cal.date(from: cal.dateComponents([.year, .month], from: first)) ?? first
        let end = cal.date(from: cal.dateComponents([.year, .month], from: last)) ?? last
        while cursor <= end {
            out.append(cursor)
            guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return out
    }

    /// One month drawn as week-columns (Monday-first rows), only that month's
    /// days filled, with the month label centred beneath.
    private func monthBlock(_ month: Date, byDay: [Date: Int], peak: Int) -> some View {
        let cal = Calendar.current
        let fmt = DateFormatter(); fmt.dateFormat = "MMM"
        let cols = monthColumns(month)
        let today = cal.startOfDay(for: Date())
        return VStack(spacing: 6) {
            HStack(alignment: .top, spacing: gap) {
                ForEach(Array(cols.enumerated()), id: \.offset) { _, column in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { row in
                            if let day = column[row], day <= today {
                                cellView(DailyCount(day: day, count: byDay[day] ?? 0), peak: peak)
                            } else {
                                Color.clear.frame(width: cell, height: cell)
                            }
                        }
                    }
                }
            }
            Text(fmt.string(from: month))
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    /// A month's days laid out into week-columns: `[column][weekdayRow]`,
    /// Monday-first, nil outside the month.
    private func monthColumns(_ month: Date) -> [[Date?]] {
        let cal = Calendar.current
        guard let first = cal.date(from: cal.dateComponents([.year, .month], from: month)),
              let count = cal.range(of: .day, in: .month, for: first)?.count
        else { return [] }
        let lead = (cal.component(.weekday, from: first) + 5) % 7   // 0 = Mon
        var slots = [Date?](repeating: nil, count: lead)
        for d in 0..<count { slots.append(cal.date(byAdding: .day, value: d, to: first)) }
        while slots.count % 7 != 0 { slots.append(nil) }
        return stride(from: 0, to: slots.count, by: 7).map { c in
            (0..<7).map { r in slots[c + r] }
        }
    }

    // MARK: - Stats header (LeetCode-style totals)

    private func statsHeader(_ days: [DailyCount]) -> some View {
        let total = days.reduce(0) { $0 + $1.count }
        let active = days.filter { $0.count > 0 }.count
        let maxStreak = longestActiveStreak(days)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(total)")
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(.white)
            Text("pomodoros")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            statChip("Active days", active)
            statChip("Max streak", maxStreak)
        }
    }

    private func statChip(_ label: String, _ value: Int) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
            Text("\(value)")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    /// Longest run of consecutive calendar days with ≥1 completed focus.
    private func longestActiveStreak(_ days: [DailyCount]) -> Int {
        var best = 0, run = 0
        for d in days {                      // `days` is chronological, gap-free
            run = d.count > 0 ? run + 1 : 0
            best = max(best, run)
        }
        return best
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
