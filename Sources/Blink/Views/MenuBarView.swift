import SwiftUI
import AppKit
import BlinkCore

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

    private enum Tab: Hashable { case timer, tasks, stats }

    var body: some View {
        VStack(spacing: 14) {
            Picker("", selection: $tab) {
                Image(systemName: "timer").tag(Tab.timer)
                Image(systemName: "checklist").tag(Tab.tasks)
                Image(systemName: "chart.bar.fill").tag(Tab.stats)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch tab {
                case .timer: timerTab
                case .tasks: TasksView(timer: timer)
                case .stats: statsTab
                }
            }

            Divider().overlay(Color.white.opacity(0.15))
            footer
        }
        .onAppear { heartbeat = true }
        .padding(18)
        .frame(width: 360)
    }

    // MARK: - Tabs

    private var timerTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            StreakRewardBanner(center: StreakRewardCenter.shared)
            // Task list is the primary plan — it sits at the very top so the
            // user's added todos are the first thing shown. The pomodoro status
            // and controls sit below as a secondary layer.
            taskList
            statusHeader
            controls
            Divider().overlay(Color.white.opacity(0.15))
            statsStrip
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
                    .buttonStyle(.plain)
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
            .buttonStyle(.plain)
        }
    }

    /// All open tasks (ignoring search/today filters) — used to decide whether to
    /// show the filter controls.
    private var allOpenCount: Int { tasks.tasks.filter { !$0.isDone }.count }

    /// Open (unfinished) tasks after search + today filters, the active one on top,
    /// then manual order.
    private var openTasks: [TaskItem] {
        var list = tasks.tasks.filter { !$0.isDone }
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
                TextField("Add a task…", text: $quickTitle, onCommit: quickAdd)
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
                    .animation(.spring(response: 0.35, dampingFraction: 0.82),
                               value: groupedOpen.map(\.category))
                }
                // Size to the actual content (headers + expanded rows) so a short
                // list doesn't claim 300pt and shove the timer off-screen; only
                // taller lists scroll.
                .frame(height: taskListHeight)
            }
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
            }
        }
        return min(max(h, 40), 240)
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
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isCollapsed { collapsedCategories.remove(group.category) }
                    else { collapsedCategories.insert(group.category) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    Image(systemName: tasks.icon(for: group.category))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 16)
                    Text(group.category)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    Text("\(group.items.count)")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
                        miniRow(task, showCategory: false)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity.combined(with: .scale(scale: 0.9))))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.82),
                           value: group.items.map(\.id))
            }
        }
    }

    private func miniRow(_ task: TaskItem, showCategory: Bool = true) -> some View {
        let isActive = tasks.activeTaskID == task.id
        let accent = Color(hex: tasks.color(for: task.category))
        return HStack(spacing: 10) {
            Button {
                tasks.toggleDone(task.id)
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if editingTaskID == task.id {
                TextField("Task name", text: $editingText, onCommit: { commitEdit(task) })
                    .textFieldStyle(.plain)
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .focused($editFieldFocused)
                    .onSubmit { commitEdit(task) }
                    .onExitCommand { editingTaskID = nil }
                    .onAppear { editFieldFocused = true }
                Spacer(minLength: 6)
            } else {
                Text(task.title)
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .lineLimit(1)

                // Category — the colored bucket pill (hidden inside an accordion
                // section, whose header already names the category).
                if showCategory {
                    categoryTag(task.category, accent: accent)
                }

                // Tags — separate `#label` chips (a tag is not a category).
                ForEach(task.tags.prefix(2), id: \.self) { tag in
                    tagChip(tag)
                }

                // Due date chip (red when overdue).
                if let due = task.dueDate {
                    Label(dueChipText(due), systemImage: "calendar")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(task.isOverdue() ? Color.red : .secondary)
                        .labelStyle(.titleAndIcon)
                }

                Spacer(minLength: 6)
            }

            if task.isPlannedToday() {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .help("On today's plan")
            }
            pomodoroBadge(task)
            Button {
                startFocus(on: task)
            } label: {
                Image(systemName: isActive && timer.isRunning
                      ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help("Run a focus pomodoro on this task")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isActive ? accent.opacity(0.16) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isActive ? accent.opacity(0.5) : .clear, lineWidth: 1)
        )
        .contextMenu {
            Button {
                // Prefill with title + existing #tags so the rename round-trips
                // (what you see is what gets saved, and tags can be edited/cleared).
                let tagText = task.tags.map { "#\($0)" }.joined(separator: " ")
                editingText = ([task.title, tagText].filter { !$0.isEmpty }).joined(separator: " ")
                editingTaskID = task.id
            } label: {
                Label("Edit", systemImage: "pencil")
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
            Divider()
            Button { tasks.move(task.id, up: true) } label: {
                Label("Move up", systemImage: "arrow.up")
            }
            Button { tasks.move(task.id, up: false) } label: {
                Label("Move down", systemImage: "arrow.down")
            }
            Divider()
            Button(role: .destructive) { tasks.delete(task.id) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// Colored bucket pill for a task's category.
    private func categoryTag(_ name: String, accent: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: tasks.icon(for: name))
                .font(.system(size: 9, weight: .semibold))
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

    /// Pomodoro progress: "🍅done/est" when estimated, else "🍅done".
    @ViewBuilder
    private func pomodoroBadge(_ task: TaskItem) -> some View {
        if let est = task.estimatedPomodoros {
            Text("🍅\(task.pomodorosDone)/\(est)")
                .font(.system(.caption2, design: .rounded).weight(.medium))
                .foregroundStyle(task.pomodorosDone >= est ? Color.green : .secondary)
        } else if task.pomodorosDone > 0 {
            Text("🍅\(task.pomodorosDone)")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
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
    /// Saves an inline rename (re-parsing `#tags` from the edited text) and exits
    /// edit mode. Empty text cancels without changing the task.
    private func commitEdit(_ task: TaskItem) {
        defer { editingTaskID = nil }
        let raw = editingText.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        var tagList: [String] = []
        var titleWords: [String] = []
        for word in raw.split(separator: " ") {
            if word.hasPrefix("#"), word.count > 1 {
                tagList.append(String(word.dropFirst()))
            } else {
                titleWords.append(String(word))
            }
        }
        let title = titleWords.joined(separator: " ")
        guard !title.isEmpty else { return }
        var updated = task
        updated.title = title
        // Tags always reflect the edited text: adding #tags sets them, removing
        // all hashtags clears them (prefill includes existing tags so nothing is
        // lost accidentally).
        updated.tags = tagList
        tasks.update(updated)
    }

    private func quickAdd() {
        let raw = quickTitle.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        var tagList: [String] = []
        var titleWords: [String] = []
        for word in raw.split(separator: " ") {
            if word.hasPrefix("#"), word.count > 1 {
                tagList.append(String(word.dropFirst()))
            } else {
                titleWords.append(String(word))
            }
        }
        let title = titleWords.joined(separator: " ")
        guard !title.isEmpty else { return }
        tasks.add(title: title, tags: tagList)
        quickTitle = ""
    }

    private func startFocus(on task: TaskItem) {
        if tasks.activeTaskID == task.id, timer.isRunning {
            timer.toggle()
            return
        }
        tasks.setActive(task.id)
        if timer.phase != .focus { timer.stop() }
        timer.start()
    }

    private var statsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                StreakBadgeView(streak: timer.stats.streak)
                StatsChartView(stats: timer.stats)
            }
            .padding(.vertical, 2)
        }
        .frame(height: 360)
    }

    // MARK: - Pieces

    private var statusHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.white.opacity(0.1))
                Image(systemName: timer.phase.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(timer.phase.glow)
                    .contentTransition(.opacity)
            }
            .frame(width: 46, height: 46)
            .glassCapsule()

            VStack(alignment: .leading, spacing: 2) {
                Text(timer.phase.label)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .contentTransition(.opacity)
                Text(timer.settings.timeFormat.string(timer.remainingSeconds))
                    .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.3), value: timer.remainingSeconds)
            }
            Spacer()
        }
        // Icon, label and glow cross-fade when the phase changes.
        .animation(.easeInOut(duration: 0.4), value: timer.phase)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            GlassButton(label: timer.isRunning ? "Pause" : "Start",
                        systemImage: timer.isRunning ? "pause.fill" : "play.fill",
                        action: startTapped)
                // Gentle breathing pulse while the timer runs.
                .scaleEffect(timer.isRunning && heartbeat ? 1.012 : 1.0)
                .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                           value: heartbeat)
            HStack(spacing: 8) {
                GlassButton(label: "Skip",
                            systemImage: "forward.end.fill",
                            action: { timer.skip() })
                GlassButton(label: "Reset",
                            systemImage: "arrow.counterclockwise",
                            tint: .red.opacity(0.95),
                            action: { timer.stop() })
            }
            HStack(spacing: 8) {
                GlassButton(label: "+5m",
                            systemImage: "plus",
                            tint: .green.opacity(0.95),
                            action: { timer.addTime(300) })
                GlassButton(label: "-5m",
                            systemImage: "minus",
                            tint: .orange.opacity(0.95),
                            action: { timer.removeTime(300) })
            }
            autoModeToggle
        }
    }

    /// Auto mode — run focus → break → focus → break continuously, hands-free.
    private var autoModeToggle: some View {
        let on = timer.settings.autoCycle
        return Button {
            timer.settings.autoCycle.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "infinity")
                    .font(.system(size: 13, weight: .bold))
                Text(on ? "Auto mode: ON" : "Auto mode")
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(
                Capsule().fill(on ? Color.green.opacity(0.22) : Color.white.opacity(0.06))
            )
            .overlay(
                Capsule().stroke(on ? Color.green.opacity(0.6) : Color.white.opacity(0.12),
                                 lineWidth: 1)
            )
            .foregroundStyle(on ? Color.green : Color.primary.opacity(0.85))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Auto mode: focus → break → focus runs continuously, no manual Start")
    }

    /// Start requires a task: toggle the running timer if one is active,
    /// otherwise kick off a focus session on the top task in the inline list.
    private func startTapped() {
        if timer.isRunning || tasks.activeTask != nil {
            timer.toggle()
        } else if let first = openTasks.first {
            startFocus(on: first)
        } else if !timer.settings.requireTaskForFocus {
            timer.toggle()
        }
        // Otherwise: no task + rule on → nothing runs.
    }

    private var statsStrip: some View {
        HStack(spacing: 14) {
            stat(value: "\(timer.stats.completedTodayCount())", label: "Today")
            stat(value: "\(timer.cyclesCompletedInRound)/\(timer.settings.longBreakEvery)",
                 label: "Cycle")
            if timer.settings.repeatConfig.enabled {
                stat(value: "\(timer.repeatIndex + 1)/\(timer.settings.repeatConfig.count)",
                     label: "Repeat")
            }
            stat(value: "\(timer.stats.streak.currentStreak)", label: "Streak")
        }
        .frame(maxWidth: .infinity)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
            Text(label).font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button {
                MainWindowManager.shared.show()
            } label: {
                Label("Open window", systemImage: "macwindow")
                    .font(.system(.callout, design: .rounded).weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button { openAppSettings() } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressableSubtle)
            .foregroundStyle(.secondary)
            .help("Settings")

            Spacer()

            Button { NSApp.terminate(nil) } label: {
                Label("Quit", systemImage: "power")
                    .font(.system(.callout, design: .rounded).weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    /// Opens the SwiftUI `Settings` scene. An `.accessory` app has no menu bar,
    /// so ⌘, is unreachable — drive it programmatically on macOS 13 & 14+.
    /// Opens the main window on its Settings section. This is far more reliable
    /// than the `showSettingsWindow:` selector, which silently no-ops for an
    /// `.accessory` menu-bar app on recent macOS.
    private func openAppSettings() {
        AppRouter.shared.section = .settings
        MainWindowManager.shared.show()
    }
}
