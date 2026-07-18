import SwiftUI
import SharinganCore

/// Day-paged per-task focus report: every task that logged focus on the
/// chosen day, with pomodoro count and real minutes, subtask rows expandable
/// underneath. Data comes straight from TaskStore.focusLog (see FocusLog.swift
/// for the task-row-includes-subtasks rule).
struct ReportView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var store = TaskStore.shared
    @ObservedObject private var log = FocusSessionLog.shared
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var expanded: Set<String> = []
    /// Row ordering — persisted; its own key, the report is a different list.
    @AppStorage("report.sortMode") private var sortModeRaw = ReportSortMode.time.rawValue
    private var sortMode: ReportSortMode { ReportSortMode(rawValue: sortModeRaw) ?? .time }
    /// Category narrowing — transient. Deleted-task rows carry no category,
    /// so any pick hides them too.
    @State private var categoryFilter: String?

    private var accent: Color { timer.settings.theme.accent }
    private var cal: Calendar { Calendar.current }
    private var isToday: Bool { cal.isDateInToday(day) }
    /// Every row the day logged — the filter decides what shows, but this is
    /// what "day is empty" means.
    private var allRows: [FocusReportRow] {
        FocusReport.rows(entries: store.focusEntries(on: day), tasks: store.tasks)
    }
    private var rows: [FocusReportRow] {
        let narrowed = categoryFilter.map { c in allRows.filter { $0.category == c } }
            ?? allRows
        return sortMode.apply(narrowed)
    }

    /// Which apps each task was focused in on this day, most-used first — the
    /// strip shown under an expanded task row. Empty when tracking is off or
    /// nothing was recorded. Keyed by task ID (deleted-task rows keep theirs).
    private var appsByTask: [UUID: [AnalyticsEngine.AppTotal]] {
        AnalyticsEngine.appTotalsByTask(sessions: log.sessions(on: day))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            pager
            if allRows.isEmpty {
                emptyState
            } else if rows.isEmpty {
                noMatchState
            } else {
                VStack(spacing: 2) {
                    ForEach(rows) { row in reportRow(row) }
                }
                totalsFooter
            }
        }
    }

    // MARK: - Day pager

    private var pager: some View {
        HStack(spacing: 10) {
            pagerButton("chevron.left", enabled: true) {
                day = cal.date(byAdding: .day, value: -1, to: day) ?? day
            }
            Text(dayLabel)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .frame(minWidth: 180)
            pagerButton("chevron.right", enabled: !isToday) {
                day = min(cal.startOfDay(for: Date()),
                          cal.date(byAdding: .day, value: 1, to: day) ?? day)
            }
            Spacer()
            if !isToday {
                Button("Today") { day = cal.startOfDay(for: Date()) }
                    .buttonStyle(.pressableSubtle)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(accent)
            }
            sortMenu
            filterMenu
        }
    }

    /// Sort + category filter for the day's rows — the same quiet circle
    /// style as the pager buttons.
    private var sortMenu: some View {
        Menu {
            ForEach(ReportSortMode.allCases) { mode in
                Button {
                    withAnimation(DS.Motion.gentle) { sortModeRaw = mode.rawValue }
                } label: {
                    Label(mode.label, systemImage: sortMode == mode ? "checkmark" : mode.icon)
                }
            }
        } label: {
            reportCircle("arrow.up.arrow.down", active: sortMode != .time)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help(sortMode == .time ? "Sort rows" : "Sorted by \(sortMode.label)")
        .accessibilityLabel("Sort report rows")
    }

    private var filterMenu: some View {
        Menu {
            ForEach(store.allCategories) { c in
                Button {
                    withAnimation(DS.Motion.gentle) {
                        categoryFilter = categoryFilter == c.name ? nil : c.name
                    }
                } label: {
                    Label(c.name, systemImage: categoryFilter == c.name ? "checkmark" : c.icon)
                }
            }
            if categoryFilter != nil {
                Divider()
                Button(role: .destructive) {
                    withAnimation(DS.Motion.gentle) { categoryFilter = nil }
                } label: {
                    Label("Clear filter", systemImage: "xmark.circle")
                }
            }
        } label: {
            reportCircle(categoryFilter == nil ? "line.3.horizontal.decrease.circle"
                                               : "line.3.horizontal.decrease.circle.fill",
                         active: categoryFilter != nil)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Filter by category")
        .accessibilityLabel("Filter report rows")
    }

    private func reportCircle(_ icon: String, active: Bool) -> some View {
        Image(systemName: icon)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(active ? accent : .white)
            .frame(width: 26, height: 26)
            .background(Circle().fill(active ? accent.opacity(0.18)
                                             : Color.white.opacity(0.06)))
            .contentShape(Circle())
    }

    private func pagerButton(_ symbol: String, enabled: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(enabled ? .white : .white.opacity(0.25))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var dayLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEE, MMM d"
        return isToday ? "\(f.string(from: day)) · Today" : f.string(from: day)
    }

    // MARK: - Rows

    private func reportRow(_ row: FocusReportRow) -> some View {
        let apps = appsByTask[row.entry.taskID] ?? []
        let canExpand = !row.subrows.isEmpty || !apps.isEmpty
        return VStack(spacing: 2) {
            HStack(spacing: 10) {
                // No reserved slot for rows without detail — the chevron only
                // takes space where it actually appears, so a leaf row starts
                // flush with the code instead of leaving a blank gap. The
                // checkmark/circle "done" icon is gone too: the strikethrough
                // on the title already carries that.
                if canExpand {
                    Button {
                        if expanded.contains(row.id) { expanded.remove(row.id) }
                        else { expanded.insert(row.id) }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                            .rotationEffect(.degrees(expanded.contains(row.id) ? 90 : 0))
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                }
                // Task code. The number lives on the task, so a row whose task
                // was deleted outright has no code to show — it gets a dash, and
                // the title beside it still says what the session was.
                Text(store.tasks.first { $0.id == row.entry.taskID }?.code ?? "—")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                Text(row.entry.title)
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .strikethrough(row.isDone, color: .white.opacity(0.4))
                    .foregroundStyle(row.isDeleted ? .white.opacity(0.4) : .white)
                    .lineLimit(1)
                if row.isDeleted {
                    Text("deleted")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                } else if let cat = row.category {
                    Text(cat.uppercased())
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(Color(hex: store.color(for: cat)))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color(hex: store.color(for: cat)).opacity(0.14)))
                }
                Spacer(minLength: 8)
                metric(count: row.entry.count, seconds: row.entry.seconds)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(Color.white.opacity(0.04)))

            if expanded.contains(row.id) {
                ForEach(row.subrows) { sub in
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.3))
                        Text(sub.title)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        metric(count: sub.count, seconds: sub.seconds)
                    }
                    .padding(.leading, 38).padding(.trailing, 12).padding(.vertical, 6)
                }
                if !apps.isEmpty { TaskAppStrip(apps: apps) }
            }
        }
    }

    private func metric(count: Int, seconds: TimeInterval) -> some View {
        HStack(spacing: 10) {
            Text("🍅 ×\(count)")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(FocusReport.durationLabel(seconds))
                .font(.system(.caption, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(accent)
                .frame(minWidth: 46, alignment: .trailing)
        }
    }

    /// Shown when the day has rows but the category filter hides them all.
    private var noMatchState: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.white.opacity(0.25))
                Text("No focus in this category.")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
        }
        .padding(.vertical, 60)
    }

    private var totalsFooter: some View {
        // Sum exactly what's on screen (task-level entries already include their
        // subtask credits). The store's day total still counts deleted/trashed
        // tasks, which the rows now hide — reducing over `rows` keeps the footer
        // in step with the list.
        let totals = rows.reduce(into: (count: 0, seconds: TimeInterval(0))) {
            $0.count += $1.entry.count
            $0.seconds += $1.entry.seconds
        }
        return HStack {
            Text("Total")
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            metric(count: totals.count, seconds: totals.seconds)
        }
        .padding(.horizontal, 12).padding(.top, 8)
        .overlay(Divider().overlay(Color.dsHairline), alignment: .top)
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.white.opacity(0.25))
                Text("No focus logged this day.")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
        }
        .padding(.vertical, 60)
    }
}
