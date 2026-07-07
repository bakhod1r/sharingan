import SwiftUI
import BlinkCore

/// A grid of lifetime metric cards shown at the top of the main-window Stats
/// page — the "many statistics" overview that the compact popover deliberately
/// omits.
struct StatsSummaryView: View {
    let stats: PomodoroStats
    let focusMinutes: Int
    var accent: Color = .paletteFocusStart

    private var metrics: [Metric] {
        let totalMinutes = stats.completedFocus * max(1, focusMinutes)
        return [
            Metric("flame.fill", "\(stats.streak.currentStreak)", "Day streak",
                   .orange, sub: "best \(stats.streak.longestStreak)"),
            Metric("checkmark.seal.fill", "\(stats.completedFocus)", "Total 🍅",
                   accent),
            Metric("clock.fill", focusTime(totalMinutes), "Focus time",
                   .cyan),
            Metric("calendar", "\(stats.completedTodayCount())", "Today",
                   .green),
            Metric("chart.line.uptrend.xyaxis", "\(stats.thisWeekTotal())", "This week",
                   accent, sub: weekTrend()),
            Metric("star.fill", "\(stats.bestDay?.count ?? 0)", "Best day",
                   .yellow),
            Metric("square.grid.2x2.fill", "\(stats.activeDays)", "Active days",
                   .purple),
            Metric("gauge.medium", String(format: "%.1f", stats.averagePerActiveDay), "Avg / day",
                   .teal),
            Metric("sunrise.fill", bestHour(), "Best hour",
                   .pink),
        ]
    }

    private let columns = [GridItem(.adaptive(minimum: 132, maximum: 200), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(metrics) { m in
                card(m)
            }
        }
    }

    private func card(_ m: Metric) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(m.tint.opacity(0.18))
                Image(systemName: m.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(m.tint)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 1) {
                Text(m.value)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(m.label)
                    .font(.system(.caption2, design: .rounded).weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))
                if let sub = m.sub {
                    Text(sub)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(Color.dsSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.04)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Formatting

    private func focusTime(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private func bestHour() -> String {
        guard let h = stats.bestFocusHour else { return "—" }
        let hh = (h % 12 == 0) ? 12 : h % 12
        return "\(hh)\(h < 12 ? "am" : "pm")"
    }

    private func weekTrend() -> String? {
        guard let change = stats.weekOverWeekChange() else { return nil }
        let pct = Int((change * 100).rounded())
        return "\(pct >= 0 ? "↑" : "↓") \(abs(pct))% vs last"
    }

    private struct Metric: Identifiable {
        var id: String { label }
        let icon: String
        let value: String
        let label: String
        let tint: Color
        let sub: String?
        init(_ icon: String, _ value: String, _ label: String, _ tint: Color, sub: String? = nil) {
            self.icon = icon; self.value = value; self.label = label; self.tint = tint; self.sub = sub
        }
    }
}
