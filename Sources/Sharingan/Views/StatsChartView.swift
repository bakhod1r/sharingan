import SwiftUI
import Charts
import SharinganCore

struct StatsChartView: View {
    let stats: PomodoroStats
    var accent: Color = .paletteFocusStart
    @State private var range: ChartRange = .month

    /// Time window + bucketing for the focus-history chart.
    enum ChartRange: String, CaseIterable, Identifiable {
        case week    = "1W"    // last 7 days, daily bars
        case month   = "1M"    // last 30 days, daily bars
        case quarter = "3M"    // last 13 weeks, weekly bars
        case year    = "1Y"    // last 12 months, monthly bars
        var id: String { rawValue }

        /// Calendar unit each bar spans — drives BarMark width + axis stride.
        var unit: Calendar.Component {
            switch self {
            case .week, .month: return .day
            case .quarter:      return .weekOfYear
            case .year:         return .month
            }
        }

        /// What one bar represents, for the "avg per …" caption.
        var perLabel: String {
            switch self {
            case .week, .month: return "day"
            case .quarter:      return "week"
            case .year:         return "month"
            }
        }
    }

    /// The bucketed series for the active range — every slot filled (0 where
    /// idle) so the axis shows the whole window, not just active days.
    private var data: [DailyCount] {
        switch range {
        case .week:    return stats.recentDays(7)
        case .month:   return stats.recentDays(30)
        case .quarter: return stats.recentWeeks(13)
        case .year:    return stats.recentMonths(12)
        }
    }

    private var total: Int { data.reduce(0) { $0 + $1.count } }
    private var average: Double {
        guard !data.isEmpty else { return 0 }
        return Double(total) / Double(data.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            chart
            if stats.hourCounts.contains(where: { $0 > 0 }) {
                Divider().overlay(Color.white.opacity(0.12))
                hourSection
            }
        }
        .padding(14)
        .glassRounded(DS.Radius.xl, material: .regular)
        .liquidShadow(radius: 12, y: 6)
    }

    // MARK: - Header + range picker

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Focus history")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                Text("\(total) 🍅 · avg \(String(format: "%.1f", average))/\(range.perLabel)")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .contentTransition(.numericText())
            }
            Spacer()
            rangePicker
        }
    }

    /// Custom segmented range control — animated selection pill, tactile press.
    private var rangePicker: some View {
        HStack(spacing: 2) {
            ForEach(ChartRange.allCases) { r in
                let selected = r == range
                Button {
                    withAnimation(DS.Motion.standard) { range = r }
                } label: {
                    Text(r.rawValue)
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(selected ? .white : .white.opacity(0.55))
                        .frame(width: 34, height: 24)
                        .background {
                            if selected {
                                Capsule().fill(accent.opacity(0.9))
                                    .matchedGeometryEffect(id: "rangePill", in: pickerNS)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressableSubtle)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }
    @Namespace private var pickerNS

    // MARK: - Main chart

    private var chart: some View {
        Chart {
            ForEach(data) { item in
                BarMark(
                    x: .value("Period", item.day, unit: range.unit),
                    y: .value("Pomodoros", item.count),
                    width: .fixed(barWidth)
                )
                .foregroundStyle(
                    LinearGradient(colors: [accent, accent.opacity(0.55)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .cornerRadius(3)
                // Direct value labels only where they stay readable — the
                // 7-bar week view; denser ranges rely on the axis + avg rule.
                .annotation(position: .top, spacing: 3) {
                    if range == .week, item.count > 0 {
                        Text("\(item.count)")
                            .font(.system(size: 9, weight: .bold,
                                          design: .rounded).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            if average > 0 {
                RuleMark(y: .value("Average", average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.white.opacity(0.3))
                    .annotation(position: .top, alignment: .trailing, spacing: 2) {
                        Text("avg \(String(format: "%.1f", average))")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: range.unit, count: axisStride)) { value in
                if let d = value.as(Date.self) {
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                    AxisValueLabel {
                        Text(xLabel(d)).font(.system(size: 9, design: .rounded))
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
        .animation(DS.Motion.gentle, value: range)
    }

    /// Slim, evenly-breathing bars per range — wide 7-day bars read as slabs.
    private var barWidth: CGFloat {
        switch range {
        case .week:    return 26
        case .month:   return 9
        case .quarter: return 16
        case .year:    return 18
        }
    }

    /// Stride between axis labels so they never overlap into mush.
    private var axisStride: Int {
        switch range {
        case .week:    return 1     // every day
        case .month:   return 4     // ~8 labels across 30 days
        case .quarter: return 2     // every other week
        case .year:    return 1     // every month
        }
    }

    private func xLabel(_ d: Date) -> String {
        switch range {
        case .week:            return DateFormatter.chartDay.string(from: d)    // Mon
        case .month, .quarter: return DateFormatter.chartDate.string(from: d)   // 7/4
        case .year:            return DateFormatter.chartMonth.string(from: d)  // Jul
        }
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
                        .foregroundStyle(accent)
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
                            ? AnyShapeStyle(accent)
                            : AnyShapeStyle(accent.opacity(0.4))
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
            // A minimal 2-mark scale so the bar heights are quantified, not just
            // relative shapes.
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 2)) { _ in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel().foregroundStyle(.white.opacity(0.4))
                }
            }
            .frame(height: 90)
        }
    }

    private func hourLabel(_ h: Int) -> String {
        let hh = ((h % 12) == 0) ? 12 : h % 12
        return "\(hh)\(h < 12 ? "am" : "pm")"
    }
}

private extension DateFormatter {
    static let chartDay: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "EEE"; return f
    }()
    static let chartDate: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "M/d"; return f
    }()
    static let chartMonth: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "MMM"; return f
    }()
}
