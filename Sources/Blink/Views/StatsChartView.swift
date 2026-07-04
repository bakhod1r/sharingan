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
                .tint(.white)
            }

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
        }
        .padding(14)
        .glassRounded(22, material: .regular)
        .liquidShadow(radius: 12, y: 6)
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