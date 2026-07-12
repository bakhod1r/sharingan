import SwiftUI
import SharinganCore

/// A grid of lifetime metric cards shown at the top of the main-window Stats
/// page — the "many statistics" overview that the compact popover deliberately
/// omits.
struct StatsSummaryView: View {
    let stats: PomodoroStats
    let focusMinutes: Int
    var accent: Color = .paletteFocusStart
    /// Today's pomodoro target (0 = no goal configured).
    var dailyGoal: Int = 0
    @ObservedObject private var store = TaskStore.shared

    /// A deliberately narrow palette — colour carries meaning instead of a stock
    /// rainbow: warm orange for streak/achievement, green for today, and the
    /// theme accent for every focus-volume metric.
    private var metrics: [Metric] {
        let totalMinutes = stats.completedFocus * max(1, focusMinutes)
        return [
            Metric("flame.fill", "\(stats.streak.currentStreak)", "Day streak",
                   .orange, sub: "best \(stats.streak.longestStreak)"),
            Metric("checkmark.seal.fill", "\(stats.completedFocus)", "Focus sessions",
                   accent),
            Metric("clock.fill", focusTime(totalMinutes), "Focus time",
                   accent),
            Metric("calendar",
                   dailyGoal > 0
                       ? "\(stats.completedTodayCount())/\(dailyGoal)"
                       : "\(stats.completedTodayCount())",
                   dailyGoal > 0 ? "Today · goal" : "Today",
                   .green,
                   sub: dailyGoal > 0 && stats.completedTodayCount() >= dailyGoal
                       ? "goal reached 🎯" : nil),
            Metric("chart.line.uptrend.xyaxis", "\(stats.thisWeekTotal())", "This week",
                   accent, sub: weekTrend()),
            Metric("star.fill", "\(stats.bestDay?.count ?? 0)", "Best day",
                   .orange),
            Metric("square.grid.2x2.fill", "\(stats.activeDays)", "Active days",
                   accent),
            Metric("gauge.medium", String(format: "%.1f", stats.averagePerActiveDay), "Avg / day",
                   accent),
            Metric("sunrise.fill", bestHour(), "Best hour",
                   accent),
            Metric("calendar.circle.fill", "\(stats.total(fromDaysAgo: 0, toDaysAgo: 30))", "Last 30 days",
                   accent),
            Metric("checklist", "\(doneTasks)", "Tasks done",
                   .green, sub: "\(openTasks) open"),
        ]
    }

    private var doneTasks: Int { store.tasks.filter(\.isDone).count }
    private var openTasks: Int { store.tasks.count - doneTasks }

    private let columns = [GridItem(.adaptive(minimum: 132, maximum: 200), spacing: 12)]

    var body: some View {
        VStack(spacing: 12) {
            // Two headline numbers, sized up, so the page has a clear focal point
            // instead of nine equal-weight cards.
            HStack(spacing: 12) {
                heroCard(metrics[0])
                heroCard(metrics[1])
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(metrics.dropFirst(2)) { m in
                    card(m)
                }
            }
        }
    }

    /// A larger card for a headline metric — bigger number, tint-washed surface.
    private func heroCard(_ m: Metric) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(m.tint.opacity(0.18))
                Image(systemName: m.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(m.tint)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.value)
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text(m.label)
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))
                if let sub = m.sub {
                    Text(sub)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(Color.dsSecondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(m.tint.opacity(0.06)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func card(_ m: Metric) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
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
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(Color.white.opacity(0.04)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
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
