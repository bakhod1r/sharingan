import SwiftUI
import SharinganCore

/// A Teamup-style project timeline: rows are groups (Project / Category / each
/// Task), and every task is a bar laid across a horizontal date axis from its
/// planned date to its due date. Bars in the same group are lane-packed so
/// overlapping work stacks instead of colliding.
///
/// Shares the Tasks list's sort preference (`tasks.sortMode`) and the same
/// one-dimension filter (category / tag / priority) as the other boards.
struct TimelineBoardView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var store = TaskStore.shared

    /// How to bucket tasks into rows.
    enum Grouping: String, CaseIterable, Identifiable {
        case project, category, task
        var id: String { rawValue }
        var title: String {
            switch self {
            case .project:  return "Project"
            case .category: return "Category"
            case .task:     return "Task"
            }
        }
    }

    /// How many days the axis spans at once.
    enum Range: String, CaseIterable, Identifiable {
        case week, twoWeeks, month
        var id: String { rawValue }
        var days: Int { self == .week ? 7 : (self == .twoWeeks ? 14 : 30) }
        var title: String {
            switch self {
            case .week:     return "Week"
            case .twoWeeks: return "2 Weeks"
            case .month:    return "Month"
            }
        }
    }

    @AppStorage("board.timeline.grouping") private var groupingRaw = Grouping.project.rawValue
    private var grouping: Grouping { Grouping(rawValue: groupingRaw) ?? .project }

    @AppStorage("board.timeline.range") private var rangeRaw = Range.twoWeeks.rawValue
    private var range: Range { Range(rawValue: rangeRaw) ?? .twoWeeks }

    /// Whole-range steps away from today (0 = the range that contains today).
    @State private var rangeOffset = 0
    @State private var editorTask: TaskItem?
    @State private var hoveredTask: UUID?

    /// Shared sort order across every board.
    @AppStorage("tasks.sortMode") private var sortModeRaw = TaskSortMode.manual.rawValue
    private var sortMode: TaskSortMode { TaskSortMode(rawValue: sortModeRaw) ?? .manual }

    /// One-dimension narrowing, matching the other boards.
    @State private var categoryFilter: String?
    @State private var tagFilter: String?
    @State private var priorityFilter: TaskPriority?
    private var isNarrowed: Bool {
        categoryFilter != nil || tagFilter != nil || priorityFilter != nil
    }

    private let labelWidth: CGFloat = 156
    private let dayWidth: CGFloat = 46
    private let laneHeight: CGFloat = 30
    private let rowPadding: CGFloat = 8
    private var accent: Color { timer.settings.theme.accent }
    private var cal: Calendar { Calendar.current }

    // MARK: - Date axis

    /// First day shown — today's range start, shifted by the offset.
    private var rangeStart: Date {
        let today = cal.startOfDay(for: Date())
        // Anchor the base range on today; step by whole ranges.
        let anchored = cal.date(byAdding: .day, value: rangeOffset * range.days, to: today) ?? today
        return cal.startOfDay(for: anchored)
    }

    private var days: [Date] {
        (0..<range.days).compactMap { cal.date(byAdding: .day, value: $0, to: rangeStart) }
    }

    private var rangeEnd: Date { days.last ?? rangeStart }

    private func dayIndex(_ date: Date) -> Int {
        cal.dateComponents([.day], from: rangeStart, to: cal.startOfDay(for: date)).day ?? 0
    }

    // MARK: - Task span

    /// A task's [start, end] on the day axis: planned→due, falling back to
    /// whichever single date exists. `nil` when the task carries no date at all.
    private func span(_ t: TaskItem) -> (start: Date, end: Date)? {
        let dates = [t.plannedDate, t.dueDate].compactMap { $0 }.map { cal.startOfDay(for: $0) }
        guard let lo = dates.min(), let hi = dates.max() else { return nil }
        return (lo, hi)
    }

    /// Tasks eligible for the timeline: live, open-or-recent, filtered, dated,
    /// and touching the visible window.
    private var visibleTasks: [TaskItem] {
        let base = store.tasks.filter { !$0.isTrashed }
        let narrowed = narrowTasks(base, category: categoryFilter, tag: tagFilter,
                                   priority: priorityFilter)
        return narrowed.filter { t in
            guard let s = span(t) else { return false }
            return s.end >= rangeStart && s.start <= rangeEnd
        }
    }

    private var undatedCount: Int {
        let base = narrowTasks(store.tasks.filter { !$0.isTrashed },
                               category: categoryFilter, tag: tagFilter, priority: priorityFilter)
        return base.filter { span($0) == nil && !$0.isDone }.count
    }

    // MARK: - Grouping

    private struct Group: Identifiable {
        let id: String
        let title: String
        let colorHex: String
        var lanes: [[TaskItem]]   // lane-packed rows of bars
        var height: CGFloat
    }

    private var groups: [Group] {
        let tasks = visibleTasks
        // Bucket by the chosen dimension.
        var buckets: [(key: String, title: String, colorHex: String, items: [TaskItem])] = []
        func bucketIndex(key: String, title: String, colorHex: String) -> Int {
            if let i = buckets.firstIndex(where: { $0.key == key }) { return i }
            buckets.append((key, title, colorHex, [])); return buckets.count - 1
        }
        for t in tasks.sorted(by: sortMode.inOrder) {
            switch grouping {
            case .project:
                let name = t.project ?? "No project"
                let i = bucketIndex(key: "p:\(name)", title: name, colorHex: store.projectColor(name))
                buckets[i].items.append(t)
            case .category:
                let i = bucketIndex(key: "c:\(t.category)", title: t.category, colorHex: store.color(for: t.category))
                buckets[i].items.append(t)
            case .task:
                let i = bucketIndex(key: "t:\(t.id.uuidString)", title: t.title,
                                    colorHex: store.color(for: t.category))
                buckets[i].items.append(t)
            }
        }
        return buckets.map { b in
            let lanes = packLanes(b.items)
            let height = CGFloat(max(1, lanes.count)) * laneHeight + rowPadding * 2
            return Group(id: b.key, title: b.title, colorHex: b.colorHex, lanes: lanes, height: height)
        }
    }

    /// Greedy interval packing: each task takes the first lane whose last bar
    /// ends before it starts, so bars never overlap within a group.
    private func packLanes(_ items: [TaskItem]) -> [[TaskItem]] {
        let sorted = items.sorted { (span($0)?.start ?? .distantPast) < (span($1)?.start ?? .distantPast) }
        var lanes: [[TaskItem]] = []
        var laneEnds: [Date] = []
        for t in sorted {
            guard let s = span(t) else { continue }
            if let lane = laneEnds.firstIndex(where: { $0 < s.start }) {
                lanes[lane].append(t); laneEnds[lane] = s.end
            } else {
                lanes.append([t]); laneEnds.append(s.end)
            }
        }
        return lanes
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if visibleTasks.isEmpty {
                emptyState
            } else {
                chart
            }
            if undatedCount > 0 {
                Label("\(undatedCount) task\(undatedCount == 1 ? "" : "s") without a plan or due date aren't shown — set a date to place them on the timeline.",
                      systemImage: "calendar.badge.exclamationmark")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.dsSecondary)
            }
        }
        .sheet(item: $editorTask) { task in
            TaskEditorView(task: task, accent: accent, settings: timer.settings)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Timeline")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                Text(rangeLabel)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .contentTransition(.opacity)
            }
            Spacer()
            groupingControl
            rangeControl
            navControls
            filterMenu
            sortMenu
        }
    }

    private var rangeLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d"
        return "\(f.string(from: rangeStart)) – \(f.string(from: rangeEnd))"
    }

    private var groupingControl: some View {
        Menu {
            ForEach(Grouping.allCases) { g in
                Button {
                    withAnimation(DS.Motion.gentle) { groupingRaw = g.rawValue }
                } label: {
                    Label(g.title, systemImage: grouping == g ? "checkmark" : groupIcon(g))
                }
            }
        } label: {
            pill(icon: "square.stack.3d.up", text: grouping.title)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Group timeline rows")
    }

    private func groupIcon(_ g: Grouping) -> String {
        switch g {
        case .project:  return "folder"
        case .category: return "tag"
        case .task:     return "checklist"
        }
    }

    private var rangeControl: some View {
        Menu {
            ForEach(Range.allCases) { r in
                Button {
                    withAnimation(DS.Motion.gentle) { rangeRaw = r.rawValue }
                } label: {
                    Label(r.title, systemImage: range == r ? "checkmark" : "calendar")
                }
            }
        } label: {
            pill(icon: "calendar", text: range.title)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Timeline range")
    }

    private var navControls: some View {
        HStack(spacing: 4) {
            circleButton("chevron.left") { withAnimation(DS.Motion.standard) { rangeOffset -= 1 } }
            Button {
                withAnimation(DS.Motion.standard) { rangeOffset = 0 }
            } label: {
                Text("Today")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(rangeOffset == 0 ? .white.opacity(0.4) : .white)
                    .padding(.horizontal, 10).frame(height: 28)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .disabled(rangeOffset == 0)
            circleButton("chevron.right") { withAnimation(DS.Motion.standard) { rangeOffset += 1 } }
        }
    }

    private var filterMenu: some View {
        Menu {
            TaskFilterMenuItems(store: store, settings: timer.settings,
                                categoryFilter: $categoryFilter,
                                tagFilter: $tagFilter,
                                priorityFilter: $priorityFilter)
        } label: {
            circleIcon("line.3.horizontal.decrease.circle", active: isNarrowed)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help(isNarrowed ? "Filtered" : "Filter tasks")
    }

    private var sortMenu: some View {
        Menu {
            TaskSortMenuItems(sortModeRaw: $sortModeRaw)
        } label: {
            circleIcon("arrow.up.arrow.down", active: sortMode != .manual)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help(sortMode == .manual ? "Sort tasks" : "Sorted by \(sortMode.label)")
    }

    // MARK: - Chart

    private var chart: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                axisHeader
                ForEach(groups) { group in
                    groupRow(group)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
            .fill(Color.white.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
            .stroke(Color.white.opacity(0.07), lineWidth: 1))
    }

    /// The sticky-feeling top row: a spacer over the label gutter, then one
    /// column head per day (weekday + date, today highlighted).
    private var axisHeader: some View {
        HStack(spacing: 0) {
            Text(grouping.title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: labelWidth, alignment: .leading)
                .padding(.leading, 14)
            ForEach(days, id: \.self) { day in
                let isToday = cal.isDateInToday(day)
                let isWeekend = cal.isDateInWeekend(day)
                VStack(spacing: 1) {
                    Text(weekday(day))
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(dayNum(day))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(isToday ? accent : .white.opacity(isWeekend ? 0.45 : 0.85))
                }
                .frame(width: dayWidth, height: 40)
                .background(isToday ? accent.opacity(0.12) : (isWeekend ? Color.white.opacity(0.02) : .clear))
            }
        }
        .frame(height: 44)
        .background(Color.white.opacity(0.04))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
    }

    private func groupRow(_ group: Group) -> some View {
        HStack(spacing: 0) {
            // Row label gutter.
            HStack(spacing: 8) {
                Circle().fill(Color(hex: group.colorHex)).frame(width: 8, height: 8)
                Text(group.title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(group.lanes.reduce(0) { $0 + $1.count })")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .frame(width: labelWidth, height: group.height, alignment: .leading)

            // Bars area, with day gridlines behind.
            ZStack(alignment: .topLeading) {
                gridlines
                ForEach(Array(group.lanes.enumerated()), id: \.offset) { laneIdx, lane in
                    ForEach(lane) { task in
                        bar(task, lane: laneIdx)
                    }
                }
            }
            .frame(width: CGFloat(days.count) * dayWidth, height: group.height, alignment: .topLeading)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
        }
    }

    private var gridlines: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                Rectangle()
                    .fill(cal.isDateInToday(day) ? accent.opacity(0.06)
                          : (cal.isDateInWeekend(day) ? Color.white.opacity(0.02) : .clear))
                    .frame(width: dayWidth)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Color.white.opacity(0.04)).frame(width: 1)
                    }
            }
        }
    }

    private func bar(_ task: TaskItem, lane: Int) -> some View {
        guard let s = span(task) else { return AnyView(EmptyView()) }
        // Clamp the span to the visible window.
        let startIdx = max(0, dayIndex(s.start))
        let endIdx = min(days.count - 1, dayIndex(s.end))
        let width = max(1, CGFloat(endIdx - startIdx + 1)) * dayWidth - 6
        let x = CGFloat(startIdx) * dayWidth + 3
        let y = CGFloat(lane) * laneHeight + rowPadding
        let color = Color(hex: store.color(for: task.category))
        let hovered = hoveredTask == task.id
        let overdue = task.isOverdue()

        return AnyView(
            HStack(spacing: 5) {
                if task.priority != .none, let hex = timer.settings.priorityColorHex(task.priority) {
                    Circle().fill(Color(hex: hex)).frame(width: 6, height: 6)
                }
                Text(task.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(task.isDone ? .white.opacity(0.6) : .white)
                    .strikethrough(task.isDone, color: .white.opacity(0.5))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(width: width, height: laneHeight - 8, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .fill(LinearGradient(colors: [color.opacity(task.isDone ? 0.35 : 0.9),
                                                  color.opacity(task.isDone ? 0.25 : 0.65)],
                                         startPoint: .leading, endPoint: .trailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .stroke(overdue && !task.isDone ? Color.red.opacity(0.9) : Color.white.opacity(0.18),
                            lineWidth: overdue && !task.isDone ? 1.5 : 1)
            )
            .shadow(color: .black.opacity(hovered ? 0.3 : 0.15), radius: hovered ? 8 : 3, y: 2)
            .scaleEffect(hovered ? 1.02 : 1, anchor: .leading)
            .animation(DS.Motion.hover, value: hovered)
            .offset(x: x, y: y)
            .contentShape(Rectangle())
            .onHover { hoveredTask = $0 ? task.id : (hoveredTask == task.id ? nil : hoveredTask) }
            .onTapGesture { editorTask = task }
            .help(barTooltip(task, s))
        )
    }

    private func barTooltip(_ task: TaskItem, _ s: (start: Date, end: Date)) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d"
        let range = cal.isDate(s.start, inSameDayAs: s.end)
            ? f.string(from: s.start)
            : "\(f.string(from: s.start)) → \(f.string(from: s.end))"
        return "\(task.title)\n\(range)"
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Color.dsTertiary)
            Text(isNarrowed
                 ? "No tasks match the filter in this range."
                 : "No dated tasks in this range. Give a task a plan or due date to see it here.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.dsSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    // MARK: - Small controls

    private func pill(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(text).font(.system(.caption, design: .rounded).weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10).frame(height: 28)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    private func circleButton(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { circleIcon(name, active: false) }
            .buttonStyle(.plain)
    }

    private func circleIcon(_ name: String, active: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(active ? accent : .white)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color.white.opacity(0.08)))
            .contentShape(Circle())
    }

    private func weekday(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "EEE"
        return f.string(from: d).uppercased()
    }
    private func dayNum(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "d"
        return f.string(from: d)
    }
}
