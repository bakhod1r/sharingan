import SwiftUI
import Charts
import SharinganCore

/// The Analytics page: Focus/Consistency scores, the yearly heatmap, and the
/// focus-load chart — all fed by `FocusSessionLog` (per-session grain) plus the
/// long-lived aggregates in `PomodoroStats`.
struct AnalyticsView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var log = FocusSessionLog.shared
    @ObservedObject private var tasks = TaskStore.shared
    @State private var tab: Tab = .overview

    enum Tab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case heatmap  = "Heatmap"
        case load     = "Focus load"
        var id: String { rawValue }
    }

    private var accent: Color { timer.settings.theme.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            tabPicker
            switch tab {
            case .overview: overview
            case .heatmap:
                AnalyticsHeatmapView(stats: timer.stats, accent: accent)
            case .load:
                AnalyticsLoadView(timer: timer)
            }
        }
    }

    // MARK: - Tab picker (same pill idiom as StatsChartView's range picker)

    @Namespace private var pickerNS
    private var tabPicker: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases) { t in
                let selected = t == tab
                Button {
                    withAnimation(DS.Motion.standard) { tab = t }
                } label: {
                    Text(t.rawValue)
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(selected ? .white : .white.opacity(0.55))
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background {
                            if selected {
                                Capsule().fill(accent.opacity(0.9))
                                    .matchedGeometryEffect(id: "analyticsTab",
                                                           in: pickerNS)
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

    // MARK: - Overview

    private var todaySessions: [SessionRecord] { log.sessions(on: Date()) }

    /// Today's planned tasks: still-open Today view members plus those already
    /// completed today — so finishing your plan raises the ratio instead of
    /// shrinking the denominator.
    private var plannedCounts: (done: Int, total: Int) {
        let open = tasks.count(.today)
        let doneToday = tasks.tasks.filter { t in
            guard t.isDone, let at = t.completedAt else { return false }
            return Calendar.current.isDateInToday(at)
        }.count
        return (doneToday, open + doneToday)
    }

    private var focusScore: Int? {
        AnalyticsEngine.focusScore(sessions: todaySessions,
                                   dailyGoal: timer.settings.dailyPomodoroGoal,
                                   focusMinutes: timer.settings.focusMinutes)
    }

    private var consistencyScore: Int? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let recent: [[SessionRecord]] = (1...14).compactMap { back in
            guard let day = cal.date(byAdding: .day, value: -back, to: today)
            else { return nil }
            let s = log.sessions(on: day)
            return s.isEmpty ? nil : s
        }
        let planned = plannedCounts
        return AnalyticsEngine.consistencyScore(
            sessions: todaySessions, recentDays: recent,
            plannedDone: planned.done, plannedTotal: planned.total,
            streakDays: timer.stats.streak.currentStreak)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                scoreCard(title: "Focus Score", score: focusScore,
                          caption: "Bugungi diqqat sifati — hajm, yakunlash, tanaffuslar")
                scoreCard(title: "Consistency", score: consistencyScore,
                          caption: "Rejaga rioya — reja, ritm, streak")
            }
            if todaySessions.isEmpty {
                Text("No sessions yet today — scores appear after your first pomodoro.")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private func scoreCard(title: String, score: Int?, caption: String) -> some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: CGFloat(score ?? 0) / 100)
                    .stroke(AngularGradient(colors: [accent.opacity(0.6), accent],
                                            center: .center),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(DS.Motion.standard, value: score)
                Text(score.map(String.init) ?? "—")
                    .font(.system(size: 34, weight: .bold,
                                  design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
            }
            .frame(width: 110, height: 110)
            Text(caption)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .glassRounded(DS.Radius.xl, material: .regular)
        .liquidShadow(radius: 12, y: 6)
    }
}
