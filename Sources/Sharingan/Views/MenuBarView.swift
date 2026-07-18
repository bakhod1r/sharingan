import SwiftUI
import AppKit
import SharinganCore

struct MenuBarView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var tasks = TaskStore.shared
    @State private var tab: Tab = .timer
    @State private var quickTitle = ""
    /// Categories whose accordion section is collapsed.
    @State private var collapsedCategories: Set<String> = []
    /// Task currently being renamed inline, and its working text.
    @State private var editingTaskID: UUID?
    @State private var editingText = ""
    @FocusState private var editFieldFocused: Bool
    /// Drives the gentle running-state pulse on the Start button.
    @State private var heartbeat = false
    @State private var taskSearch = ""
    @State private var todayOnly = false
    /// Tasks whose subtask/notes panel is expanded in the popover.
    @State private var expandedTasks: Set<UUID> = []
    @State private var subtaskDrafts: [UUID: String] = [:]
    @State private var showCompleted = false
    /// Row the pointer is over — reveals its delete button.
    @State private var hoveredTask: UUID?
    /// Task open in the full editor sheet (nil = closed).
    @State private var editorTask: TaskItem?
    /// Task queued for the "move to Trash?" confirmation (nil = no prompt).
    @State private var pendingDeleteTask: TaskItem?
    @State private var showTrash = false
    /// Task queued for the irreversible "delete forever?" confirmation.
    @State private var pendingPurgeTask: TaskItem?
    @State private var confirmEmptyTrash = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Tab: Hashable, CaseIterable {
        // Pomodoro and Tasks are one tab now: the full task view with the timer
        // controls pinned below it.
        case timer, week, report

        var title: String {
            switch self {
            case .timer: return "Tasks"
            case .week: return "Week"
            case .report: return "Report"
            }
        }
        var icon: String {
            switch self {
            case .timer: return "checklist"
            case .week: return "calendar"
            case .report: return "list.bullet.rectangle"
            }
        }
    }
    @Namespace private var tabPillNS

    /// Fixed height for the switchable tab area so the popover keeps one height
    /// across tabs. Sized to fit the timer tab's controls (the stats strip is
    /// pinned separately below); a very long task list scrolls within.
    private let tabContentHeight: CGFloat = 560

    /// Outer popover padding — also part of the Week-tab width math below, so
    /// tweaking one can't silently clip the board.
    private static let outerPadding: CGFloat = 18

    /// Popover width for every tab except Week. The task rows carry a dense
    /// trailing cluster (estimate badge, chevron, hover actions, Focus button)
    /// plus the composer's filter row; 360 pt clipped both edges, so the
    /// content sets the floor here.
    private static let standardWidth: CGFloat = 420

    /// Week-tab popover width: the full 8-column board plus padding, capped to
    /// the current screen so narrow displays keep every column reachable via
    /// the board's own horizontal scroll.
    private static var weekPopoverWidth: CGFloat {
        let ideal = MenuBarWeekView.boardWidth + outerPadding * 2
        let screen = (NSScreen.main?.visibleFrame.width ?? 1440) - 40
        return min(ideal, screen)
    }

    var body: some View {
        VStack(spacing: 14) {
            // Capped so the Week tab's wider popover doesn't stretch the tab
            // bar edge-to-edge — it stays a compact, centered control like
            // the rest of the chrome, while the board below manages its own
            // full-bleed horizontal scroll.
            liquidGlassTabBar
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)

            // Fixed-height area so switching Timer ↔ Tasks never resizes the
            // popover. Content is top-aligned; an over-long list scrolls within.
            // On the Timer tab the controls are pinned BELOW the scroll — only
            // the plan (goal bar + tasks) scrolls — so Start / Skip / +5m can
            // never be pushed out of sight by a long list. (The old phase +
            // countdown header is gone: the menu bar and Floating widget already
            // show the time; tasks get the space instead.)
            VStack(spacing: 14) {
                ScrollView(.vertical, showsIndicators: false) {
                    Group {
                        switch tab {
                        case .timer:  TasksView(timer: timer)
                        case .week:   MenuBarWeekView(timer: timer)
                        case .report: ReportView(timer: timer)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                // Overflowing content dissolves at the bottom edge instead of
                // being sliced mid-row — and the fade hints there's more to
                // scroll. No-op when the content fits.
                .mask(
                    VStack(spacing: 0) {
                        Rectangle()
                        LinearGradient(colors: [.black, .clear],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 26)
                    }
                )
                if tab == .timer {
                    // Same width envelope as the tab bar and stats strip so the
                    // controls line up with the rest of the popover chrome.
                    controls
                        .frame(maxWidth: 640)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: tabContentHeight)

            // Today / Cycle / Streak + Sync / Settings / Quit — one row, pinned
            // below the scroll so it's always fully visible on both tabs,
            // never clipped by the fixed height.
            Divider().overlay(Color.dsHairline).frame(maxWidth: 640).frame(maxWidth: .infinity)
            footer
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
        }
        .onAppear { heartbeat = true }
        .padding(Self.outerPadding)
        // The Week tab widens the popover to fit the full board (backlog +
        // 7 day columns); NSHostingController tracks preferredContentSize, so
        // the popover follows this frame automatically. Capped to the screen —
        // when it can't fit, the board's horizontal scroll takes over.
        .frame(width: tab == .week ? Self.weekPopoverWidth : Self.standardWidth)
        .animation(DS.Motion.standard, value: tab)
        // One app accent: controls follow the chosen theme, not system blue.
        .tint(timer.settings.theme.accent)
        .sheet(item: $editorTask) { task in
            TaskEditorView(task: task,
                           accent: timer.settings.theme.accent,
                           settings: timer.settings)
        }
        .alert("Delete this task?", isPresented: Binding(
            get: { pendingDeleteTask != nil },
            set: { if !$0 { pendingDeleteTask = nil } })) {
            Button("Move to Trash", role: .destructive) {
                if let t = pendingDeleteTask { tasks.delete(t.id) }
                pendingDeleteTask = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteTask = nil }
        } message: {
            Text(pendingDeleteTask.map { "“\($0.title)” moves to Trash — restore it from the Tasks tab." } ?? "")
        }
        .alert("Delete forever?", isPresented: Binding(
            get: { pendingPurgeTask != nil },
            set: { if !$0 { pendingPurgeTask = nil } })) {
            Button("Delete forever", role: .destructive) {
                if let t = pendingPurgeTask { withAnimation { tasks.deletePermanently(t.id) } }
                pendingPurgeTask = nil
            }
            Button("Cancel", role: .cancel) { pendingPurgeTask = nil }
        } message: {
            Text(pendingPurgeTask.map { "“\($0.title)” will be gone for good. This can't be undone." } ?? "")
        }
        .alert("Empty Trash?", isPresented: $confirmEmptyTrash) {
            Button("Delete \(tasks.trashedTasks.count) forever", role: .destructive) {
                withAnimation { tasks.emptyTrash() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let n = tasks.trashedTasks.count
            Text("This permanently deletes \(n) task\(n == 1 ? "" : "s") in the Trash.")
        }
    }

    /// Liquid-glass tab bar — a translucent capsule track with a floating
    /// glass pill that glides to the selected tab, replacing the flat
    /// `.segmented` picker with the same material language as the rest of
    /// the popover's glass surfaces.
    private var liquidGlassTabBar: some View {
        let segment = RoundedRectangle(cornerRadius: 9, style: .continuous)
        let tabs = Tab.allCases
        return HStack(spacing: 2) {
            ForEach(Array(tabs.enumerated()), id: \.element) { idx, t in
                let selected = tab == t
                // Hairline separator between two *unselected* neighbours — the
                // macOS segmented look in the reference. It vanishes next to the
                // accent pill so the pill never butts against a line.
                if idx > 0 {
                    let prevSelected = tab == tabs[idx - 1]
                    Rectangle()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: 1, height: 16)
                        .opacity(selected || prevSelected ? 0 : 1)
                        .animation(DS.Motion.standard, value: tab)
                }
                Button {
                    withAnimation(DS.Motion.standard) { tab = t }
                } label: {
                    Label(t.title, systemImage: t.icon)
                        .font(.system(.callout, design: .rounded).weight(selected ? .semibold : .medium))
                        .foregroundStyle(selected ? .white : .white.opacity(0.6))
                        .labelStyle(.titleOnly)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if selected {
                                let accent = timer.settings.theme.accent
                                // Flat, clean accent pill — matches the reference:
                                // no glossy white sheen, no coloured glow. A barely
                                // there top-to-bottom gradient keeps it from reading
                                // dull, a hairline border defines the edge, and a
                                // soft neutral drop shadow gives just enough lift.
                                segment
                                    .fill(LinearGradient(colors: [accent, accent.opacity(0.92)],
                                                          startPoint: .top, endPoint: .bottom))
                                    .overlay(segment.stroke(Color.white.opacity(0.12), lineWidth: 1))
                                    .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
                                    .matchedGeometryEffect(id: "tabPill", in: tabPillNS)
                            }
                        }
                        .contentShape(segment)
                }
                .buttonStyle(.pressableSubtle)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1))
        )
    }

    // MARK: - Tabs

    private var timerTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            StreakRewardBanner(center: StreakRewardCenter.shared)
            dailyGoalBar
            // Task list is the primary plan — it sits at the very top so the
            // user's added todos are the first thing shown. The pomodoro
            // controls are pinned below the scroll (see `body`).
            taskList
        }
    }

    /// Today's pomodoro goal as a slim progress bar (hidden when goal is 0).
    @ViewBuilder
    private var dailyGoalBar: some View {
        let goal = timer.settings.dailyPomodoroGoal
        if goal > 0 {
            let done = timer.stats.completedTodayCount()
            let frac = min(1, Double(done) / Double(goal))
            VStack(spacing: 4) {
                HStack {
                    Text("Today's goal")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(done)/\(goal) 🍅")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(done >= goal ? Color.green : .secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(done >= goal
                                  ? AnyShapeStyle(Color.green)
                                  : AnyShapeStyle(LinearGradient(
                                        colors: [.paletteFocusStart, .paletteBreakStart],
                                        startPoint: .leading, endPoint: .trailing)))
                            .frame(width: max(4, geo.size.width * frac))
                    }
                }
                .frame(height: 6)
                .animation(DS.Motion.gentle, value: frac)
            }
        }
    }

    // MARK: - Inline task list

    /// Search field + a "Today" toggle for the inline task list.
    private var filterRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("Search", text: $taskSearch)
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .rounded))
                if !taskSearch.isEmpty {
                    Button { taskSearch = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.pressableSubtle)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.06)))

            Button { todayOnly.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sun.max.fill").font(.system(size: 10, weight: .bold))
                    Text("Today").font(.system(.caption2, design: .rounded).weight(.semibold))
                }
                .foregroundStyle(todayOnly ? Color.orange : .secondary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(todayOnly ? Color.orange.opacity(0.18)
                                                     : Color.white.opacity(0.06)))
            }
            .buttonStyle(.pressableSubtle)
        }
    }

    /// All open tasks (ignoring search/today filters) — used to decide whether to
    /// show the filter controls.
    private var allOpenCount: Int { tasks.tasks.filter { !$0.isDone && $0.trashedAt == nil }.count }

    /// All open tasks, active-on-top then manual order, IGNORING the search /
    /// Today filters — used by Start so a filter that hides every row doesn't
    /// disable a perfectly startable timer or change which task Start launches.
    private var allOpenTasks: [TaskItem] {
        tasks.tasks.filter { !$0.isDone && $0.trashedAt == nil }.sorted { a, b in
            if (tasks.activeTaskID == a.id) != (tasks.activeTaskID == b.id) {
                return tasks.activeTaskID == a.id
            }
            return TaskStore.inListOrder(a, b)
        }
    }

    /// Open (unfinished) tasks after search + today filters, the active one on top,
    /// then manual order.
    private var openTasks: [TaskItem] {
        var list = tasks.tasks.filter { !$0.isDone && $0.trashedAt == nil }
        let q = taskSearch.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.title.lowercased().contains(q)
                    || $0.category.lowercased().contains(q)
                    || $0.tags.contains { $0.lowercased().contains(q) }
            }
        }
        if todayOnly { list = list.filter { $0.isPlannedToday() } }
        return list.sorted { a, b in
            if (tasks.activeTaskID == a.id) != (tasks.activeTaskID == b.id) {
                return tasks.activeTaskID == a.id
            }
            return TaskStore.inListOrder(a, b)
        }
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Quick add
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.tint)
                TextField("Add a task…", text: $quickTitle)
                    .textFieldStyle(.plain)
                    .font(.system(.callout, design: .rounded))
                    .onSubmit(quickAdd)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .glassCapsule(material: .thin)

            // Search + Today filter — only once the list is big enough to need it.
            if allOpenCount > 4 || todayOnly || !taskSearch.isEmpty {
                filterRow
            }

            if openTasks.isEmpty {
                HStack {
                    Spacer()
                    Text(taskSearch.isEmpty && !todayOnly
                         ? "No tasks yet — add one above"
                         : "No matching tasks")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 10)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(groupedOpen, id: \.category) { group in
                            categorySection(group)
                        }
                    }
                    .padding(.vertical, 1)
                    .animation(DS.Motion.standard,
                               value: groupedOpen.map(\.category))
                }
                // Size to the actual content (headers + expanded rows) so a short
                // list doesn't claim 300pt and shove the timer off-screen; only
                // taller lists scroll.
                .frame(height: taskListHeight)
            }
            // Completed and Trash live in the Tasks tab — the Pomodoro tab shows
            // only the active/open list so the timer stays front and centre.
        }
    }

    /// Shared header for the collapsible Completed / Trash buckets, so both read
    /// as one consistent, quietly styled disclosure row: tinted icon, label,
    /// count pill, a chevron that turns on expand, and an optional trailing
    /// action — all sitting on a soft rounded fill that deepens when open.
    @ViewBuilder
    private func bucketHeader<Trailing: View>(
        icon: String, label: String, count: Int, tint: Color, isOpen: Bool,
        toggle: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(DS.Motion.gentle) { toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.dsTertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 15)
                    Text(label).dsSectionLabel()
                    Text("\(count)")
                        .font(.system(.caption2, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.dsSecondary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.dsFill))
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressableSubtle)
            trailing()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.dsFill.opacity(isOpen ? 0.6 : 0.3))
        )
    }

    /// Collapsible Trash bucket for the Pomodoro tab's inline list — the same
    /// bucket the Tasks tab shows, so a task deleted from either place can be
    /// recovered without switching tabs. Hidden when the Trash is empty.
    @ViewBuilder
    private var trashSection: some View {
        let trashed = tasks.trashedTasks
        if !trashed.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                bucketHeader(icon: "trash", label: "Trash", count: trashed.count,
                             tint: Color.red.opacity(0.8), isOpen: showTrash,
                             toggle: { showTrash.toggle() }) {
                    if showTrash {
                        Button { confirmEmptyTrash = true } label: {
                            Text("Empty")
                                .font(.system(.caption2, design: .rounded).weight(.semibold))
                                .foregroundStyle(Color.red.opacity(0.85))
                                .padding(.horizontal, 8).padding(.vertical, 5)
                        }
                        .buttonStyle(.pressableSubtle)
                        .help("Delete every trashed task permanently")
                    }
                }

                if showTrash {
                    ForEach(trashed) { task in
                        HStack(spacing: 10) {
                            Text(task.title)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Button {
                                withAnimation(DS.Motion.standard) { tasks.restore(task.id) }
                            } label: {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22, height: 22)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.pressableSubtle)
                            .help("Restore this task")
                            .accessibilityLabel("Restore \(task.title)")
                            Button { pendingPurgeTask = task } label: {
                                Image(systemName: "trash.slash")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.red.opacity(0.75))
                                    .frame(width: 22, height: 22)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.pressableSubtle)
                            .help("Delete permanently")
                            .accessibilityLabel("Delete \(task.title) permanently")
                        }
                        .padding(.horizontal, 10).padding(.vertical, 4)
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    /// Collapsible list of completed tasks with one-tap un-complete (undo).
    @ViewBuilder
    private var completedSection: some View {
        let done = tasks.tasks.filter { $0.isDone && $0.trashedAt == nil }
            .sorted { $0.createdAt > $1.createdAt }
        if !done.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                bucketHeader(icon: "checkmark.circle.fill", label: "Completed",
                             count: done.count, tint: .green, isOpen: showCompleted,
                             toggle: { showCompleted.toggle() })

                if showCompleted {
                    ForEach(done.prefix(8)) { task in
                        HStack(spacing: 10) {
                            Button { tasks.toggleDone(task.id) } label: {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.green)
                            }
                            .buttonStyle(.pressableSubtle)
                            .help("Mark not done")
                            Text(task.title)
                                .font(.system(.caption, design: .rounded))
                                .strikethrough(true, color: .secondary)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Button { tasks.delete(task.id) } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22, height: 22)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.pressableSubtle)
                            .help("Delete")
                        }
                        .padding(.horizontal, 10).padding(.vertical, 4)
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    /// Height that fits the visible accordion content (section headers + rows of
    /// expanded categories), capped so long lists scroll instead of growing.
    private var taskListHeight: CGFloat {
        var h: CGFloat = 0
        for group in groupedOpen {
            h += 30   // category header row
            if !collapsedCategories.contains(group.category) {
                h += CGFloat(group.items.count) * 48 + 6
                // Expanded rows reveal a subtask/notes panel below them — grow the
                // frame so opening one doesn't just push it into the scroll region.
                for item in group.items where expandedTasks.contains(item.id) {
                    h += CGFloat(item.subtasks.count) * 24 + 34   // steps + add field
                    if !item.notes.isEmpty { h += 30 }
                }
            }
        }
        return min(max(h, 40), 360)
    }

    /// Open tasks grouped by category, in the app's category order.
    private var groupedOpen: [(category: String, color: String, items: [TaskItem])] {
        let order = tasks.allCategories.map(\.name)
        let byCat = Dictionary(grouping: openTasks, by: { $0.category })
        return byCat.keys
            // Secondary key on the name keeps ordering stable for categories not
            // in `allCategories` (both map to .max otherwise → reshuffle).
            .sorted { (order.firstIndex(of: $0) ?? .max, $0) < (order.firstIndex(of: $1) ?? .max, $1) }
            .map { name in (name, tasks.color(for: name), byCat[name] ?? []) }
    }

    /// One collapsible accordion section for a category.
    @ViewBuilder
    private func categorySection(_ group: (category: String, color: String, items: [TaskItem])) -> some View {
        let accent = Color(hex: group.color)
        let isCollapsed = collapsedCategories.contains(group.category)
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(DS.Motion.gentle) {
                    if isCollapsed { collapsedCategories.remove(group.category) }
                    else { collapsedCategories.insert(group.category) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.dsTertiary)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    CategoryGlyph(symbol: tasks.icon(for: group.category), color: accent, size: 11)
                    Text(group.category).dsSectionLabel()
                    Text("\(group.items.count)")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.dsTertiary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.dsFill))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressableSubtle)
            .contextMenu {
                Menu {
                    ForEach(TaskCategory.iconChoices, id: \.self) { symbol in
                        Button {
                            tasks.setIcon(for: group.category, icon: symbol)
                        } label: {
                            Label(symbol, systemImage: symbol)
                        }
                    }
                } label: {
                    Label("Change icon", systemImage: "star")
                }
                Menu {
                    ForEach(TaskCategory.palette, id: \.self) { hex in
                        Button {
                            tasks.setColor(for: group.category, colorHex: hex)
                        } label: {
                            Label(hex, systemImage: "circle.fill")
                        }
                    }
                } label: {
                    Label("Change color", systemImage: "paintpalette")
                }
            }

            if !isCollapsed {
                VStack(spacing: 6) {
                    ForEach(group.items) { task in
                        VStack(spacing: 4) {
                            miniRow(task, showCategory: false)
                            if expandedTasks.contains(task.id) {
                                subtaskPanel(task)
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity.combined(with: .scale(scale: 0.9))))
                    }
                }
                .animation(DS.Motion.standard,
                           value: group.items.map(\.id))
            }
        }
    }

    private func miniRow(_ task: TaskItem, showCategory: Bool = true) -> some View {
        let isActive = tasks.activeTaskID == task.id
        let accent = Color(hex: tasks.color(for: task.category))
        return HStack(spacing: 8) {
            Button {
                tasks.toggleDone(task.id)
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.pressableSubtle)

            if editingTaskID == task.id {
                TextField("Task name", text: $editingText)
                    .textFieldStyle(.plain)
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .focused($editFieldFocused)
                    .onSubmit { commitEdit(task) }
                    .onExitCommand { editingTaskID = nil; editFieldFocused = false }
                    .onAppear { editFieldFocused = true }
                Spacer(minLength: 6)
            } else {
                // Code leads the row (fixed, tiny); the title takes all the room
                // it can before the decoration ladder.
                if let code = task.code {
                    Text(code)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.dsTertiary)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .fixedSize()
                        .help("Task code — shown in the notch while focusing")
                }

                Text(task.title)
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .lineLimit(1)
                    // Keep the title legible: sized before the chip ladder, so
                    // chips yield width first. Without this the stack offers
                    // the title an equal share and a long title truncates to a
                    // few characters even while the Spacer holds free width.
                    .layoutPriority(1)

                Spacer(minLength: 6)
            }

            // Decorations — one ladder, widest tier that fits. Every tier is
            // fixed-size, so a tier either renders whole or the next (leaner)
            // one is used: chips drop first, then the due date, then the
            // small state icons. Decorations used to compress in place
            // instead: empty crushed capsules and count labels wrapped onto
            // two overlapping lines once a task carried enough metadata.
            if editingTaskID != task.id {
                ViewThatFits(in: .horizontal) {
                    miniMeta(task, accent: accent, category: showCategory, tags: 2, due: true)
                    miniMeta(task, accent: accent, category: false, tags: 0, due: true)
                    miniMeta(task, accent: accent, category: false, tags: 0, due: false)
                    Color.clear.frame(width: 0, height: 0)
                }

                // Step + pomodoro progress — never dropped and never squashed
                // (`fixedSize`): on a long title the title truncates instead,
                // like every task app's row. The title still can't be starved
                // below the leftover the fixed cluster leaves it.
                if task.subtaskProgress.total > 0 {
                    SubtaskProgressBadge(task.subtaskProgress)
                        .fixedSize()
                }
            }

            // Every secondary action, subtasks/notes included, lives in this ⋮
            // menu — the chevron used to sit here and cost the title width.
            Menu {
                taskMenuItems(task)
            } label: {
                // U+22EE text, not drawn dots — see the note in TasksView.rowMenu.
                Text("⋮")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.dsSecondary)
                    .frame(width: 16, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More actions")

            // Merged focus control: the pomodoro ring and the play/pause button
            // sit in one capsule so they read as a single unit — the task's
            // tomato count and the control that runs a pomodoro on it.
            HStack(spacing: 3) {
                if editingTaskID != task.id {
                    pomodoroBadge(task).fixedSize()
                }
                Button {
                    startFocus(on: task)
                } label: {
                    Image(systemName: isActive && timer.isRunning
                          ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(isActive ? Color.accentColor : .secondary)
                }
                .buttonStyle(.pressableSubtle)
                .help("Run a focus pomodoro on this task")
            }
            .padding(.horizontal, 4).padding(.vertical, 2)
            .background(Capsule().fill(Color.white.opacity(0.06)))
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(isActive ? accent.opacity(0.16)
                      : (hoveredTask == task.id ? Color.dsFillStrong : Color.dsFill))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(isActive ? accent.opacity(0.5) : .clear, lineWidth: 1)
        )
        .animation(DS.Motion.hover, value: hoveredTask)
        .onHover { inside in
            if inside { hoveredTask = task.id }
            else if hoveredTask == task.id { hoveredTask = nil }
        }
        .contextMenu { taskMenuItems(task) }
    }

    /// The full task action menu — shared by the row's right-click context menu
    /// and its ⋮ overflow button so both offer identical actions.
    @ViewBuilder
    private func taskMenuItems(_ task: TaskItem) -> some View {
            // The chevron's old job, now that the row no longer carries one.
            if task.subtaskProgress.total > 0 || !task.notes.isEmpty {
                Button {
                    withAnimation(DS.Motion.gentle) {
                        if expandedTasks.contains(task.id) { expandedTasks.remove(task.id) }
                        else { expandedTasks.insert(task.id) }
                    }
                } label: {
                    Label(expandedTasks.contains(task.id) ? "Hide subtasks & notes"
                                                          : "Subtasks & notes",
                          systemImage: "list.bullet.indent")
                }
                Divider()
            }
            Button { editorTask = task } label: {
                Label("Edit…", systemImage: "pencil")
            }
            Button {
                editingText = task.title
                editingTaskID = task.id
            } label: {
                Label("Rename", systemImage: "character.cursor.ibeam")
            }
            Menu {
                ForEach(tasks.allCategories) { cat in
                    Button {
                        var updated = task
                        updated.category = cat.name
                        tasks.update(updated)
                    } label: {
                        if task.category == cat.name {
                            Label(cat.name, systemImage: "checkmark")
                        } else {
                            Text(cat.name)
                        }
                    }
                }
            } label: {
                Label("Change category", systemImage: "tag")
            }
            Menu {
                ForEach(SharinganCore.TaskPriority.levels(custom: timer.settings.customPriorityLevels)) { p in
                    Button {
                        tasks.setPriority(task.id, p)
                    } label: {
                        Label(timer.settings.priorityName(p),
                              systemImage: task.priority == p ? "checkmark" : "flag.fill")
                    }
                }
            } label: {
                Label("Priority", systemImage: "flag.fill")
            }
            Menu {
                // Subtask estimates outrank the task's own in every badge/ring
                // (effectiveEstimate) — say so here instead of looking broken.
                if let sum = task.subtaskEstimateTotal {
                    Text("Using subtask total: \(sum) 🍅").disabled(true)
                    Divider()
                }
                Button("No estimate") { tasks.setEstimate(task.id, nil) }
                Divider()
                ForEach(1...8, id: \.self) { n in
                    Button {
                        tasks.setEstimate(task.id, n)
                    } label: {
                        if task.estimatedPomodoros == n {
                            Label("\(n) 🍅", systemImage: "checkmark")
                        } else {
                            Text("\(n) 🍅")
                        }
                    }
                }
            } label: {
                Label("Estimate", systemImage: "target")
            }
            Button {
                tasks.togglePlannedToday(task.id)
            } label: {
                Label(task.isPlannedToday() ? "Remove from today" : "Plan for today",
                      systemImage: task.isPlannedToday() ? "sun.max" : "sun.max.fill")
            }
            Menu {
                ForEach(Recurrence.allCases) { r in
                    Button {
                        tasks.setRecurrence(task.id, r)
                    } label: {
                        if task.recurrence == r { Label(r.label, systemImage: "checkmark") }
                        else { Text(r.label) }
                    }
                }
            } label: { Label("Repeat", systemImage: "repeat") }
            if !tasks.projects.isEmpty {
                Menu {
                    Button("None") { tasks.setProject(task.id, nil) }
                    Divider()
                    ForEach(tasks.projects, id: \.self) { p in
                        Button {
                            tasks.setProject(task.id, p)
                        } label: {
                            if task.project == p { Label(p, systemImage: "checkmark") }
                            else { Text(p) }
                        }
                    }
                } label: { Label("Project", systemImage: "folder") }
            }
            Divider()
            Button { tasks.move(task.id, up: true) } label: {
                Label("Move up", systemImage: "arrow.up")
            }
            Button { tasks.move(task.id, up: false) } label: {
                Label("Move down", systemImage: "arrow.down")
            }
            Divider()
            Button(role: .destructive) { pendingDeleteTask = task } label: {
                Label("Delete", systemImage: "trash")
            }
    }

    /// Colored bucket pill for a task's category.
    private func categoryTag(_ name: String, accent: Color) -> some View {
        HStack(spacing: 4) {
            CategoryGlyph(symbol: tasks.icon(for: name), color: accent, size: 9)
            Text(name)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(accent)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(
            Capsule().fill(accent.opacity(0.14))
        )
    }

    /// One fixed-width tier of a row's decorations — chips (category pill, up
    /// to `tags` tag chips, the due-date chip) and the small state icons
    /// (planned today / repeat / pomodoro kind). `fixedSize` makes the tier
    /// all-or-nothing so `ViewThatFits` in `miniRow` can walk down the ladder;
    /// without it SwiftUI compresses the labels in place into unreadable
    /// slivers. Step/pomodoro progress deliberately lives outside the ladder —
    /// it never drops.
    private func miniMeta(_ task: TaskItem, accent: Color,
                          category: Bool, tags: Int, due: Bool) -> some View {
        HStack(spacing: 8) {
            // Category — the colored bucket pill (hidden inside an accordion
            // section, whose header already names the category).
            if category {
                categoryTag(task.category, accent: accent)
            }
            // Tags — separate `#label` chips (a tag is not a category).
            ForEach(task.tags.prefix(tags), id: \.self) { tag in
                tagChip(tag)
            }
            // Due date chip (red when overdue).
            if due, let d = task.dueDate {
                Label(dueChipText(d), systemImage: "calendar")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(task.isOverdue() ? Color.red : .secondary)
                    .labelStyle(.titleAndIcon)
            }
            if task.isPlannedToday() {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .help("On today's plan")
            }
            if task.recurrence != .none {
                Image(systemName: "repeat")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .help(task.recurrence.label)
            }
            if let kind = task.pomodoroKind {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .help(kind.label)
            }
        }
        .fixedSize()
    }

    /// Expanded subtasks + notes editor for a task in the popover.
    private func subtaskPanel(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(task.subtasks) { sub in
                let isTarget = tasks.activeSubtaskID == sub.id
                HStack(spacing: 8) {
                    Button {
                        tasks.toggleSubtask(task.id, sub.id)
                    } label: {
                        Image(systemName: sub.isDone ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 13))
                            .foregroundStyle(sub.isDone ? Color.green : .secondary)
                    }
                    .buttonStyle(.pressableSubtle)
                    Text(sub.title)
                        .font(.system(.caption, design: .rounded))
                        .strikethrough(sub.isDone, color: .secondary)
                        .foregroundStyle(sub.isDone ? AnyShapeStyle(.secondary)
                                         : isTarget ? AnyShapeStyle(Color.accentColor)
                                         : AnyShapeStyle(.primary))
                        .lineLimit(1)
                    Spacer()
                    if timer.settings.showPomodoroBadges,
                       sub.pomodorosDone > 0 || sub.estimatedPomodoros != nil {
                        Text(sub.estimatedPomodoros.map { "🍅\(sub.pomodorosDone)/\($0)" }
                             ?? "🍅\(sub.pomodorosDone)")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    if !sub.isDone {
                        Button {
                            tasks.setActiveSubtask(taskID: task.id,
                                                   subtaskID: isTarget ? nil : sub.id)
                        } label: {
                            Image(systemName: isTarget ? "scope" : "circle.dashed")
                                .font(.system(size: 11))
                                .foregroundStyle(isTarget ? Color.accentColor : .secondary)
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressableSubtle)
                        .help("Focus pomodoros credit this step")
                        .accessibilityLabel(isTarget ? "Stop targeting \(sub.title)"
                                                     : "Target focus at \(sub.title)")
                    }
                    Button { tasks.deleteSubtask(task.id, sub.id) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressableSubtle)
                    .help("Remove step")
                }
            }
            // Add subtask
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tint)
                TextField("Add step…", text: Binding(
                    get: { subtaskDrafts[task.id] ?? "" },
                    set: { subtaskDrafts[task.id] = $0 }
                ))
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .rounded))
                    .onSubmit { commitSubtask(task.id) }
            }
            if !task.notes.isEmpty {
                Text(task.notes)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.leading, 28).padding(.trailing, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.03)))
    }

    private func commitSubtask(_ taskID: UUID) {
        let text = (subtaskDrafts[taskID] ?? "").trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let est = timer.settings.defaultSubtaskEstimate
        tasks.addSubtask(taskID, title: text, estimate: est > 0 ? est : nil)
        subtaskDrafts[taskID] = ""
    }

    /// Pomodoro progress: "🍅done/est" when estimated, else "🍅done".
    /// Estimate is the subtask sum when subtasks carry estimates.
    @ViewBuilder
    private func pomodoroBadge(_ task: TaskItem) -> some View {
        if timer.settings.showPomodoroBadges {
            if let est = task.effectiveEstimate {
                Text("🍅\(task.pomodorosDone)/\(est)")
                    .font(.system(.caption2, design: .rounded).weight(.medium))
                    .foregroundStyle(task.pomodorosDone >= est ? Color.green : .secondary)
            } else if task.pomodorosDone > 0 {
                Text("🍅\(task.pomodorosDone)")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Compact due-date label for a task row.
    private func dueChipText(_ d: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        if cal.isDateInToday(d) { f.dateFormat = "HH:mm"; return f.string(from: d) }
        if cal.isDateInTomorrow(d) { return "tmrw" }
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }

    /// Neutral `#label` chip for a free-form tag (distinct from the category).
    private func tagChip(_ tag: String) -> some View {
        Text("#\(tag)")
            .font(.system(.caption2, design: .rounded).weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(
                Capsule().fill(Color.primary.opacity(0.08))
            )
    }

    /// Adds a task, pulling any `#tag` tokens out of the typed text into the
    /// task's tags (category stays the default — a tag is not a category).
    /// Saves an inline rename and exits edit mode. Title-only, matching the
    /// main window — re-parsing `#tokens` here corrupted any legitimate title
    /// containing a `#` (e.g. "Buy #2 pencils" lost "#2" on a no-op edit).
    private func commitEdit(_ task: TaskItem) {
        defer { editingTaskID = nil; editFieldFocused = false }
        let title = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != task.title else { return }
        var updated = task
        updated.title = title
        tasks.update(updated)
    }

    /// Full natural-language quick add — the same parser (and 25-language
    /// vocabulary) the main composer uses, so `ertaga 15:00 p1 #ish next week`
    /// typed here yields dates, recurrence, priority, project and estimate, not
    /// just a raw title. The preview chips above already reflect this parse.
    private func quickAdd() {
        let raw = quickTitle.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        // Whole pasted documents import in bulk; a line quick-adds.
        if let result = tasks.importIfDocument(raw) {
            quickTitle = ""
            ImportDuplicatePrompt.resolve(result, store: tasks)
            return
        }
        let parsed = TaskInputParser.parse(raw, now: Date())
        let title = parsed.title.isEmpty ? raw : parsed.title
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        tasks.add(title: title,
                  tags: parsed.tags,
                  dueDate: parsed.dueDate,
                  estimatedPomodoros: parsed.estimatedPomodoros,
                  recurrence: parsed.recurrence,
                  project: parsed.project,
                  priority: parsed.priority)
        quickTitle = ""
    }

    private func startFocus(on task: TaskItem) {
        if tasks.activeTaskID == task.id, timer.isRunning {
            timer.toggle()
            return
        }
        tasks.selectFocusTarget(task.id)
        timer.startFocusSession(kind: tasks.resolvedActiveKind)
    }

    // MARK: - Pieces

    /// One row, every control the same 36×36 circle so the whole strip reads as
    /// one family: Small · Normal · Big (pomodoro size) — a divider — Skip ·
    /// Start · Reset · −5m · +5m · Auto. Labels live in tooltips; the row would
    /// never fit the popover's fixed width if every button also carried text.
    private var controls: some View {
        let accent = timer.settings.theme.accent
        return HStack(spacing: 6) {
            ForEach(PomodoroKind.allCases) { kind in
                let selected = timer.settings.activeKind == kind
                let cfg = timer.settings.config(for: kind)
                circleButton(kind.systemImage, selected: selected, accent: accent,
                            help: "\(kind.label): \(cfg.focusMinutes) min focus, \(cfg.breakMinutes) min break") {
                    timer.applyKind(kind)
                }
            }
            Divider().frame(height: 22)
            circleButton("forward.end.fill", accent: accent, help: "Skip") { timer.skip() }
            startPauseCircle
            circleButton("arrow.counterclockwise", tint: .red.opacity(0.9), accent: accent,
                        help: "Reset") { timer.stop() }
            circleButton("minus", tint: .orange.opacity(0.9), accent: accent,
                        help: "-5 minutes") { timer.removeTime(300) }
            circleButton("plus", tint: .green.opacity(0.9), accent: accent,
                        help: "+5 minutes") { timer.addTime(300) }
            circleButton("infinity", selected: timer.settings.autoCycle,
                        tint: timer.settings.autoCycle ? .green : .primary.opacity(0.85),
                        accent: .green,
                        help: "Auto mode: focus → break → focus runs continuously, no manual Start") {
                timer.settings.autoCycle.toggle()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var startPauseCircle: some View {
        circleButton(timer.isRunning ? "pause.fill" : "play.fill",
                    prominent: true, accent: timer.settings.theme.accent,
                    help: startBlocked ? "Add or pick a task to start a focus session"
                                       : (timer.isRunning ? "Pause" : "Start"),
                    action: startTapped)
            // Gentle breathing pulse while the timer runs.
            .scaleEffect(timer.isRunning && !reduceMotion ? 1.03 : 1.0)
            .animation(timer.isRunning && !reduceMotion
                       ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
                       : .default,
                       value: timer.isRunning)
            // When a task is required but none exists, Start would silently do
            // nothing — dim + disable it so the dead tap is visible.
            .opacity(startBlocked ? 0.45 : 1)
            .disabled(startBlocked)
    }

    /// One uniform 36×36 circle used for every control in `controls` — same
    /// shape and size whether it's a pomodoro-size pick, Start, or a nudge, so
    /// the strip reads as one consistent family instead of mismatched pills.
    private func circleButton(_ systemImage: String, selected: Bool = false,
                              prominent: Bool = false, tint: Color = .primary,
                              accent: Color, help: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .contentTransition(.opacity)
                .foregroundStyle(prominent ? Color.white
                                  : (selected ? accent : tint.opacity(0.85)))
                .frame(width: 36, height: 36)
                .background(circleBackground(selected: selected, prominent: prominent, accent: accent))
                .overlay(
                    Circle().stroke(
                        prominent ? Color.white.opacity(0.25)
                        : (selected ? accent.opacity(0.6) : Color.clear),
                        lineWidth: 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.pressableSubtle)
        .help(help)
    }

    @ViewBuilder
    private func circleBackground(selected: Bool, prominent: Bool, accent: Color) -> some View {
        if prominent {
            Circle().fill(LinearGradient(colors: [accent, accent.opacity(0.82)],
                                         startPoint: .top, endPoint: .bottom))
                .shadow(color: accent.opacity(0.5), radius: 6, y: 2)
        } else if selected {
            Circle().fill(accent.opacity(0.24))
        } else {
            Circle().fill(Color.white.opacity(0.06))
        }
    }

    /// True when Start can do nothing: the "require a task" rule is on, no task
    /// is active, and there are no open tasks to fall back to.
    private var startBlocked: Bool {
        !timer.isRunning && tasks.activeTask == nil
            && allOpenTasks.isEmpty && timer.settings.requireTaskForFocus
    }

    /// Start requires a task: toggle the running timer if one is active,
    /// otherwise kick off a focus session on the top task in the inline list.
    private func startTapped() {
        if timer.isRunning || tasks.activeTask != nil {
            timer.toggle()
        } else if let first = allOpenTasks.first {
            startFocus(on: first)
        } else if !timer.settings.requireTaskForFocus {
            timer.toggle()
        }
        // Otherwise: no task + rule on → nothing runs.
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
            Text(label).font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    /// Today / Cycle / Streak stats and the Sync / Settings / Quit actions,
    /// combined into a single row so the footer no longer takes two.
    private var footer: some View {
        HStack(spacing: 14) {
            stat(value: "\(timer.stats.completedTodayCount())", label: "Today")
            stat(value: "\(timer.cyclesCompletedInRound)/\(timer.settings.longBreakEvery)",
                 label: "Cycle")
            if timer.settings.repeatConfig.enabled {
                stat(value: "\(timer.repeatIndex + 1)/\(timer.settings.repeatConfig.count)",
                     label: "Repeat")
            }
            stat(value: "\(timer.stats.streak.currentStreak)", label: "Streak")

            Spacer(minLength: 12)

            if let engine = AppServices.syncEngine {
                SyncFooterButton(engine: engine)
            }

            Button { openAppSettings() } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressableSubtle)
            .foregroundStyle(.secondary)
            .help("Settings")

            Button { NSApp.terminate(nil) } label: {
                Label("Quit", systemImage: "power")
                    .font(.system(.callout, design: .rounded).weight(.medium))
            }
            .buttonStyle(.pressableSubtle)
            .foregroundStyle(.secondary)
        }
    }

    /// Opens the SwiftUI `Settings` scene. An `.accessory` app has no menu bar,
    /// so ⌘, is unreachable — drive it programmatically on macOS 13 & 14+.
    /// Opens the main window on its Settings section. This is far more reliable
    /// than the `showSettingsWindow:` selector, which silently no-ops for an
    /// `.accessory` menu-bar app on recent macOS.
    private func openAppSettings() {
        AppRouter.shared.openSettings()
        MainWindowManager.shared.show()
    }
}

/// Footer "Sync" button — triggers `CloudSyncEngine.syncNow()` and spins its
/// icon while a round trip is in flight. Disabled unless the user has turned
/// iCloud sync on and no sync is already running.
private struct SyncFooterButton: View {
    @ObservedObject var engine: CloudSyncEngine
    @AppStorage(CloudSyncEngine.syncEnabledKey) private var syncEnabled = false

    var body: some View {
        Button { engine.syncNow() } label: {
            Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(.callout, design: .rounded).weight(.medium))
                .rotationEffect(.degrees(engine.status.isActive ? 360 : 0))
                .animation(
                    engine.status.isActive
                        ? .linear(duration: 1).repeatForever(autoreverses: false)
                        : .default,
                    value: engine.status.isActive)
        }
        .buttonStyle(.pressableSubtle)
        .foregroundStyle(.secondary)
        .disabled(!canSyncNow)
        .opacity(canSyncNow ? 1 : 0.4)
        .help(syncEnabled ? "Sync Now" : "Turn on iCloud sync in Settings first")
    }

    private var canSyncNow: Bool {
        if case .idle = engine.status { return syncEnabled }
        return false
    }
}
