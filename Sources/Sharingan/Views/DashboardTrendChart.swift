import SwiftUI
import Charts

/// One day on the Overview trend line.
struct TrendPoint: Identifiable, Equatable {
    let date: Date
    let value: Double          // focus minutes that day
    var id: Date { date }
}

/// The Dashboard Overview centrepiece — a full-width gradient area+line chart of
/// focus minutes per day, echoing the "Sessions overview / Traffic Trend" charts
/// in the reference dashboards: soft gradient fill, a smooth accent stroke,
/// point marks, and a scrubbable tooltip. Draws itself in on appear.
struct DashboardTrendChart: View {
    let points: [TrendPoint]
    var accent: Color
    /// Percentage change of the second half vs the first half of the window.
    var delta: Double?

    @State private var selected: TrendPoint?
    @State private var drawn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var total: Double { points.reduce(0) { $0 + $1.value } }
    private var peak: Double { max(1, points.map(\.value).max() ?? 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            chart
                .frame(height: 200)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassRounded(DS.Radius.xl, material: .regular)
        .liquidShadow(radius: 14, y: 7)
        .onAppear {
            guard !reduceMotion else { drawn = true; return }
            withAnimation(.easeOut(duration: 1.0)) { drawn = true }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Focus trend")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                HStack(spacing: 8) {
                    Text(focusTime(Int(total)))
                        .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                    if let delta { deltaBadge(delta) }
                }
                Text("Focus time per day · \(points.count)d")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            if let sel = selected {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(sel.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(focusTime(Int(sel.value)))
                        .font(.system(.callout, design: .rounded).weight(.bold))
                        .foregroundStyle(accent)
                }
                .transition(.opacity)
            }
        }
    }

    private func deltaBadge(_ d: Double) -> some View {
        let up = d >= 0
        let color: Color = up ? .green : .orange
        return HStack(spacing: 2) {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 9, weight: .bold))
            Text("\(up ? "+" : "")\(Int(d.rounded()))%")
                .font(.system(.caption2, design: .rounded).weight(.bold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.16)))
    }

    private var chart: some View {
        Chart(points) { p in
            AreaMark(x: .value("Day", p.date),
                     y: .value("Minutes", drawn ? p.value : 0))
                .foregroundStyle(LinearGradient(
                    colors: [accent.opacity(0.45), accent.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("Day", p.date),
                     y: .value("Minutes", drawn ? p.value : 0))
                .foregroundStyle(LinearGradient(
                    colors: [accent, accent.opacity(0.7)],
                    startPoint: .leading, endPoint: .trailing))
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .interpolationMethod(.catmullRom)
            if points.count <= 31 {
                PointMark(x: .value("Day", p.date),
                          y: .value("Minutes", drawn ? p.value : 0))
                    .foregroundStyle(accent)
                    .symbolSize(selected == p ? 90 : 26)
            }
            if let sel = selected, sel == p {
                RuleMark(x: .value("Day", p.date))
                    .foregroundStyle(.white.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(.white.opacity(0.07))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { v in
                AxisValueLabel(format: .dateTime.day().month(.narrow))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            guard let plot = proxy.plotFrame else { return }
                            let x = drag.location.x - geo[plot].origin.x
                            guard let date: Date = proxy.value(atX: x) else { return }
                            selected = points.min {
                                abs($0.date.timeIntervalSince(date))
                                    < abs($1.date.timeIntervalSince(date))
                            }
                        }
                        .onEnded { _ in selected = nil })
            }
        }
    }

    private func focusTime(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
