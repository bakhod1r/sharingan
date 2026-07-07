import SwiftUI
import Charts
import BlinkCore

struct StatsChartView: View {
    let stats: PomodoroStats
    @State private var range: Range = .week

    enum Range: String, CaseIterable, Identifiable {
        case week   = "7d"
        case month  = "30d"
        var id: String { rawValue }
        var days: Int { self == .week ? 7 : 30 }
    }

    private var data: [DailyCount] {
        stats.recentDays(range.days)
    }

    private var average: Double { stats.weeklyAverage }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stats")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                    Text("Avg: \(String(format: "%.1f", average))/day")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Picker("", selection: $range) {
                    ForEach(Range.allCases) { r in Text(r.rawValue).tag(r) }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                
            }

            weeklyReport

            Chart {
                ForEach(data) { item in
                    BarMark(
                        x: .value("Day", item.day, unit: .day),
                        y: .value("Pomodoros", item.count)
                    )
                    .foregroundStyle(
                        LinearGradient(colors: [.paletteFocusStart, .paletteBreakStart],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .cornerRadius(4)
                    .opacity(max(0.35, Double(item.count) / Double(max(1, data.map { $0.count }.max() ?? 1))))
                }
            }
            .chartXAxis {
                // Cap the number of labels so 30-day mode doesn't overlap into mush.
                AxisMarks(values: .automatic(desiredCount: range == .week ? 7 : 6)) { value in
                    if let d = value.as(Date.self) {
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel {
                            Text(xLabel(d))
                                .font(.system(size: 9, design: .rounded))
                        }
                        .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.12))
                    AxisValueLabel().foregroundStyle(.white.opacity(0.65))
                }
            }
            .frame(height: 180)

            if stats.hourCounts.contains(where: { $0 > 0 }) {
                Divider().overlay(Color.white.opacity(0.12))
                hourSection
            }
        }
        .padding(14)
        .glassRounded(DS.Radius.xl, material: .regular)
        .liquidShadow(radius: 12, y: 6)
    }

    // MARK: - Focus by hour

    private var hourSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Focus by hour")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                if let best = stats.bestFocusHour {
                    Text("Best: \(hourLabel(best))")
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundStyle(.orange)
                }
            }

            Chart {
                ForEach(Array(stats.hourCounts.enumerated()), id: \.offset) { hour, count in
                    BarMark(
                        x: .value("Hour", hour),
                        y: .value("Pomodoros", count)
                    )
                    .foregroundStyle(
                        hour == stats.bestFocusHour
                            ? AnyShapeStyle(Color.orange)
                            : AnyShapeStyle(Color.paletteFocusStart.opacity(0.75))
                    )
                    .cornerRadius(2)
                }
            }
            .chartXScale(domain: 0...23)
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                    if let h = value.as(Int.self) {
                        AxisValueLabel { Text(hourLabel(h)).font(.system(size: 9, design: .rounded)) }
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 90)
        }
    }

    private func hourLabel(_ h: Int) -> String {
        let hh = ((h % 12) == 0) ? 12 : h % 12
        return "\(hh)\(h < 12 ? "am" : "pm")"
    }

    /// This-week total with a week-over-week growth / decline indicator.
    private var weeklyReport: some View {
        let this = stats.thisWeekTotal()
        let last = stats.lastWeekTotal()
        let change = stats.weekOverWeekChange()
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("This week")
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Text("\(this) 🍅")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
            }
            Spacer()
            if let change {
                let up = change >= 0
                HStack(spacing: 4) {
                    Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 12, weight: .bold))
                    Text("\(up ? "+" : "")\(Int((change * 100).rounded()))%")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                }
                .foregroundStyle(up ? Color.green : Color.red)
                Text("vs last week (\(last))")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            } else {
                Text(last == 0 && this > 0 ? "First week — keep going!" : "No data yet")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .fill(Color.white.opacity(0.05)))
    }

    private func xLabel(_ d: Date) -> String {
        range == .week
            ? DateFormatter.shortDay.string(from: d)   // Mon, Tue…
            : DateFormatter.shortDate.string(from: d)   // 7/4
    }
}

private extension DateFormatter {
    static let shortDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEE"
        return f
    }()
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "M/d"
        return f
    }()
}