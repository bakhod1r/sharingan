import SwiftUI
import BlinkCore

/// Extra statistics for the main-window Stats page: a GitHub-style activity
/// heatmap, a weekday breakdown, and focus-by-category bars.
struct StatsExtrasView: View {
    let stats: PomodoroStats
    @ObservedObject private var store = TaskStore.shared
    var accent: Color = .paletteFocusStart

    private let weeks = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            heatmapCard
            HStack(alignment: .top, spacing: 16) {
                weekdayCard
                categoryCard
            }
        }
    }

    // MARK: - Heatmap

    /// Columns of weeks, each 7 cells (Mon…Sun), aligned so row 0 is Monday.
    private var heatmapColumns: [[DailyCount?]] {
        let cal = Calendar.current
        let days = stats.recentDays(weeks * 7)          // ascending, ends today
        guard let first = days.first?.day else { return [] }
        let wd = (cal.component(.weekday, from: first) + 5) % 7   // 0=Mon
        var cells: [DailyCount?] = Array(repeating: nil, count: wd) + days
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0+7]) }
    }

    private var heatmapMax: Int { max(1, stats.history.map(\.count).max() ?? 1) }

    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Activity").dsSectionLabel()
                Spacer()
                Text("last \(weeks) weeks")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.dsTertiary)
            }
            HStack(alignment: .top, spacing: 4) {
                // Weekday labels.
                VStack(alignment: .trailing, spacing: 3) {
                    ForEach(["Mon","","Wed","","Fri","","Sun"], id: \.self) { d in
                        Text(d).font(.system(size: 8, design: .rounded))
                            .foregroundStyle(Color.dsTertiary)
                            .frame(height: 13)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 3) {
                        ForEach(Array(heatmapColumns.enumerated()), id: \.offset) { _, col in
                            VStack(spacing: 3) {
                                ForEach(0..<7, id: \.self) { r in
                                    cell(col[r])
                                }
                            }
                        }
                    }
                }
            }
            legend
        }
        .padding(14)
        .glassRounded(DS.Radius.xl, material: .regular)
        .liquidShadow(radius: 12, y: 6)
    }

    private func cell(_ d: DailyCount?) -> some View {
        let count = d?.count ?? 0
        let intensity = d == nil ? -1.0 : Double(count) / Double(heatmapMax)
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(cellColor(intensity))
            .frame(width: 13, height: 13)
            .help(d.map { "\($0.count) 🍅 · \(dayLabel($0.day))" } ?? "")
    }

    private func cellColor(_ intensity: Double) -> Color {
        if intensity < 0 { return Color.white.opacity(0.03) }   // padding
        if intensity == 0 { return Color.white.opacity(0.06) }  // no activity
        return accent.opacity(0.28 + 0.62 * intensity)
    }

    private var legend: some View {
        HStack(spacing: 5) {
            Text("Less").font(.system(size: 9, design: .rounded)).foregroundStyle(Color.dsTertiary)
            ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { i in
                RoundedRectangle(cornerRadius: 2).fill(cellColor(i == 0 ? 0 : i))
                    .frame(width: 11, height: 11)
            }
            Text("More").font(.system(size: 9, design: .rounded)).foregroundStyle(Color.dsTertiary)
        }
    }

    // MARK: - Weekday

    private var weekdayCard: some View {
        let totals = stats.weekdayTotals()
        let peak = max(1, totals.max() ?? 1)
        let names = ["M","T","W","T","F","S","S"]
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("By weekday").dsSectionLabel()
                Spacer()
                if let b = stats.bestWeekday {
                    Text(["Mon","Tue","Wed","Thu","Fri","Sat","Sun"][b])
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(accent)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(i == stats.bestWeekday ? accent : accent.opacity(0.4))
                            .frame(height: max(4, 70 * CGFloat(totals[i]) / CGFloat(peak)))
                        Text(names[i]).font(.system(size: 9, design: .rounded))
                            .foregroundStyle(Color.dsSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 92, alignment: .bottom)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .glassRounded(DS.Radius.xl, material: .regular)
        .liquidShadow(radius: 12, y: 6)
    }

    // MARK: - Category

    /// Focus pomodoros logged per category (from tasks), most first.
    private var categoryTotals: [(name: String, count: Int, color: Color)] {
        var freq: [String: Int] = [:]
        for t in store.tasks where t.pomodorosDone > 0 {
            freq[t.category, default: 0] += t.pomodorosDone
        }
        return freq.sorted { $0.value > $1.value }.prefix(5).map {
            ($0.key, $0.value, Color(hex: store.color(for: $0.key)))
        }
    }

    private var categoryCard: some View {
        let totals = categoryTotals
        let peak = max(1, totals.map(\.count).max() ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text("By category").dsSectionLabel()
            if totals.isEmpty {
                Text("Run a focus session on a task to see this.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.dsTertiary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            } else {
                VStack(spacing: 9) {
                    ForEach(totals, id: \.name) { row in
                        HStack(spacing: 8) {
                            Circle().fill(row.color).frame(width: 8, height: 8)
                            Text(row.name)
                                .font(.system(.caption, design: .rounded).weight(.medium))
                                .foregroundStyle(Color.dsPrimary)
                                .frame(width: 66, alignment: .leading)
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(row.color)
                                    .frame(width: max(6, geo.size.width * CGFloat(row.count) / CGFloat(peak)))
                            }
                            .frame(height: 10)
                            Text("\(row.count)")
                                .font(.system(.caption2, design: .rounded).weight(.bold).monospacedDigit())
                                .foregroundStyle(Color.dsSecondary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .glassRounded(DS.Radius.xl, material: .regular)
        .liquidShadow(radius: 12, y: 6)
    }

    private func dayLabel(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "MMM d"
        return f.string(from: d)
    }
}
