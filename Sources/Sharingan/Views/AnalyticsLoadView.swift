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
    var averageDays: Int = 30
    @ObservedObject private var log = FocusSessionLog.shared
    @State private var day = Calendar.current.startOfDay(for: Date())

    private var accent: Color { timer.settings.theme.accent }

    private func sessions(on d: Date) -> [SessionRecord] {
        AnalyticsEngine.filter(sessions: log.sessions(on: d),
                               completedOnly: completedOnly,
                               allowedTaskIDs: allowedTaskIDs)
    }

    private struct HourLoad: Identifiable {
        let hour: Int
        let minutes: Double
        let avgMinutes: Double
        var id: Int { hour }
    }

    private var data: [HourLoad] {
        let today = AnalyticsEngine.hourlyLoad(sessions: sessions(on: day))
        // Rolling average per hour over the selected window (days with data).
        let cal = Calendar.current
        var sums = [TimeInterval](repeating: 0, count: 24)
        var daysWithData = 0
        for back in 1...max(1, averageDays) {
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

    private var hasData: Bool { data.contains { $0.minutes > 0 || $0.avgMinutes > 0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            pager
            if hasData {
                chart
            } else {
                Text("No focus sessions on this day.")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding(14)
        .glassRounded(DS.Radius.xl, material: .regular)
        .liquidShadow(radius: 12, y: 6)
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
                        Text("\(Int(m))m")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        .frame(height: 180)
    }
}
