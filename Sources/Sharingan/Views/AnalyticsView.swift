import SwiftUI
import Charts
import SharinganCore

/// The Analytics page: Focus/Consistency scores, the yearly heatmap, and the
/// focus-load chart — all fed by `FocusSessionLog` (per-session grain) plus the
/// long-lived aggregates in `PomodoroStats`. A shared filter bar narrows every
/// tab: a time range (averages the Overview scores), one task-attribution
/// dimension (category / project / tag), and a completed-only toggle.
struct AnalyticsView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var log = FocusSessionLog.shared
    @ObservedObject private var tasks = TaskStore.shared
    @State private var tab: Tab = .overview
    @State private var filter = AnalyticsFilter()

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
            filterBar
            switch tab {
            case .overview:
                overview
            case .heatmap:
                AnalyticsHeatmapView(
                    stats: timer.stats, accent: accent,
                    // A narrowed view can't read the aggregate history, so feed
                    // the heatmap a session-derived series instead.
                    override: filter.narrowsSessions
                        ? AnalyticsEngine.dailyCounts(from: filteredAllSessions)
                        : nil,
                    spanDays: filter.range.heatmapDays)
            case .load:
                AnalyticsLoadView(timer: timer, completedOnly: filter.completedOnly,
                                  allowedTaskIDs: allowedTaskIDs,
                                  averageDays: filter.range.loadAverageDays)
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

    // MARK: - Filter bar

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                rangePicker
                filterMenu
                completedToggle
                Spacer()
            }
            if filter.hasAttributionFilter { chipRow }
        }
    }

    private var chipRow: some View {
        // Wraps so many selections don't overflow the width.
        FlowChips(spacing: 6) {
            ForEach(Array(filter.categories).sorted(), id: \.self) { c in
                chip(c) { filter.categories.remove(c) }
            }
            ForEach(Array(filter.projects).sorted(), id: \.self) { p in
                chip(p) { filter.projects.remove(p) }
            }
            ForEach(Array(filter.tags).sorted(), id: \.self) { t in
                chip("#\(t)") { filter.tags.remove(t) }
            }
            Button("Clear all") { withAnimation(DS.Motion.hover) { filter.clearAttribution() } }
                .buttonStyle(.plain)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func chip(_ label: String, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
            Button { withAnimation(DS.Motion.hover) { remove() } } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(accent)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Capsule().fill(accent.opacity(0.15)))
    }

    @Namespace private var rangeNS
    private var rangePicker: some View {
        HStack(spacing: 2) {
            ForEach(AnalyticsFilter.Range.allCases) { r in
                let selected = r == filter.range
                Button {
                    withAnimation(DS.Motion.standard) { filter.range = r }
                } label: {
                    Text(r.rawValue)
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(selected ? .white : .white.opacity(0.5))
                        .frame(width: 40, height: 22)
                        .background {
                            if selected {
                                Capsule().fill(accent.opacity(0.85))
                                    .matchedGeometryEffect(id: "rangePill", in: rangeNS)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressableSubtle)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.05)))
    }

    private var filterMenu: some View {
        Menu {
            if !tasks.allCategories.isEmpty {
                Section("Category") {
                    ForEach(tasks.allCategories) { cat in
                        toggleButton(cat.name, on: filter.categories.contains(cat.name)) {
                            toggle(&filter.categories, cat.name)
                        }
                    }
                }
            }
            if !tasks.projects.isEmpty {
                Section("Project") {
                    ForEach(tasks.projects, id: \.self) { proj in
                        toggleButton(proj, on: filter.projects.contains(proj)) {
                            toggle(&filter.projects, proj)
                        }
                    }
                }
            }
            if !tasks.allTags.isEmpty {
                Section("Tag") {
                    ForEach(tasks.allTags, id: \.self) { tag in
                        toggleButton("#\(tag)", on: filter.tags.contains(tag)) {
                            toggle(&filter.tags, tag)
                        }
                    }
                }
            }
            if filter.hasAttributionFilter {
                Divider()
                Button("Clear all", role: .destructive) { filter.clearAttribution() }
            }
        } label: {
            Image(systemName: filter.hasAttributionFilter
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(filter.hasAttributionFilter ? accent : .white.opacity(0.55))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// A menu row that shows a checkmark when its value is selected — SwiftUI
    /// menus keep multi-select menus open between taps.
    private func toggleButton(_ label: String, on: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: on ? "checkmark" : "")
        }
    }

    private func toggle(_ set: inout Set<String>, _ value: String) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    private var completedToggle: some View {
        Button {
            withAnimation(DS.Motion.hover) { filter.completedOnly.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: filter.completedOnly
                      ? "checkmark.circle.fill" : "checkmark.circle")
                Text("Completed only")
            }
            .font(.system(.caption2, design: .rounded).weight(.semibold))
            .foregroundStyle(filter.completedOnly ? accent : .white.opacity(0.55))
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Capsule().fill(filter.completedOnly
                                       ? accent.opacity(0.15) : Color.white.opacity(0.05)))
        }
        .buttonStyle(.pressableSubtle)
    }

    // MARK: - Filtering helpers

    /// Tasks matching the active facets → their IDs; nil when no facet is set.
    /// OR within a facet, AND across facets (a task must satisfy every non-empty
    /// facet). Deleted tasks aren't in the live list, so their sessions drop —
    /// same as the Report tab.
    private var allowedTaskIDs: Set<UUID>? {
        guard filter.hasAttributionFilter else { return nil }
        let ids = tasks.tasks.filter { t in
            if !filter.categories.isEmpty && !filter.categories.contains(t.category) {
                return false
            }
            if !filter.projects.isEmpty {
                guard let p = t.project, filter.projects.contains(p) else { return false }
            }
            if !filter.tags.isEmpty {
                let hit = t.tags.contains { tag in
                    filter.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
                }
                if !hit { return false }
            }
            return true
        }.map(\.id)
        return Set(ids)
    }

    private func filtered(_ sessions: [SessionRecord]) -> [SessionRecord] {
        AnalyticsEngine.filter(sessions: sessions,
                               completedOnly: filter.completedOnly,
                               allowedTaskIDs: allowedTaskIDs)
    }

    /// Every logged session, filtered — used to derive the narrowed heatmap.
    private var filteredAllSessions: [SessionRecord] { filtered(log.records) }

    // MARK: - Overview

    /// Days (start-of-day) that carry ≥1 completed focus session in the filtered
    /// log — the basis for the per-day streak used when averaging over a range.
    private var completedFocusDays: Set<Date> {
        let cal = Calendar.current
        return Set(filteredAllSessions
            .filter { $0.phase == .focus && $0.completed }
            .map { cal.startOfDay(for: $0.start) })
    }

    /// Consecutive days with completed focus ending at `day` (inclusive).
    private func streak(upTo day: Date, in days: Set<Date>) -> Int {
        let cal = Calendar.current
        var count = 0
        var cursor = cal.startOfDay(for: day)
        while days.contains(cursor) {
            count += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return count
    }

    /// (Focus, Consistency) averaged across the selected range. `range == .today`
    /// collapses to the single live day (with the real planned-task counts). For
    /// past days, plan adherence is unknown, so its neutral default applies and
    /// the streak is reconstructed from the log.
    private var overviewScores: (focus: Int?, consistency: Int?) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let doneDays = completedFocusDays
        var focusScores: [Int?] = []
        var consistencyScores: [Int?] = []

        for back in 0..<filter.range.days {
            guard let day = cal.date(byAdding: .day, value: -back, to: today)
            else { continue }
            let daySessions = filtered(log.sessions(on: day))

            focusScores.append(AnalyticsEngine.focusScore(
                sessions: daySessions,
                dailyGoal: timer.settings.dailyPomodoroGoal,
                focusMinutes: timer.settings.focusMinutes))

            let recent: [[SessionRecord]] = (1...14).compactMap { b in
                guard let d = cal.date(byAdding: .day, value: -b, to: day)
                else { return nil }
                let s = filtered(log.sessions(on: d))
                return s.isEmpty ? nil : s
            }
            let isToday = cal.isDate(day, inSameDayAs: today)
            let planned = isToday ? plannedCounts : (0, 0)
            consistencyScores.append(AnalyticsEngine.consistencyScore(
                sessions: daySessions, recentDays: recent,
                plannedDone: planned.0, plannedTotal: planned.1,
                streakDays: streak(upTo: day, in: doneDays)))
        }
        return (AnalyticsEngine.average(focusScores),
                AnalyticsEngine.average(consistencyScores))
    }

    /// Today's planned tasks: still-open Today view members plus those already
    /// completed today — so finishing your plan raises the ratio instead of
    /// shrinking the denominator.
    private var plannedCounts: (Int, Int) {
        let open = tasks.count(.today)
        let doneToday = tasks.tasks.filter { t in
            guard t.isDone, let at = t.completedAt else { return false }
            return Calendar.current.isDateInToday(at)
        }.count
        return (doneToday, open + doneToday)
    }

    private var rangeSuffix: String {
        filter.range == .today ? "" : " · \(filter.range.rawValue) avg"
    }

    private var overview: some View {
        let scores = overviewScores
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                scoreCard(title: "Focus Score", score: scores.focus,
                          caption: "Diqqat sifati — hajm, yakunlash, tanaffuslar\(rangeSuffix)")
                scoreCard(title: "Consistency", score: scores.consistency,
                          caption: "Rejaga rioya — reja, ritm, streak\(rangeSuffix)")
            }
            if scores.focus == nil {
                Text(filter.narrowsSessions
                     ? "No sessions match this filter."
                     : "No sessions yet — scores appear after your first pomodoro.")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private func scoreCard(title: String, score: Int?, caption: String) -> some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: CGFloat(score ?? 0) / 100)
                    .stroke(AngularGradient(colors: [accent.opacity(0.6), accent],
                                            center: .center),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(DS.Motion.standard, value: score)
                VStack(spacing: 0) {
                    Text(score.map(String.init) ?? "—")
                        .font(.system(size: 44, weight: .bold,
                                      design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                    Text("/ 100")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .frame(width: 140, height: 140)
            Text(caption)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .glassRounded(DS.Radius.xl, material: .regular)
        .liquidShadow(radius: 14, y: 7)
    }
}

/// Simple wrapping HStack for the filter chips — flows onto new rows instead of
/// overflowing the width when many facets are selected.
struct FlowChips: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxWidth, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
