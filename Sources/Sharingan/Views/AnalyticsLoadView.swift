import SwiftUI
import Charts
import SharinganCore

/// "Focus load" — minutes of focus per hour of day for one day, with the
/// 30-day average overlaid, so the day's diqqat cho'qqilari stand out against
/// the usual rhythm. Day pager doubles as the load view's time machine.
struct AnalyticsLoadView: View {
    @ObservedObject var timer: PomodoroTimer
    var completedOnly: Bool = false
    var allowedTaskIDs: Set<UUID>? = nil
    var range: AnalyticsFilter.Range = .today
    @ObservedObject private var log = FocusSessionLog.shared
    @State private var day = Calendar.current.startOfDay(for: Date())

    private var accent: Color { timer.settings.theme.accent }

    /// A single day is browsed with the pager; any wider range aggregates the
    /// hourly load across its whole window (so the range actually changes the
    /// curve — the peaks of "a typical month", not one day).
    private var isSingleDay: Bool { range == .today }

    private func sessions(on d: Date) -> [SessionRecord] {
        AnalyticsEngine.filter(sessions: log.sessions(on: d),
                               completedOnly: completedOnly,
                               allowedTaskIDs: allowedTaskIDs)
    }

    private struct HourLoad: Identifiable {
        let hour: Int
        let minutes: Double        // primary series
        let avgMinutes: Double     // rolling-average overlay (single-day only)
        var id: Int { hour }
    }

    private var data: [HourLoad] {
        let cal = Calendar.current
        if isSingleDay {
            let today = AnalyticsEngine.hourlyLoad(sessions: sessions(on: day))
            var sums = [TimeInterval](repeating: 0, count: 24)
            var daysWithData = 0
            for back in 1...range.loadAverageDays {
                guard let d = cal.date(byAdding: .day, value: -back, to: day)
                else { continue }
                let s = sessions(on: d)
                guard !s.isEmpty else { continue }
                daysWithData += 1
                let load = AnalyticsEngine.hourlyLoad(sessions: s)
                for h in 0..<24 { sums[h] += load[h] }
            }
            return (0..<24).map { h in
                HourLoad(hour: h, minutes: today[h] / 60,
                         avgMinutes: daysWithData > 0
                            ? sums[h] / Double(daysWithData) / 60 : 0)
            }
        }
        // Total focus minutes per hour across the whole range.
        let today = cal.startOfDay(for: Date())
        var sums = [TimeInterval](repeating: 0, count: 24)
        for back in 0..<range.days {
            guard let d = cal.date(byAdding: .day, value: -back, to: today)
            else { continue }
            let load = AnalyticsEngine.hourlyLoad(sessions: sessions(on: d))
            for h in 0..<24 { sums[h] += load[h] }
        }
        return (0..<24).map { HourLoad(hour: $0, minutes: sums[$0] / 60, avgMinutes: 0) }
    }

    private var hasData: Bool { data.contains { $0.minutes > 0 || $0.avgMinutes > 0 } }

    /// Adaptive y-axis label: hours once a bar clears an hour, a decimal minute
    /// for small values (so ticks don't collapse to "0m 0m 1m 1m").
    private func yLabel(_ m: Double) -> String {
        if m <= 0 { return "0" }
        if m >= 60 { return String(format: "%.1fh", m / 60) }
        if m >= 10 { return "\(Int(m.rounded()))m" }
        return String(format: "%.1fm", m)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if hasData {
                chart
            } else {
                Text(isSingleDay ? "No focus sessions on this day."
                                 : "No focus sessions in this range.")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding(14)
        .glassRounded(DS.Radius.xl, material: .regular)
        .liquidShadow(radius: 12, y: 6)
    }

    @ViewBuilder
    private var header: some View {
        if isSingleDay { pager } else {
            Text("\(range.rawValue) · hourly focus load")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
        }
    }

    private var pager: some View {
        HStack {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.pressableSubtle)
            Spacer()
            Text(Calendar.current.isDateInToday(day)
                 ? "Today"
                 : day.formatted(date: .abbreviated, time: .omitted))
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Spacer()
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.pressableSubtle)
                .disabled(Calendar.current.isDateInToday(day))
                .opacity(Calendar.current.isDateInToday(day) ? 0.3 : 1)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white.opacity(0.8))
    }

    private func step(_ delta: Int) {
        if let d = Calendar.current.date(byAdding: .day, value: delta, to: day) {
            withAnimation(DS.Motion.standard) {
                day = min(d, Calendar.current.startOfDay(for: Date()))
            }
        }
    }

    private var chart: some View {
        Chart(data) { item in
            AreaMark(x: .value("Hour", item.hour),
                     y: .value("Minutes", item.minutes))
                .foregroundStyle(
                    LinearGradient(colors: [accent.opacity(0.55),
                                            accent.opacity(0.05)],
                                   startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            LineMark(x: .value("Hour", item.hour),
                     y: .value("Minutes", item.minutes))
                .foregroundStyle(accent)
                .interpolationMethod(.monotone)
            if item.avgMinutes > 0 {
                LineMark(x: .value("Hour", item.hour),
                         y: .value("30-day avg", item.avgMinutes),
                         series: .value("Series", "avg"))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .interpolationMethod(.monotone)
            }
        }
        .chartXScale(domain: 0...23)
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18, 23]) { v in
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel {
                    if let h = v.as(Int.self) {
                        Text("\(h):00")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { v in
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel {
                    if let m = v.as(Double.self) {
                        Text(yLabel(m))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        .frame(height: 180)
    }
}
