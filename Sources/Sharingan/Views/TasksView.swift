import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SharinganCore

struct TasksView: View {
    @ObservedObject var timer: PomodoroTimer
    /// When true (main window), rows flow into the parent scroll view instead of
    /// the fixed-height inner scroll used by the compact menu-bar popover.
    var embeddedInScroll: Bool = false
    @ObservedObject private var store = TaskStore.shared
    @ObservedObject private var templates = TemplateStore.shared
    /// The coordinator's focus queue — tasks worked through one pomodoro each.
    @ObservedObject private var queue = AppServices.focusQueue
    /// Small "Queue (N)" popover anchored to the chip in the view bar.
    @State private var showQueuePanel = false

    @State private var newTitle = ""
    @State private var newCategory = TaskCategory.presets[0].name
    @State private var newTagList: [String] = []
    @State private var tagDraft = ""
    @State private var hasDue = false
    @State private var newDue = Date().addingTimeInterval(3600)
    @State private var showCustomDue = false
    @State private var newEstimate = 0
    @State private var newRecurrence: Recurrence = .none
    @State private var newProject = ""
    /// Inline "new project" name form under the composer's project picker.
    @State private var showNewProject = false
    @State private var newProjectName = ""
    @State private var newNotes = ""
    @State private var newPriority: TaskPriority = .none
    /// Pomodoro length override for the new task; nil means Auto (settings default).
    @State private var newKind: PomodoroKind? = nil
    /// Tasks whose subtasks/notes panel is expanded.
    @State private var expanded: Set<UUID> = []
    @State private var subtaskDrafts: [UUID: String] = [:]
    /// Inline title editing (double-click a row or the context-menu "Edit").
    @State private var editingTaskID: UUID?
    @State private var editingText = ""
    @FocusState private var editFocused: Bool
    /// Row the pointer is over — reveals its delete button.
    @State private var hoveredTask: UUID?
    /// Task currently open in the full editor sheet (nil = closed).
    @State private var editorTask: TaskItem?
    /// Task shown in the docked side panel (main window only, `embeddedInScroll`).
    @State private var detailTask: TaskItem?
    /// Task being snoozed via "Pick date…" (nil = closed).
    @State private var snoozeTask: TaskItem?
    @State private var snoozeDate = Date()
    /// Task being saved as a template (nil = no name prompt).
    @State private var templateNamingTask: TaskItem?
    @State private var templateName = ""
    /// Small template list sheet (rename / delete).
    @State private var showTemplateManager = false
    @State private var templateRenameID: UUID?
    @State private var templateRenameText = ""
    /// Done view "Clear" asks before deleting permanently.
    @State private var confirmClearCompleted = false
    /// Task queued for the "move to Trash?" confirmation (nil = no prompt).
    @State private var pendingDeleteTask: TaskItem?
    /// Task queued for the Trash's "delete forever?" confirmation.
    @State private var pendingPurgeTask: TaskItem?
    /// Whether the collapsible Trash section is expanded.
    @State private var showTrash = false
    /// Empty-Trash confirmation.
    @State private var confirmEmptyTrash = false
    /// Bulk import sheet — paste Markdown/JSON, or a dropped file's contents.
    @State private var showImportSheet = false
    @State private var importText = ""

    // Inline "add category" form state.
    @State private var showNewCategory = false
    @State private var newCatName = ""
    @State private var newCatColor = TaskCategory.palette[0]
    @State private var newCatIcon = TaskCategory.iconChoices[0]
    /// Inline category manager (recolor / re-icon / rename / delete).
    @State private var showCategoryManager = false
    @State private var renamingCategory: String?
    @State private var renameText = ""
    /// Advanced add-fields (category/tags/estimate/repeat/project/notes/due) are
    /// hidden behind a disclosure so the default composer is a single clean input.
    @State private var showDetails = false
    @FocusState private var composerFocused: Bool
    /// Smart-view filter + free-text search over the list.
    @State private var filter: TaskFilter = .all
    @State private var search = ""
    /// List ordering inside each category group — persisted across launches.
    @AppStorage("tasks.sortMode") private var sortModeRaw = TaskSortMode.manual.rawValue
    private var sortMode: TaskSortMode { TaskSortMode(rawValue: sortModeRaw) ?? .manual }
    /// Step ordering inside expanded subtask panels — persisted, shared with
    /// the focus picker's step rows.
    @AppStorage("tasks.subtaskSortMode") private var subSortRaw = SubtaskSortMode.manual.rawValue
    private var subSort: SubtaskSortMode { SubtaskSortMode(rawValue: subSortRaw) ?? .manual }
    /// Step narrowing for expanded panels — one setting for every panel.
    @State private var subStatus: SubtaskStatusFilter = .all
    @State private var subPriority: TaskPriority?
    /// Eisenhower matrix mode — replaces the grouped list with the 2×2 grid.
    @State private var showEisenhower = false
    @FocusState private var searchFocused: Bool
    /// Sidebar deep-link narrowing — at most one is active at a time.
    @State private var categoryFilter: String?
    @State private var projectFilter: String?
    @State private var tagFilter: String?
    @State private var priorityFilter: TaskPriority?
    @State private var deviceFilter: String?
    /// Row being flash-highlighted after a reveal deep-link (see `AppRouter.
    /// revealTask`) — cleared a couple of seconds after the scroll lands.
    @State private var revealedTaskID: UUID?
    /// Infinite scroll: how many rows are materialised right now. Starts at one
    /// page and grows by `pageSize` as the load-more footer nears the viewport.
    /// Reset to `pageSize` whenever the list's shape changes (filter, search,
    /// sort, narrowing) so a new view starts at the top of a fresh first page.
    @State private var visibleCount = TasksView.pageSize
    private static let pageSize = 20
    @ObservedObject private var router = AppRouter.shared

    private var newCategoryAccent: Color { Color(hex: store.color(for: newCategory)) }

    /// One value that changes whenever the visible list is re-shaped (smart
    /// view, search, sort, or any narrowing) — drives the paging reset.
    private var listShapeKey: String {
        "\(filter.label)|\(search)|\(sortModeRaw)|\(categoryFilter ?? "")|"
            + "\(projectFilter ?? "")|\(tagFilter ?? "")|"
            + "\(priorityFilter.map(String.init(describing:)) ?? "")|\(deviceFilter ?? "")"
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 12) {
                composer

                if store.tasks.isEmpty {
                    emptyState
                } else {
                    viewBar
                    if showEisenhower {
                        let matrix = EisenhowerView(timer: timer) { editorTask = $0 }
                        if embeddedInScroll {
                            matrix
                        } else {
                            ScrollView { matrix.padding(.vertical, 2) }
                                .frame(height: 320)
                        }
                    } else {
                        narrowFilterChip
                        let groups = narrowed(store.grouped(filter: filter, search: search,
                                                            sort: sortMode))
                        if groups.isEmpty {
                            noResults
                        } else if embeddedInScroll {
                            ScrollView { taskList(groups).padding(.vertical, 2) }
                        } else {
                            ScrollView { taskList(groups).padding(.vertical, 2) }
                                .frame(height: 320)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            // Docked detail panel (main window only) — the row's chevron.right
            // or "Edit…" opens it; the list stays visible beside it, no scrim.
            if embeddedInScroll, let task = store.tasks.first(where: { $0.id == detailTask?.id }) {
                Divider().overlay(Color.white.opacity(0.1)).padding(.vertical, 8)
                TaskEditorView(task: task,
                               accent: timer.settings.theme.accent,
                               settings: timer.settings,
                               presentation: .docked,
                               onClose: { withAnimation(DS.Motion.panel) { detailTask = nil } })
                    // The editor seeds its `draft` @State in init, so switching
                    // rows has to give it a new identity — otherwise the panel
                    // keeps showing the first task it was opened with.
                    .id(task.id)
                    .frame(width: 380)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.97, anchor: .trailing)),
                        removal: .move(edge: .trailing).combined(with: .opacity)))
            }
        }
        .animation(DS.Motion.panel, value: detailTask?.id)
        .sheet(item: $editorTask) { task in
            TaskEditorView(task: task,
                           accent: timer.settings.theme.accent,
                           settings: timer.settings)
        }
        .sheet(item: $snoozeTask) { task in snoozeSheet(task) }
        .sheet(isPresented: $showTemplateManager) { templateManager }
        .sheet(isPresented: $showImportSheet) { importSheet }
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleFileDrop)
        .alert("Save as Template", isPresented: Binding(
            get: { templateNamingTask != nil },
            set: { if !$0 { templateNamingTask = nil } })) {
            TextField("Template name", text: $templateName)
            Button("Save") {
                if let t = templateNamingTask {
                    templates.saveTemplate(from: t, name: templateName)
                }
                templateNamingTask = nil
            }
            Button("Cancel", role: .cancel) { templateNamingTask = nil }
        } message: {
            Text("Saves the task's shape — subtasks, tags, estimates — for reuse.")
        }
        .alert("Clear completed tasks?", isPresented: $confirmClearCompleted) {
            Button("Delete \(store.count(.completed))", role: .destructive) {
                withAnimation { store.clearCompleted() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let n = store.count(.completed)
            Text("This permanently deletes \(n) completed task\(n == 1 ? "" : "s").")
        }
        .alert("Delete this task?", isPresented: Binding(
            get: { pendingDeleteTask != nil },
            set: { if !$0 { pendingDeleteTask = nil } })) {
            Button("Move to Trash", role: .destructive) {
                if let t = pendingDeleteTask {
                    withAnimation(DS.Motion.standard) {
                        queue.remove(t.id)
                        store.delete(t.id)
                    }
                }
                pendingDeleteTask = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteTask = nil }
        } message: {
            Text(pendingDeleteTask.map { "“\($0.title)” moves to Trash — you can restore it from there." } ?? "")
        }
        .alert("Delete forever?", isPresented: Binding(
            get: { pendingPurgeTask != nil },
            set: { if !$0 { pendingPurgeTask = nil } })) {
            Button("Delete forever", role: .destructive) {
                if let t = pendingPurgeTask { withAnimation { store.deletePermanently(t.id) } }
                pendingPurgeTask = nil
            }
            Button("Cancel", role: .cancel) { pendingPurgeTask = nil }
        } message: {
            Text(pendingPurgeTask.map { "“\($0.title)” will be gone for good. This can't be undone." } ?? "")
        }
        .alert("Empty Trash?", isPresented: $confirmEmptyTrash) {
            Button("Delete \(store.trashedTasks.count) forever", role: .destructive) {
                withAnimation { store.emptyTrash() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let n = store.trashedTasks.count
            Text("This permanently deletes \(n) task\(n == 1 ? "" : "s") in the Trash.")
        }
        // Any change to the list's shape restarts paging at the first page, so
        // a freshly-narrowed view opens at the top instead of mid-scroll.
        .onChange(of: listShapeKey) { visibleCount = TasksView.pageSize }
        .onAppear(perform: consumeDeepLink)
        .onChange(of: router.pendingTaskFilter) { consumeDeepLink() }
        .onChange(of: router.pendingTaskCategory) { consumeDeepLink() }
        .onChange(of: router.pendingTaskProject) { consumeDeepLink() }
        .onChange(of: router.pendingTaskTag) { consumeDeepLink() }
        .onChange(of: router.pendingTaskPriority) { consumeDeepLink() }
        .onChange(of: router.focusTaskSearch) { consumeDeepLink() }
        .onChange(of: router.pendingRevealTaskID) { consumeDeepLink() }
        .onChange(of: router.openTaskImport) { consumeDeepLink() }
    }

    /// Applies (and clears) one-shot sidebar deep-links: smart filter, one
    /// narrowing dimension (category / tag / priority), or search focus.
    private func consumeDeepLink() {
        if let f = router.pendingTaskFilter {
            filter = f
            router.pendingTaskFilter = nil
        }
        if router.pendingTaskCategory != nil || router.pendingTaskProject != nil
            || router.pendingTaskTag != nil || router.pendingTaskPriority != nil {
            categoryFilter = router.pendingTaskCategory
            projectFilter = router.pendingTaskProject
            tagFilter = router.pendingTaskTag
            priorityFilter = router.pendingTaskPriority
            if filter == .completed { filter = .all }
            router.pendingTaskCategory = nil
            router.pendingTaskProject = nil
            router.pendingTaskTag = nil
            router.pendingTaskPriority = nil
        }
        if router.focusTaskSearch {
            searchFocused = true
            router.focusTaskSearch = false
        }
        if router.openTaskImport {
            showImportSheet = true
            router.openTaskImport = false
        }
        if let id = router.pendingRevealTaskID {
            // A reveal outranks whatever the list happens to be showing: drop
            // the search, the sidebar narrowing and the matrix, and land on the
            // smart view that actually contains the task (Done for completed).
            search = ""
            categoryFilter = nil; projectFilter = nil; tagFilter = nil; priorityFilter = nil
            deviceFilter = nil
            showEisenhower = false
            let isDone = store.tasks.first { $0.id == id }?.isDone ?? false
            filter = isDone ? .completed : .all
            revealedTaskID = id
            router.pendingRevealTaskID = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                if revealedTaskID == id {
                    withAnimation(DS.Motion.gentle) { revealedTaskID = nil }
                }
            }
        }
    }

    /// Applies the active sidebar narrowing to the smart-view groups, dropping
    /// groups that end up empty.
    private func narrowed(_ groups: [(category: String, items: [TaskItem])])
        -> [(category: String, items: [TaskItem])] {
        guard categoryFilter != nil || projectFilter != nil
            || tagFilter != nil || priorityFilter != nil || deviceFilter != nil else {
            return groups
        }
        return groups.compactMap { g in
            if let c = categoryFilter, g.category != c { return nil }
            var items = g.items
            if let pr = projectFilter { items = items.filter { $0.project == pr } }
            if let t = tagFilter { items = items.filter { $0.tags.contains(t) } }
            if let p = priorityFilter { items = items.filter { $0.priority == p } }
            if let d = deviceFilter { items = items.filter { $0.originDevice == d } }
            return items.isEmpty ? nil : (g.category, items)
        }
    }

    /// "Filtered by …" pill (category / project / tag / priority) with a clear button.
    @ViewBuilder
    private var narrowFilterChip: some View {
        if categoryFilter != nil || projectFilter != nil
            || tagFilter != nil || priorityFilter != nil {
            let (symbol, label, tint): (String, String, Color) = {
                if let c = categoryFilter { return ("#", c, Color(hex: store.color(for: c))) }
                if let pr = projectFilter { return ("▤", pr, Color(hex: store.projectColor(pr))) }
                if let t = tagFilter { return ("@", t, .accentColor) }
                if let p = priorityFilter {
                    return ("⚑", timer.settings.priorityName(p),
                            timer.settings.priorityColorHex(p).map { Color(hex: $0) } ?? .secondary)
                }
                return ("", "", .secondary)
            }()
            HStack(spacing: 6) {
                Text(symbol)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                Button {
                    withAnimation(DS.Motion.gentle) {
                        categoryFilter = nil; projectFilter = nil
                        tagFilter = nil; priorityFilter = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.pressableSubtle)
                .help("Clear filter")
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(0.14)))
        }
    }

    /// The grouped section stack, shared by the embedded and popover layouts.
    /// The Done view regroups by completion day instead of category — history
    /// reads chronologically, newest first.
    private func taskList(_ groups: [(category: String, items: [TaskItem])]) -> some View {
        // Normalise both layouts to (label, items): Done regroups by day, the
        // open views stay grouped by category.
        let isDone = filter == .completed
        let allGroups: [(label: String, items: [TaskItem])] = isDone
            ? doneGroups(groups)
            : groups.map { (label: $0.category, items: $0.items) }
        let total = allGroups.reduce(0) { $0 + $1.items.count }
        let shown = min(visibleCount, total)
        let visible = limitedGroups(allGroups, to: shown)

        // Flatten headers + rows into ONE list. A single flat LazyVStack is the
        // key to smooth scrolling: nested lazy stacks defeat each other's
        // laziness and force a whole category to render at once. Here every
        // header and row is a direct lazy child, so only what's near the
        // viewport is ever built.
        let rows = flattenRows(visible, isDone: isDone)

        return ScrollViewReader { proxy in
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(rows) { listRowView($0, isDone: isDone) }
                // Infinite scroll: this footer auto-loads the next page as it
                // nears the viewport. A fresh id per page re-arms its onAppear.
                if shown < total {
                    loadMoreFooter(shown: shown, total: total)
                        .id("load-more-\(shown)")
                        .padding(.top, 12)
                }
                // Trash lives in the full main window only — the menu-bar popover
                // stays lean (it's the combined focus + task list now).
                if embeddedInScroll { trashSection.padding(.top, 12) }
            }
            // Both hooks matter: onChange for a reveal that arrives while the
            // list is on screen, onAppear for one consumed before it was (the
            // deep-link flipped the matrix / empty state back into the list).
            .onAppear { scrollToRevealed(proxy) }
            .onChange(of: revealedTaskID) { scrollToRevealed(proxy) }
        }
    }

    /// A flattened list entry — either a group header or a task row. Flattening
    /// lets the whole list live in one non-nested LazyVStack.
    private enum ListRow: Identifiable {
        case header(label: String, count: Int)
        case task(TaskItem)
        var id: String {
            switch self {
            case .header(let label, _): return "header-\(label)"
            case .task(let t): return "task-\(t.id.uuidString)"
            }
        }
    }

    /// Interleaves each group's header with its rows into one flat sequence.
    private func flattenRows(_ groups: [(label: String, items: [TaskItem])], isDone: Bool)
        -> [ListRow] {
        var rows: [ListRow] = []
        rows.reserveCapacity(groups.reduce(0) { $0 + $1.items.count + 1 })
        for g in groups {
            rows.append(.header(label: g.label, count: g.items.count))
            for t in g.items { rows.append(.task(t)) }
        }
        return rows
    }

    /// Renders one flattened entry. Headers get top spacing so groups still read
    /// as separated sections without a nested container.
    @ViewBuilder
    private func listRowView(_ entry: ListRow, isDone: Bool) -> some View {
        switch entry {
        case .header(let label, let count):
            sectionHeader(label, count: count, isDone: isDone)
                .padding(.top, 12)
        case .task(let task):
            taskRow(task, isDone: isDone)
                .id(task.id)   // scroll anchor for reveal deep-links
        }
    }

    /// Group header — a category (icon + colour) for the open views, or a
    /// completion-day label for Done, with a count badge.
    private func sectionHeader(_ label: String, count: Int, isDone: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isDone ? "checkmark.circle" : store.icon(for: label))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isDone ? Color.dsTertiary : Color(hex: store.color(for: label)))
            Text(label).dsSectionLabel()
            Spacer()
            Text("\(count)")
                .font(.system(.caption2, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(Color.dsSecondary)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.06)))
        }
    }

    /// One task row plus its expanded subtask panel. Open views also carry the
    /// drag-to-reorder handlers; Done rows don't reorder.
    @ViewBuilder
    private func taskRow(_ task: TaskItem, isDone: Bool) -> some View {
        VStack(spacing: 4) {
            if isDone {
                row(task)
            } else {
                row(task)
                    .draggable(task.id.uuidString)
                    .dropDestination(for: String.self) { dropped, _ in
                        guard let s = dropped.first, let id = UUID(uuidString: s) else { return false }
                        store.moveTask(id, before: task.id)
                        return true
                    }
            }
            if expanded.contains(task.id) {
                subtaskPanel(task)
            }
        }
    }

    /// Truncates the grouped list to at most `limit` tasks in total, keeping the
    /// group structure — the last visible group is sliced mid-way if needed.
    private func limitedGroups(_ groups: [(label: String, items: [TaskItem])], to limit: Int)
        -> [(label: String, items: [TaskItem])] {
        var remaining = limit
        var out: [(label: String, items: [TaskItem])] = []
        for g in groups {
            if remaining <= 0 { break }
            if g.items.count <= remaining {
                out.append(g)
                remaining -= g.items.count
            } else {
                out.append((g.label, Array(g.items.prefix(remaining))))
                remaining = 0
            }
        }
        return out
    }

    /// Grows the visible window by one page. Called from the footer's onAppear,
    /// so it fires exactly when the user scrolls the footer into view.
    private func loadMore(total: Int) {
        guard visibleCount < total else { return }
        // No animation: animating a 20-row insertion drops frames mid-scroll.
        // The new rows simply appear below the footer as it scrolls off.
        visibleCount = min(visibleCount + TasksView.pageSize, total)
    }

    /// Premium load-more footer — a progress ring of how far through the list
    /// you are, the running "X of Y" count, and a soft accent glow. Auto-loads
    /// via onAppear (true infinite scroll); also tappable as a fallback.
    private func loadMoreFooter(shown: Int, total: Int) -> some View {
        let accent = timer.settings.theme.accent
        let progress = total > 0 ? Double(shown) / Double(total) : 0
        return Button {
            loadMore(total: total)
        } label: {
            HStack(spacing: 11) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(DS.Motion.gentle, value: progress)
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 7, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.dsSecondary)
                }
                .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Loading more")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.dsPrimary)
                    Text("\(shown) of \(total) tasks")
                        .font(.system(size: 10, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.dsTertiary)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accent.opacity(0.7))
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(Color.dsFill))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(accent.opacity(0.18), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        }
        .buttonStyle(.pressableSubtle)
        .help("Load the next \(TasksView.pageSize) tasks")
        .transition(.opacity)
        .onAppear { loadMore(total: total) }
    }

    /// Centres the revealed row — one runloop later, so a filter change from
    /// the same deep-link has laid the row out before we scroll to it.
    private func scrollToRevealed(_ proxy: ScrollViewProxy) {
        guard let id = revealedTaskID else { return }
        // The target may sit past the loaded window — materialise everything so
        // the anchor exists before we scroll to it. Reveal is deliberate
        // navigation, so the one-off full render is worth it.
        if visibleCount < store.tasks.count { visibleCount = store.tasks.count }
        DispatchQueue.main.async {
            withAnimation(DS.Motion.gentle) { proxy.scrollTo(id, anchor: .center) }
        }
    }

    /// View-side regrouping of completed tasks by completion day — Today /
    /// Yesterday / a medium date — newest first; tasks without a completion
    /// stamp (pre-history data) land in a trailing "Earlier" bucket.
    private func doneGroups(_ groups: [(category: String, items: [TaskItem])])
        -> [(label: String, items: [TaskItem])] {
        let all = groups.flatMap(\.items)
        let dated = all.filter { $0.completedAt != nil }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        var out: [(label: String, items: [TaskItem])] = []
        for task in dated {
            let label = doneDayLabel(task.completedAt!)
            if let i = out.firstIndex(where: { $0.label == label }) {
                out[i].items.append(task)
            } else {
                out.append((label, [task]))
            }
        }
        let undated = all.filter { $0.completedAt == nil }
        if !undated.isEmpty { out.append(("Earlier", undated)) }
        return out
    }

    private func doneDayLabel(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateStyle = .medium; f.timeStyle = .none
        return f.string(from: d)
    }

    // MARK: - Smart views (filter + search)

    /// Smart-view selector + search + (in Done) a clear-all action.
    private var viewBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(TaskFilter.allCases) { filterPill($0) }
            }
            HStack(spacing: 8) {
                searchField
                sortMenu
                filterMenu
                matrixToggle
                importButton
                queueChip
                if filter == .completed, store.count(.completed) > 0 {
                    Button { confirmClearCompleted = true } label: {
                        Label("Clear", systemImage: "trash")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(Color.red.opacity(0.85))
                    }
                    .buttonStyle(.pressableSubtle)
                    .help("Delete all completed tasks")
                }
            }
        }
    }

    /// One segment of the smart-view selector — label + live count.
    private func filterPill(_ f: TaskFilter) -> some View {
        let selected = filter == f
        let n = store.count(f)
        let accent = timer.settings.theme.accent
        return Button {
            withAnimation(DS.Motion.gentle) { filter = f }
        } label: {
            HStack(spacing: 4) {
                Text(f.label)
                    .font(.system(.caption, design: .rounded).weight(selected ? .semibold : .medium))
                if n > 0 {
                    Text("\(n)")
                        .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(selected ? .white.opacity(0.85) : Color.dsTertiary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(selected ? .white : Color.dsSecondary)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(selected ? accent.opacity(0.9) : Color.dsFill))
            .contentShape(Capsule())
        }
        .buttonStyle(.pressableSubtle)
    }

    /// Sort menu — reorders rows inside each category group. The icon tints
    /// while a non-manual sort applies; drag-to-reorder keeps editing the
    /// manual order underneath, which every mode uses as its tiebreak.
    private var sortMenu: some View {
        Menu {
            TaskSortMenuItems(sortModeRaw: $sortModeRaw)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(sortMode != .manual ? Color.accentColor : Color.dsSecondary)
                .frame(width: 27, height: 27)
                .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .fill(sortMode != .manual ? Color.accentColor.opacity(0.16) : Color.dsFill))
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help(sortMode == .manual ? "Sort tasks" : "Sorted by \(sortMode.label)")
        .accessibilityLabel("Sort tasks")
    }

    /// True while a sidebar/menu narrowing dimension is active.
    private var isNarrowed: Bool {
        categoryFilter != nil || tagFilter != nil || priorityFilter != nil
    }

    /// Filter menu — the same category / tag / priority narrowing the sidebar
    /// deep-links set, reachable from the list itself. One dimension at a
    /// time (matching the sidebar); the pick shows up as the "Filtered by …"
    /// chip, whose ✕ clears it. Picking the active entry toggles it off.
    private var filterMenu: some View {
        Menu {
            TaskFilterMenuItems(store: store, settings: timer.settings,
                                categoryFilter: $categoryFilter,
                                tagFilter: $tagFilter,
                                priorityFilter: $priorityFilter,
                                deviceFilter: $deviceFilter)
        } label: {
            Image(systemName: isNarrowed
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isNarrowed ? Color.accentColor : Color.dsSecondary)
                .frame(width: 27, height: 27)
                .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .fill(isNarrowed ? Color.accentColor.opacity(0.16) : Color.dsFill))
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Filter by category, tag, or priority")
        .accessibilityLabel("Filter tasks")
    }

    /// Compact grid icon that flips the list into the Eisenhower 2×2 matrix.
    private var matrixToggle: some View {
        Button {
            withAnimation(DS.Motion.gentle) { showEisenhower.toggle() }
        } label: {
            Image(systemName: showEisenhower ? "square.grid.2x2.fill" : "square.grid.2x2")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(showEisenhower ? Color.accentColor : Color.dsSecondary)
                .frame(width: 27, height: 27)
                .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .fill(showEisenhower ? Color.accentColor.opacity(0.16) : Color.dsFill))
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressableSubtle)
        .help(showEisenhower ? "Back to the list" : "Eisenhower matrix — urgency × importance")
        .accessibilityLabel(showEisenhower ? "Show task list" : "Show Eisenhower matrix")
    }

    private var searchField: some View {
        // The field lit up: it was near-invisible at rest, so clicking it (or the
        // sidebar "Search", which focuses it) gave no feedback. Focus now paints
        // an accent ring, a stronger fill, and an accent glyph so it clearly
        // "wakes up", and the field is a touch taller/rounder to read as a real
        // search bar rather than a faint strip.
        let active = searchFocused || !search.isEmpty
        let accent = timer.settings.theme.accent
        return HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? accent : Color.dsTertiary)
            TextField("Search tasks", text: $search)
                .textFieldStyle(.plain)
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.white)
                .focused($searchFocused)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.dsTertiary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressableSubtle)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .fill(active ? Color.dsFillStrong : Color.dsFill))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .stroke(searchFocused ? accent.opacity(0.8) : Color.clear, lineWidth: 1.5))
        .animation(DS.Motion.standard, value: active)
        .animation(DS.Motion.standard, value: searchFocused)
    }

    // MARK: - Focus queue

    /// Queued ids resolved against the store, in queue order — open tasks only
    /// (a read-only mirror of what `FocusQueue.current` would walk, without
    /// mutating queue state from a view).
    private var queuedOpenTasks: [TaskItem] {
        queue.taskIDs.compactMap { id in
            store.tasks.first { $0.id == id && !$0.isDone }
        }
    }

    /// 1-based position of a task among the (open) queued tasks, nil if unqueued.
    private func queuePosition(_ id: UUID) -> Int? {
        queuedOpenTasks.firstIndex { $0.id == id }.map { $0 + 1 }
    }

    /// Opens the bulk-import sheet (paste Markdown/JSON or drop a file).
    private var importButton: some View {
        Button { showImportSheet = true } label: {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.dsSecondary)
                .frame(width: 27, height: 27)
                .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .fill(Color.dsFill))
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressableSubtle)
        .help("Import tasks — paste Markdown or JSON, or drop a .md/.json file")
        .accessibilityLabel("Import tasks")
    }

    /// Paste-a-document import: the Markdown template, a plain checklist, or
    /// JSON — auto-detected, previewed as a live task count before inserting.
    private var importSheet: some View {
        let parsed = TaskImportParser.parse(importText)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Import Tasks")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Button { showImportSheet = false } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.pressableSubtle)
            }
            Text("Paste Markdown or JSON — the template lives in Settings → Tasks & Planning. A plain checklist works too.")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Color.dsTertiary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $importText)
                .font(.system(.caption, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 220)
                .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .fill(Color.black.opacity(0.25)))
            HStack {
                Button("Cancel") { importText = ""; showImportSheet = false }
                    .buttonStyle(.pressableSubtle)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                if !importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let dupCount = store.partitionByDuplicateTitle(parsed).duplicates.count
                    Text(parsed.isEmpty
                         ? "Nothing recognized"
                         : "\(parsed.count) task\(parsed.count == 1 ? "" : "s") recognized"
                           + (dupCount > 0 ? " · \(dupCount) already exist" : ""))
                        .font(.system(.caption2, design: .rounded).weight(.medium))
                        .foregroundStyle(parsed.isEmpty ? Color.orange.opacity(0.9) : Color.dsSecondary)
                }
                Button("Import") { runImport(parsed) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(parsed.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 430)
        .background(Color.black.opacity(0.3).background(.ultraThinMaterial))
    }

    private func runImport(_ tasks: [TaskItem]) {
        guard !tasks.isEmpty else { return }
        let (fresh, duplicates) = store.partitionByDuplicateTitle(tasks)
        withAnimation(DS.Motion.standard) { store.insertAll(fresh) }
        importText = ""
        showImportSheet = false
        ImportDuplicatePrompt.resolve(.init(inserted: fresh.count, duplicates: duplicates),
                                      store: store)
    }

    /// A `.md`/`.json`/`.txt` file dropped on the task list opens the import
    /// sheet prefilled with its contents.
    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: URL.self) })
        else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url,
                  ["md", "markdown", "json", "txt"].contains(url.pathExtension.lowercased()),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                importText = text
                showImportSheet = true
            }
        }
        return true
    }

    /// Compact "Queue N" chip in the view bar — only when the queue has tasks.
    @ViewBuilder
    private var queueChip: some View {
        let count = queuedOpenTasks.count
        if count > 0 {
            Button { showQueuePanel = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "list.number")
                        .font(.system(size: 10, weight: .bold))
                    Text("Queue \(count)")
                        .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                }
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(Color.accentColor.opacity(0.16)))
                .contentShape(Capsule())
            }
            .buttonStyle(.pressableSubtle)
            .help("Focus queue — each finished session hands off to the next task")
            .popover(isPresented: $showQueuePanel, arrowEdge: .bottom) { queuePanel }
        }
    }

    /// Popover listing queued tasks in order: drag a row onto another to
    /// reorder (drop-before, the list's drag idiom), ✕ removes, Clear empties.
    private var queuePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Focus Queue").dsSectionLabel()
                Spacer()
                Button {
                    queue.clear()
                    showQueuePanel = false
                } label: {
                    Text("Clear")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.red.opacity(0.85))
                }
                .buttonStyle(.pressableSubtle)
                .help("Empty the queue")
            }
            Text("Each finished focus session hands off to the next task.")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Color.dsTertiary)
            VStack(spacing: 6) {
                ForEach(Array(queuedOpenTasks.enumerated()), id: \.element.id) { idx, task in
                    queueRow(task, position: idx + 1)
                        .draggable(task.id.uuidString)
                        .dropDestination(for: String.self) { dropped, _ in
                            guard let s = dropped.first, let dragged = UUID(uuidString: s),
                                  dragged != task.id else { return false }
                            moveQueued(dragged, before: task.id)
                            return true
                        }
                }
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private func queueRow(_ task: TaskItem, position: Int) -> some View {
        HStack(spacing: 8) {
            Text("\(position)")
                .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.dsSecondary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.white.opacity(0.08)))
            Circle()
                .fill(Color(hex: store.color(for: task.category)))
                .frame(width: 8, height: 8)
            Text(task.title)
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(Color.dsPrimary)
                .lineLimit(1)
            Spacer(minLength: 6)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.dsTertiary)
                .help("Drag to reorder")
            Button { withAnimation(DS.Motion.standard) { queue.remove(task.id) } } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dsTertiary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressableSubtle)
            .help("Remove from queue")
            .accessibilityLabel("Remove \(task.title) from queue")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
            .fill(Color.dsFill))
    }

    /// Reorders the id list so `dragged` sits before `target` (drop-before,
    /// matching the task rows' drag idiom).
    private func moveQueued(_ dragged: UUID, before target: UUID) {
        guard let src = queue.taskIDs.firstIndex(of: dragged),
              let dst = queue.taskIDs.firstIndex(of: target), src != dst else { return }
        withAnimation(DS.Motion.standard) {
            queue.move(from: IndexSet(integer: src), to: dst)
        }
    }

    /// Shown when the list has tasks but none match the current view/search.
    private var noResults: some View {
        VStack(spacing: 8) {
            Image(systemName: search.isEmpty ? filter.icon : "magnifyingglass")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.dsTertiary)
            Text(noResultsText)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.dsSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private var noResultsText: String {
        if !search.trimmingCharacters(in: .whitespaces).isEmpty {
            return "No tasks match “\(search)”."
        }
        switch filter {
        case .today:     return "Nothing due today — enjoy the breathing room."
        case .upcoming:  return "No upcoming tasks scheduled."
        case .completed: return "No completed tasks yet."
        case .all:       return "No open tasks. You're all clear."
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Row 1 — just type and press Return (or +). Nothing else needed.
            HStack(spacing: 10) {
                Button(action: add) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.pressableSubtle)
                .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Add task")

                TextField("Add a task…", text: $newTitle)
                    .textFieldStyle(.plain)
                    .font(.system(.title3, design: .rounded))
                    .focused($composerFocused)
                    .onSubmit(add)
            }

            // Smart-parse preview — chips for every token the quick-add syntax
            // found in the line (p1 / #tag / @project / times / ~2 / repeats).
            let parsed = TaskInputParser.parse(newTitle, now: Date())
            if hasSmartTokens(parsed) {
                parsedChips(parsed)
                    .transition(.opacity)
            }

            // Row 2 — the three you set most: category, priority, due. One tap each.
            HStack(spacing: 8) {
                categoryMenu
                PriorityMenu(priority: $newPriority, settings: timer.settings)
                dueMenu
                if !templates.templates.isEmpty { templateMenu }
                Spacer(minLength: 4)
                // Everything else (tags, estimate, repeat, project, notes).
                Button {
                    withAnimation(DS.Motion.gentle) { showDetails.toggle() }
                } label: {
                    chip(icon: "slider.horizontal.3",
                         text: showDetails ? "Less" : "More", active: showDetails)
                }
                .buttonStyle(.pressableSubtle)
                .help("Tags, estimate, repeat, project, notes")
            }

            if showDetails {
                detailsPanel
                    .transition(.asymmetric(
                        insertion: .push(from: .top).combined(with: .opacity),
                        removal: .opacity))
            }
        }
        .padding(12)
        .glassRounded(DS.Radius.lg, material: .thin)
    }

    /// Due-date chip: quick options in a menu, plus a "Pick a date…" that opens
    /// a graphical calendar popover for a specific day + time.
    private var dueMenu: some View {
        Menu {
            Button { setDue(dueAt(daysFromNow: 0)) } label: { Label("Today", systemImage: "star") }
            Button { setDue(dueAt(daysFromNow: 1)) } label: { Label("Tomorrow", systemImage: "sun.max") }
            Button { setDue(upcomingWeekend()) } label: { Label("This weekend", systemImage: "beach.umbrella") }
            Button { setDue(nextMonday()) } label: { Label("Next week", systemImage: "calendar") }
            Divider()
            Button { showCustomDue = true } label: { Label("Pick a date…", systemImage: "calendar.badge.clock") }
            if hasDue {
                Divider()
                Button(role: .destructive) { setDue(nil) } label: { Label("No date", systemImage: "xmark") }
            }
        } label: {
            chip(icon: hasDue ? "calendar.circle.fill" : "calendar", text: dueChipLabel, active: hasDue)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .popover(isPresented: $showCustomDue, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Due date").dsSectionLabel()
                SharinganCalendar(date: $newDue,
                              accent: timer.settings.theme.accent,
                              weekStartsOnMonday: timer.settings.weekStartsOnMonday)
                HStack {
                    Button("Clear") { setDue(nil) }
                        .buttonStyle(.pressableSubtle)
                        .foregroundStyle(Color.red.opacity(0.9))
                    Spacer()
                    Button("Set") {
                        // Picking a day sets a date-only due (no time of day).
                        newDue = DueDate.dateOnly(newDue)
                        hasDue = true; showCustomDue = false
                    }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
            .frame(width: 292)
        }
    }

    /// Human label for the due chip — "Today", "Tomorrow", or "MMM d".
    private var dueChipLabel: String {
        guard hasDue else { return "Due" }
        let cal = Calendar.current
        if cal.isDateInToday(newDue) { return "Today" }
        if cal.isDateInTomorrow(newDue) { return "Tomorrow" }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "MMM d"
        return f.string(from: newDue)
    }

    private func setDue(_ date: Date?) {
        if let d = date { newDue = d; hasDue = true } else { hasDue = false }
        showCustomDue = false
    }

    /// `days` from now at 9:00 AM.
    // Quick-pick due dates are date-only (start of day) — the time of day is
    // optional and only quick-add ("5pm") sets one.
    private func dueAt(daysFromNow days: Int) -> Date {
        let cal = Calendar.current
        let base = cal.date(byAdding: .day, value: days, to: Date()) ?? Date()
        return cal.startOfDay(for: base)
    }

    /// The coming Saturday (today if it's already Saturday), date-only.
    private func upcomingWeekend() -> Date {
        let cal = Calendar.current
        var d = Date()
        for _ in 0..<7 {
            if cal.component(.weekday, from: d) == 7 { break }   // 7 = Saturday
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return cal.startOfDay(for: d)
    }

    /// The next Monday (never today), date-only.
    private func nextMonday() -> Date {
        let cal = Calendar.current
        var d = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        for _ in 0..<7 {
            if cal.component(.weekday, from: d) == 2 { break }   // 2 = Monday
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return cal.startOfDay(for: d)
    }

    /// The category picker chip, reused in the primary row.
    private var categoryMenu: some View {
        Menu {
            ForEach(store.allCategories) { c in
                Button {
                    newCategory = c.name
                } label: {
                    Label(c.name, systemImage: newCategory == c.name ? "checkmark" : c.icon)
                }
            }
            Divider()
            Button {
                newCatName = ""
                withAnimation { showDetails = true; showNewCategory = true }
            } label: {
                Label("Add category…", systemImage: "plus")
            }
            Button {
                withAnimation { showDetails = true; showCategoryManager.toggle() }
            } label: {
                Label("Edit categories…", systemImage: "slider.horizontal.3")
            }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(newCategoryAccent).frame(width: 9, height: 9)
                Text(newCategory)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(newCategoryAccent.opacity(0.22)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// Expanded add-fields: tags, estimate, repeat, project, notes, due date.
    private var detailsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().overlay(Color.white.opacity(0.1))

            // Estimate + repeat (due & priority live in the always-visible row).
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text(newEstimate == 0 ? "Est —" : "Est \(newEstimate) 🍅")
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundStyle(Color.dsSecondary)
                    DSStepper(value: $newEstimate, range: 0...12)
                }

                Menu {
                    ForEach(Recurrence.allCases) { r in
                        Button(r.label) { newRecurrence = r }
                    }
                } label: {
                    chip(icon: "repeat",
                         text: newRecurrence == .none ? "No repeat" : newRecurrence.label,
                         active: newRecurrence != .none)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()

                HStack(spacing: 2) {
                    ForEach(PomodoroKind.allCases) { kind in
                        Button {
                            newKind = (newKind == kind) ? nil : kind
                        } label: {
                            Image(systemName: kind.systemImage)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(newKind == kind ? Color.white : .white.opacity(0.45))
                                .frame(width: 26, height: 22)
                                .background(
                                    Capsule().fill(newKind == kind
                                        ? Color.accentColor.opacity(0.22)
                                        : Color.white.opacity(0.06)))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.pressableSubtle)
                        .help("\(kind.label) pomodoro — tap again for Auto")
                    }
                }

                Spacer()
            }

            tagEditor
            projectPicker

            fieldBox {
                TextField("notes (optional)", text: $newNotes, axis: .vertical)
                    .lineLimit(1...3)
            }

            if showNewCategory { newCategoryForm }
            if showCategoryManager { categoryManager }

            if !store.tasks.isEmpty {
                HStack {
                    Spacer()
                    Button(action: exportCSV) {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                            .font(.system(.caption, design: .rounded))
                    }
                    .buttonStyle(.pressableSubtle)
                    .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .padding(.horizontal, 12).padding(.bottom, 12)
    }

    // MARK: - Smart-parse chips

    /// True when the composer line carries more than a bare title.
    private func hasSmartTokens(_ p: ParsedTaskInput) -> Bool {
        p.priority != .none || !p.tags.isEmpty || p.project != nil
            || p.dueDate != nil || p.estimatedPomodoros != nil || p.recurrence != .none
    }

    /// Compact preview row of everything the parser detected while typing.
    private func parsedChips(_ p: ParsedTaskInput) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if p.priority != .none {
                    parsedChip(p.priority.label,
                               tint: p.priority.colorHex.map { Color(hex: $0) })
                }
                ForEach(p.tags, id: \.self) { parsedChip("#\($0)") }
                if let project = p.project { parsedChip("@\(project)") }
                if let due = p.dueDate { parsedChip(parsedDueText(due)) }
                if let est = p.estimatedPomodoros { parsedChip("~\(est) 🍅") }
                if p.recurrence != .none { parsedChip(p.recurrence.label) }
            }
        }
    }

    /// One tiny token pill — same quiet capsule as the tag suggestions.
    private func parsedChip(_ text: String, tint: Color? = nil) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(tint ?? .white.opacity(0.7))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private func parsedDueText(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d HH:mm"
        return f.string(from: d)
    }

    // MARK: - Templates

    /// Icon-only chip: instantiate a saved template, or open the manager.
    private var templateMenu: some View {
        Menu {
            ForEach(templates.templates) { t in
                Button(t.name) {
                    if let task = templates.instantiate(t.id) {
                        withAnimation(DS.Motion.standard) { store.insert(task) }
                    }
                }
            }
            Divider()
            Button { showTemplateManager = true } label: {
                Label("Manage…", systemImage: "slider.horizontal.3")
            }
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 8).padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(0.06)))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("New task from template")
    }

    /// Small sheet listing templates with rename / delete.
    private var templateManager: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Templates")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Button { showTemplateManager = false } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.pressableSubtle)
            }
            if templates.templates.isEmpty {
                Text("No templates yet — right-click a task and choose “Save as Template…”.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.dsSecondary)
                    .padding(.vertical, 12)
            }
            ForEach(templates.templates) { t in
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.dsSecondary)
                        .frame(width: 20)
                    if templateRenameID == t.id {
                        TextField("Name", text: $templateRenameText)
                            .textFieldStyle(.plain)
                            .font(.system(.caption, design: .rounded).weight(.medium))
                            .onSubmit { commitTemplateRename(t.id) }
                    } else {
                        Text(t.name)
                            .font(.system(.caption, design: .rounded).weight(.medium))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Button {
                        templateRenameText = t.name; templateRenameID = t.id
                    } label: {
                        Image(systemName: "pencil").font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6)).frame(width: 22, height: 22)
                    }
                    .buttonStyle(.pressableSubtle).help("Rename")
                    Button { templates.delete(t.id) } label: {
                        Image(systemName: "trash").font(.system(size: 11))
                            .foregroundStyle(.red.opacity(0.8)).frame(width: 22, height: 22)
                    }
                    .buttonStyle(.pressableSubtle).help("Delete template")
                }
                .padding(.vertical, 3)
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(Color.black.opacity(0.3).background(.ultraThinMaterial))
    }

    private func commitTemplateRename(_ id: UUID) {
        templates.rename(id, to: templateRenameText)
        templateRenameID = nil
    }

    /// Date-only calendar for the "Snooze → Pick date…" action.
    private func snoozeSheet(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Snooze until").dsSectionLabel()
            SharinganCalendar(date: $snoozeDate, showsTime: false,
                          accent: timer.settings.theme.accent,
                          weekStartsOnMonday: timer.settings.weekStartsOnMonday)
            HStack {
                Button("Cancel") { snoozeTask = nil }
                    .buttonStyle(.pressableSubtle)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button("Snooze") {
                    store.snooze(task.id, to: snoozeDate)
                    snoozeTask = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 292)
        .background(Color.black.opacity(0.3).background(.ultraThinMaterial))
    }

    /// A small labelled pill used for menu triggers in the details panel.
    private func chip(icon: String, text: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            Text(text).font(.system(.caption, design: .rounded).weight(.medium))
        }
        .foregroundStyle(active ? Color.accentColor : .white.opacity(0.85))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    /// Wraps a text field in a subtle rounded box so it reads as an input.
    private func fieldBox<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .textFieldStyle(.plain)
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(Color.white.opacity(0.05)))
    }

    // MARK: - Project picker

    /// Selectable project menu — projects are a registry like categories, not
    /// free text. Offers every known project (colour dot + name), "No project",
    /// and an inline "New project…" name field.
    private var projectPicker: some View {
        HStack(spacing: 8) {
            Menu {
                Button {
                    newProject = ""
                } label: {
                    Label("No project", systemImage: newProject.isEmpty ? "checkmark" : "slash.circle")
                }
                if !store.allProjects.isEmpty { Divider() }
                ForEach(store.allProjects) { p in
                    Button {
                        newProject = p.name
                    } label: {
                        Label(p.name, systemImage: newProject == p.name ? "checkmark" : p.icon)
                    }
                }
                Divider()
                Button { showNewProject = true } label: {
                    Label("New project…", systemImage: "plus")
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: newProject.isEmpty ? "square.stack.3d.up"
                                                         : store.projectIcon(newProject))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(newProject.isEmpty ? Color.dsSecondary
                                         : Color(hex: store.projectColor(newProject)))
                    Text(newProject.isEmpty ? "Project" : newProject)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(newProject.isEmpty ? Color.dsSecondary : .white)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.dsTertiary)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .contentShape(Capsule())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Assign a project")

            if showNewProject {
                fieldBox {
                    TextField("New project name", text: $newProjectName)
                        .onSubmit(commitNewProject)
                }
                Button("Add", action: commitNewProject)
                    .buttonStyle(.pressableSubtle)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Spacer(minLength: 0)
        }
    }

    private func commitNewProject() {
        guard let name = store.addProject(name: newProjectName,
                                          colorHex: TaskCategory.palette[
                                            store.allProjects.count % TaskCategory.palette.count])
        else { return }
        newProject = name
        newProjectName = ""
        showNewProject = false
    }

    // MARK: - Tag editor

    /// Chip-based tag input: current tags as removable pills, an inline field
    /// (Return / comma commits), plus one-tap suggestions from existing tags.
    private var tagEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "tag")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(newTagList, id: \.self) { tag in
                            TaskTag(tag: tag, onRemove: { removeTag(tag) })
                                .transition(.scale.combined(with: .opacity))
                        }
                        TextField(newTagList.isEmpty ? "add tags" : "", text: $tagDraft)
                            .textFieldStyle(.plain)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(minWidth: 60)
                            .onChange(of: tagDraft) { _, v in
                                // Commit on comma/space so typing flows into chips.
                                if v.hasSuffix(",") || v.hasSuffix(" ") { commitTagDraft() }
                            }
                            .onSubmit { commitTagDraft() }
                    }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(Color.white.opacity(0.05)))

            // Suggestions — existing tags not already added.
            let suggestions = store.allTags.filter { !newTagList.contains($0) }.prefix(6)
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(suggestions), id: \.self) { tag in
                            Button { addTag(tag) } label: {
                                Text("#\(tag)")
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Capsule().fill(Color.white.opacity(0.06)))
                            }
                            .buttonStyle(.pressableSubtle)
                        }
                    }
                }
            }
        }
    }

    private func addTag(_ raw: String) {
        let t = raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "#", with: "")
        guard !t.isEmpty, !newTagList.contains(t) else { return }
        withAnimation(DS.Motion.standard) { newTagList.append(t) }
    }

    private func removeTag(_ tag: String) {
        withAnimation(DS.Motion.standard) {
            newTagList.removeAll { $0 == tag }
        }
    }

    private func commitTagDraft() {
        let parts = tagDraft.split(whereSeparator: { $0 == "," || $0 == " " })
        for p in parts { addTag(String(p)) }
        tagDraft = ""
    }

    /// Inline form to create a custom, color-coded category.
    private var newCategoryForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: newCatIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: newCatColor))
                    .frame(width: 20)
                TextField("New category name", text: $newCatName)
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .onSubmit(addCategory)
                Button("Add", action: addCategory)
                    .buttonStyle(.borderless)
                    .disabled(newCatName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button {
                    withAnimation { showNewCategory = false }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.pressableSubtle)
            }
            colorRow(selected: newCatColor) { newCatColor = $0 }
            iconRow(selected: newCatIcon) { newCatIcon = $0 }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }

    /// Palette swatches; calls `pick` on tap.
    private func colorRow(selected: String, pick: @escaping (String) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach(TaskCategory.palette, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(Color.white, lineWidth: selected == hex ? 2 : 0))
                    .onTapGesture { withAnimation(DS.Motion.hover) { pick(hex) } }
            }
        }
    }

    /// Icon choices; calls `pick` on tap.
    private func iconRow(selected: String, pick: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TaskCategory.iconChoices, id: \.self) { icon in
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected == icon ? .white : .white.opacity(0.6))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(selected == icon ? 0.18 : 0.05)))
                        .onTapGesture { withAnimation(DS.Motion.hover) { pick(icon) } }
                }
            }
        }
    }

    /// Inline manager: recolor / re-icon / rename / delete each category.
    private var categoryManager: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Categories")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Button {
                    withAnimation { showCategoryManager = false }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.pressableSubtle)
            }
            ForEach(store.allCategories) { c in
                categoryManagerRow(c)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }

    private func categoryManagerRow(_ c: TaskCategory) -> some View {
        let custom = store.isCustomCategory(c.name)
        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                // Icon menu.
                Menu {
                    ForEach(TaskCategory.iconChoices, id: \.self) { icon in
                        Button { store.setIcon(for: c.name, icon: icon) } label: {
                            Label(icon, systemImage: icon)
                        }
                    }
                } label: {
                    Image(systemName: c.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: c.colorHex))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()

                if renamingCategory == c.name {
                    TextField("Name", text: $renameText)
                        .textFieldStyle(.plain)
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .onSubmit { commitRename(c.name) }
                } else {
                    Text(c.name)
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundStyle(.white)
                    if !custom {
                        Text("preset")
                            .font(.system(size: 9, design: .rounded).weight(.bold))
                            .foregroundStyle(Color.dsTertiary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.white.opacity(0.06)))
                    }
                }
                Spacer()
                if custom {
                    Button {
                        renameText = c.name; renamingCategory = c.name
                    } label: {
                        Image(systemName: "pencil").font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6)).frame(width: 22, height: 22)
                    }
                    .buttonStyle(.pressableSubtle).help("Rename")
                    Button { store.deleteCategory(c.name) } label: {
                        Image(systemName: "trash").font(.system(size: 11))
                            .foregroundStyle(.red.opacity(0.8)).frame(width: 22, height: 22)
                    }
                    .buttonStyle(.pressableSubtle).help("Delete category")
                }
            }
            colorRow(selected: c.colorHex) { store.setColor(for: c.name, colorHex: $0) }
        }
        .padding(.vertical, 4)
    }

    private func commitRename(_ old: String) {
        let ok = store.renameCategory(old, to: renameText)
        if ok, newCategory == old { newCategory = renameText.trimmingCharacters(in: .whitespacesAndNewlines) }
        renamingCategory = nil
    }

    private func addCategory() {
        guard let name = store.addCategory(name: newCatName, colorHex: newCatColor, icon: newCatIcon) else { return }
        newCategory = name
        newCatName = ""
        newCatIcon = TaskCategory.iconChoices[0]
        withAnimation { showNewCategory = false }
    }

    private var emptyState: some View {
        let accent = timer.settings.theme.accent
        return VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.14))
                    .frame(width: 68, height: 68)
                Image(systemName: "checklist")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(accent)
            }
            VStack(spacing: 5) {
                Text("Plan your first task")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.dsPrimary)
                Text("Type a task above and press Return. Then hit \(Image(systemName: "play.fill")) to run a focus pomodoro on it.")
                    .font(.system(.caption, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.dsSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { showImportSheet = true } label: {
                Label("Import from Markdown or JSON", systemImage: "square.and.arrow.down")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(accent)
            }
            .buttonStyle(.pressableSubtle)
            .help("Paste a task list or drop a .md/.json file")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    /// Collapsible Trash bucket, pinned below the lists. Hidden when empty.
    /// Expands to show soft-deleted tasks, each with Restore and Delete-forever;
    /// a header "Empty" purges the lot (after a confirm).
    @ViewBuilder
    private var trashSection: some View {
        let trashed = store.trashedTasks
        if !trashed.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Button {
                        withAnimation(DS.Motion.gentle) { showTrash.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Trash").dsSectionLabel()
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .rotationEffect(.degrees(showTrash ? 0 : -90))
                        }
                        .foregroundStyle(Color.dsSecondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressableSubtle)
                    Spacer()
                    Text("\(trashed.count)")
                        .font(.system(.caption2, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.dsSecondary)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                    if showTrash {
                        Button { confirmEmptyTrash = true } label: {
                            Text("Empty")
                                .font(.system(.caption2, design: .rounded).weight(.semibold))
                                .foregroundStyle(Color.red.opacity(0.8))
                        }
                        .buttonStyle(.pressableSubtle)
                        .help("Delete every trashed task permanently")
                    }
                }
                if showTrash {
                    ForEach(trashed) { task in trashRow(task) }
                }
            }
            .padding(.top, 4)
        }
    }

    /// One row in the Trash — dimmed title, Restore, and Delete-forever.
    private func trashRow(_ task: TaskItem) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "trash")
                .font(.system(size: 13))
                .foregroundStyle(Color.dsTertiary)
                .frame(width: 24, height: 24)
            Text(task.title)
                .font(.system(.callout, design: .rounded).weight(.medium))
                .foregroundStyle(Color.dsSecondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            Button { withAnimation(DS.Motion.standard) { store.restore(task.id) } } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.dsSecondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressableSubtle)
            .help("Restore this task")
            .accessibilityLabel("Restore \(task.title)")
            Button { pendingPurgeTask = task } label: {
                Image(systemName: "trash.slash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.red.opacity(0.75))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressableSubtle)
            .help("Delete permanently")
            .accessibilityLabel("Delete \(task.title) permanently")
        }
        .padding(.leading, 14).padding(.trailing, 12).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(Color.dsFill.opacity(0.5))
        )
    }

    /// Slim controls row atop an expanded panel (only for multi-step tasks):
    /// step progress, then quiet sort / filter menus. The sort preference is
    /// shared with the picker's step rows; the filter applies to every panel.
    private func subtaskPanelBar(_ task: TaskItem) -> some View {
        HStack(spacing: 8) {
            let p = task.subtaskProgress
            Text("\(p.done)/\(p.total) steps")
                .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.dsTertiary)
            Spacer()
            Menu {
                SubtaskSortMenuItems(sortModeRaw: $subSortRaw)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(subSort != .manual ? Color.accentColor : Color.dsTertiary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help(subSort == .manual ? "Sort steps" : "Steps sorted by \(subSort.label)")
            Menu {
                SubtaskFilterMenuItems(settings: timer.settings,
                                       status: $subStatus,
                                       priorityFilter: $subPriority)
            } label: {
                let active = subStatus != .all || subPriority != nil
                Image(systemName: active ? "line.3.horizontal.decrease.circle.fill"
                                         : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(active ? Color.accentColor : Color.dsTertiary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Filter steps — status or priority")
        }
    }

    /// Expanded subtasks + notes for a task in the main window.
    private func subtaskPanel(_ task: TaskItem) -> some View {
        let shown = subSort.apply(task.subtasks.narrowed(status: subStatus,
                                                         priority: subPriority))
        return VStack(alignment: .leading, spacing: 5) {
            if task.subtasks.count > 1 {
                subtaskPanelBar(task)
            }
            if shown.isEmpty, !task.subtasks.isEmpty {
                Text("No steps match the filter")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.dsTertiary)
            }
            ForEach(shown) { sub in
                let isTarget = store.activeSubtaskID == sub.id
                HStack(spacing: 8) {
                    Button { store.toggleSubtask(task.id, sub.id) } label: {
                        Image(systemName: sub.isDone ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 13))
                            .foregroundStyle(sub.isDone ? Color.green : .secondary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressableSubtle)
                    .accessibilityLabel(sub.isDone ? "Mark \(sub.title) not done" : "Mark \(sub.title) done")
                    Text(sub.title)
                        .font(.system(.caption, design: .rounded))
                        .strikethrough(sub.isDone, color: .secondary)
                        .foregroundStyle(sub.isDone ? AnyShapeStyle(.secondary)
                                         : isTarget ? AnyShapeStyle(Color.accentColor)
                                         : AnyShapeStyle(.primary))
                    Spacer()
                    if timer.settings.showPomodoroBadges,
                       sub.pomodorosDone > 0 || sub.estimatedPomodoros != nil {
                        Text(sub.estimatedPomodoros.map { "🍅\(sub.pomodorosDone)/\($0)" }
                             ?? "🍅\(sub.pomodorosDone)")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    if let kind = sub.pomodoroKind {
                        Image(systemName: kind.systemImage)
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.secondary)
                            .help(kind.label)
                    }
                    if sub.priority != .none {
                        Text(timer.settings.priorityShortLabel(sub.priority))
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(timer.settings.priorityColorHex(sub.priority)
                                .map { Color(hex: $0) } ?? Color.dsSecondary)
                            .help("Step priority")
                    }
                    if !sub.isDone {
                        Button {
                            store.setActiveSubtask(taskID: task.id,
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
                    Button { store.deleteSubtask(task.id, sub.id) } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressableSubtle)
                    .accessibilityLabel("Delete subtask \(sub.title)")
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundStyle(.tint)
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
            }
        }
        .padding(.leading, 34).padding(.trailing, 12).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.03)))
    }

    private func commitSubtask(_ taskID: UUID) {
        let text = (subtaskDrafts[taskID] ?? "").trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let est = timer.settings.defaultSubtaskEstimate
        store.addSubtask(taskID, title: text, estimate: est > 0 ? est : nil)
        subtaskDrafts[taskID] = ""
    }

    /// Secondary metadata line — deliberately calm: due leads (most actionable),
    /// then the priority flag, up to two neutral tags (+N), and a quiet cluster
    /// of subtask progress / repeat / project. One line, one size. Category and
    /// priority own their color channels; tags stay neutral so nothing competes.
    @ViewBuilder
    private func metaRow(_ task: TaskItem) -> some View {
        // Only the essentials belong on the row — due date, priority, subtask
        // progress. Tags, project, recurrence and pomodoro-kind live in the task
        // editor; crowding them onto the row is what forced the ugly truncation.
        let hasMeta = task.dueDate != nil
            || task.priority != .none
            || task.subtaskProgress.total > 0
            || task.isPlannedToday()
        if hasMeta {
            // A horizontal ScrollView keeps the chips' combined width from
            // propagating up and widening the row past the popover (a plain
            // `.fixedSize()` HStack did exactly that and clipped both edges); the
            // chips stay `.fixedSize()` so nothing truncates mid-label.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    if let due = task.dueDate {
                        Label(dueText(due), systemImage: "calendar")
                            .foregroundStyle(task.isOverdue() ? Color.red : Color.dsSecondary)
                            .fixedSize()
                    }
                    if task.priority != .none, let hex = timer.settings.priorityColorHex(task.priority) {
                        Label(timer.settings.priorityShortLabel(task.priority), systemImage: "flag.fill")
                            .foregroundStyle(Color(hex: hex))
                            .fixedSize()
                    }
                    if task.subtaskProgress.total > 0 {
                        SubtaskProgressBadge(task.subtaskProgress).fixedSize()
                    }
                    if task.isPlannedToday() {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                            .fixedSize()
                            .help("On today's plan")
                    }
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .lineLimit(1)
            }
            .scrollDisabled(true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 1)
        }
    }

    /// The row's vertical "⋮" overflow menu — the full task action list, the
    /// same items as the right-click context menu. Delete routes through the
    /// "move to Trash?" confirmation rather than acting immediately.
    private func rowMenu(_ task: TaskItem) -> some View {
        Menu {
            rowMenuItems(task)
        } label: {
            // A borderless Menu's label is rendered by AppKit, which only picks
            // up Text and Image: Shape-drawn dots come out blank, a rotated
            // `ellipsis` loses its rotation, and a clear label leaves nothing
            // to click. The U+22EE character is real text, so it draws vertical
            // and carries a hit area.
            Text("⋮")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.dsSecondary)
                .frame(width: 16, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More actions")
        .accessibilityLabel("More actions for \(task.title)")
    }

    private func row(_ task: TaskItem) -> some View {
        let isActive = store.activeTaskID == task.id
        let accent = Color(hex: store.color(for: task.category))
        let hovered = hoveredTask == task.id
        let revealed = revealedTaskID == task.id
        let prio = timer.settings.priorityColorHex(task.priority).map { Color(hex: $0) }
        return HStack(spacing: 11) {
            // Checkbox — priority-tinted ring (Todoist-style), fills green when done.
            Button { store.toggleDone(task.id) } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(task.isDone ? Color.green
                                     : (prio ?? (hovered ? Color.dsPrimary : Color.dsSecondary)))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: task.isDone)
                    .animation(DS.Motion.celebrate, value: task.isDone)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressableSubtle)
            .help(task.priority == .none ? "" : timer.settings.priorityName(task.priority))
            .accessibilityLabel(task.isDone ? "Mark \(task.title) not done" : "Mark \(task.title) done")

            VStack(alignment: .leading, spacing: 3) {
                if editingTaskID == task.id {
                    TextField("Task name", text: $editingText)
                        .textFieldStyle(.plain)
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .focused($editFocused)
                        .onSubmit { commitEdit(task) }
                        .onExitCommand { editingTaskID = nil; editFocused = false }
                        .onAppear { editFocused = true }
                } else {
                    HStack(spacing: 6) {
                        if let code = task.code {
                            Text(code)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.dsTertiary)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Capsule().fill(Color.dsFill))
                                .fixedSize()
                                .help("Task code — shown in the notch while focusing")
                        }
                        Text(task.title)
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .strikethrough(task.isDone, color: .dsTertiary)
                            .foregroundStyle(task.isDone ? Color.dsTertiary : Color.dsPrimary)
                            .lineLimit(1)
                    }
                }
                metaRow(task)
            }
            // Sized before the row's trailing controls, so the title keeps its
            // width instead of splitting it evenly with them.
            .layoutPriority(1)
            Spacer(minLength: 4)

            // Subtle queue-position chip for queued tasks ("1", "2", …).
            if !task.isDone, let pos = queuePosition(task.id) {
                Text("\(pos)")
                    .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.dsSecondary)
                    .frame(minWidth: 10)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .help("Position \(pos) in the focus queue")
                    .accessibilityLabel("Focus queue position \(pos)")
            }

            // Main window: a chevron toggles the docked detail panel beside
            // the list. It flips to point back at the list while open, so the
            // same tap that opened the panel closes it.
            if embeddedInScroll {
                Button {
                    withAnimation(DS.Motion.panel) {
                        detailTask = (detailTask?.id == task.id) ? nil : task
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(detailTask?.id == task.id ? accent : Color.dsTertiary)
                        .rotationEffect(.degrees(detailTask?.id == task.id ? 180 : 0))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressableSubtle)
                .help("Open task details")
                .accessibilityLabel("Open details for \(task.title)")
            }

            // Hover-revealed disclosure chevron: hovering any row reveals a
            // chevron.down that toggles the inline subtasks/notes panel (where
            // steps are viewed *and added*); it flips to point up while open.
            // (Notch and widget stay chevron-free — full-width surfaces only.)
            if hovered || expanded.contains(task.id) {
                Button { toggleExpanded(task) } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(expanded.contains(task.id) ? accent : Color.dsTertiary)
                        .rotationEffect(.degrees(expanded.contains(task.id) ? 180 : 0))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressableSubtle)
                .help(expanded.contains(task.id) ? "Hide subtasks & notes" : "Show subtasks & notes")
                .accessibilityLabel("Toggle subtasks and notes for \(task.title)")
                .transition(.opacity)
            }

            // Every secondary action — including the subtasks/notes expander
            // the chevron used to own — lives in this one ⋮ menu, so the row
            // spends its width on the title instead of a control ladder.
            rowMenu(task)

            // Primary action + pomodoro progress in one control: at rest it's
            // the estimate ring with the done-count in the middle; on hover or
            // while active it fills and shows the play / pause glyph.
            focusRing(task, isActive: isActive, hovered: hovered, accent: accent)
        }
        .padding(.leading, 14).padding(.trailing, 12).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(isActive ? accent.opacity(0.16)
                      // The reveal flash — a beat stronger than the active tint
                      // so the row a deep-link landed on is unmistakable.
                      : revealed ? accent.opacity(0.24)
                      : (hovered ? Color.dsFillStrong : Color.dsFill))
        )
        // Left category accent bar (overlay so it matches the row height).
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent.opacity(task.isDone ? 0.3 : 1))
                .frame(width: 3)
                .padding(.vertical, 8)
        }
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(isActive || revealed ? accent.opacity(0.5) : .clear, lineWidth: 1)
        )
        .shadow(color: .black.opacity(hovered ? 0.18 : 0), radius: 6, y: 3)
        .scaleEffect(hovered && !isActive ? 1.006 : 1)
        .animation(DS.Motion.hover, value: hovered)
        // Whole-row hit area, so a double-click anywhere on the row (not just the
        // title's tight text bounds) toggles the subtask/notes panel. Buttons
        // inside the row keep their own single-click actions.
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { toggleExpanded(task) }
        .onHover { inside in
            if inside { hoveredTask = task.id }
            else if hoveredTask == task.id { hoveredTask = nil }
        }
        .contextMenu { rowMenuItems(task) }
    }

    /// The full task action menu — shared by the row's right-click context menu
    /// and its ⋮ overflow button so both offer identical actions.
    @ViewBuilder
    private func rowMenuItems(_ task: TaskItem) -> some View {
            if task.isDone {
                Button { store.toggleDone(task.id) } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
                Divider()
            }
            // The chevron's old job — only offered when there's something to
            // expand, same condition the chevron itself used.
            if task.subtaskProgress.total > 0 || !task.notes.isEmpty {
                Button {
                    withAnimation(DS.Motion.gentle) {
                        if expanded.contains(task.id) { expanded.remove(task.id) }
                        else { expanded.insert(task.id) }
                    }
                } label: {
                    Label(expanded.contains(task.id) ? "Hide subtasks & notes"
                                                     : "Subtasks & notes",
                          systemImage: "list.bullet.indent")
                }
                Divider()
            }
            Button {
                if embeddedInScroll {
                    withAnimation(DS.Motion.panel) { detailTask = task }
                } else {
                    editorTask = task
                }
            } label: {
                Label("Edit…", systemImage: "pencil")
            }
            Button { beginEdit(task) } label: {
                Label("Rename", systemImage: "character.cursor.ibeam")
            }
            Menu {
                ForEach(TaskPriority.levels(custom: timer.settings.customPriorityLevels)) { p in
                    Button {
                        store.setPriority(task.id, p)
                    } label: {
                        Label(timer.settings.priorityName(p),
                              systemImage: task.priority == p ? "checkmark" : "flag.fill")
                    }
                }
            } label: { Label("Priority", systemImage: "flag.fill") }
            Menu {
                ForEach(store.allCategories) { c in
                    Button {
                        var u = task; u.category = c.name; store.update(u)
                    } label: {
                        Label(c.name, systemImage: task.category == c.name ? "checkmark" : c.icon)
                    }
                }
            } label: { Label("Category", systemImage: "folder.fill") }
            Divider()
            Menu {
                // Subtask estimates outrank the task's own in every badge/ring
                // (effectiveEstimate) — say so here instead of looking broken.
                if let sum = task.subtaskEstimateTotal {
                    Text("Using subtask total: \(sum) 🍅").disabled(true)
                    Divider()
                }
                Button("No estimate") { store.setEstimate(task.id, nil) }
                Divider()
                ForEach(1...8, id: \.self) { n in
                    Button {
                        store.setEstimate(task.id, n)
                    } label: {
                        if task.estimatedPomodoros == n {
                            Label("\(n) 🍅", systemImage: "checkmark")
                        } else { Text("\(n) 🍅") }
                    }
                }
            } label: { Label("Estimate", systemImage: "target") }
            Button {
                store.togglePlannedToday(task.id)
            } label: {
                Label(task.isPlannedToday() ? "Remove from today" : "Plan for today",
                      systemImage: "sun.max.fill")
            }
            if !task.isDone {
                Menu {
                    Button { store.snoozeTomorrow(task.id) } label: {
                        Label("Tomorrow", systemImage: "sun.max")
                    }
                    Button { store.snoozeNextWeek(task.id) } label: {
                        Label("Next week", systemImage: "calendar")
                    }
                    Divider()
                    Button {
                        snoozeDate = task.dueDate
                            ?? Calendar.current.date(byAdding: .day, value: 1, to: Date())
                            ?? Date()
                        snoozeTask = task
                    } label: {
                        Label("Pick date…", systemImage: "calendar.badge.clock")
                    }
                } label: { Label("Snooze", systemImage: "zzz") }
            }
            if !task.isDone {
                let queued = queue.taskIDs.contains(task.id)
                Button {
                    withAnimation(DS.Motion.standard) {
                        if queued { queue.remove(task.id) } else { queue.enqueue(task.id) }
                    }
                } label: {
                    Label(queued ? "Remove from Focus Queue" : "Add to Focus Queue",
                          systemImage: queued ? "text.badge.minus" : "text.badge.plus")
                }
            }
            Divider()
            Button { store.duplicate(task.id) } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            Button {
                templateName = task.title
                templateNamingTask = task
            } label: {
                Label("Save as Template…", systemImage: "square.on.square.dashed")
            }
            Divider()
            Button { store.move(task.id, up: true) } label: {
                Label("Move up", systemImage: "arrow.up")
            }
            Button { store.move(task.id, up: false) } label: {
                Label("Move down", systemImage: "arrow.down")
            }
            Divider()
            Button(role: .destructive) { pendingDeleteTask = task } label: {
                Label("Delete", systemImage: "trash")
            }
    }

    // MARK: - Actions

    private func beginEdit(_ task: TaskItem) {
        editingText = task.title
        editingTaskID = task.id
    }

    /// Double-clicking a task's title expands (or collapses) its subtask/notes
    /// panel — the same toggle the ⋮ menu offers.
    private func toggleExpanded(_ task: TaskItem) {
        withAnimation(DS.Motion.gentle) {
            if expanded.contains(task.id) { expanded.remove(task.id) }
            else { expanded.insert(task.id) }
        }
    }

    /// Persist an inline title edit. Ignores empty or unchanged input.
    private func commitEdit(_ task: TaskItem) {
        defer { editingTaskID = nil; editFocused = false }
        let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != task.title else { return }
        var updated = task
        updated.title = trimmed
        store.update(updated)
    }

    private func add() {
        // A pasted document (multi-line, fenced, or JSON) bulk-imports right
        // from the composer — same parser as the import sheet. Duplicates
        // (same title as an open task) are held back behind a prompt.
        if let result = store.importIfDocument(newTitle) {
            newTitle = ""
            ImportDuplicatePrompt.resolve(result, store: store)
            return
        }
        commitTagDraft()   // fold any half-typed tag in before saving
        // Merge smart-parsed tokens with the manual pickers: whatever the user
        // set by hand wins; parsed values fill everything left untouched.
        let parsed = TaskInputParser.parse(newTitle, now: Date())
        var tags = newTagList
        for t in parsed.tags where !tags.contains(t) { tags.append(t) }
        store.add(title: parsed.title.isEmpty ? newTitle : parsed.title,
                  category: newCategory, tags: tags,
                  dueDate: hasDue ? newDue : parsed.dueDate,
                  estimatedPomodoros: newEstimate > 0 ? newEstimate : parsed.estimatedPomodoros,
                  recurrence: newRecurrence != .none ? newRecurrence : parsed.recurrence,
                  project: newProject.isEmpty ? parsed.project : newProject,
                  notes: newNotes,
                  priority: newPriority != .none ? newPriority : parsed.priority,
                  pomodoroKind: newKind)
        newTitle = ""
        newTagList = []
        tagDraft = ""
        hasDue = false
        showCustomDue = false
        newEstimate = 0
        newRecurrence = .none
        newProject = ""
        newNotes = ""
        newPriority = .none
        newKind = nil
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "sharingan-tasks.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? store.csv().write(to: url, atomically: true, encoding: .utf8)
    }

    private func dueText(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        // The time is optional: a due parked at midnight is a date-only deadline,
        // so its "HH:mm" is dropped everywhere it reads. Only a due carrying a
        // real time of day (from quick-add like "5pm") shows the clock.
        let dateOnly = DueDate.isDateOnly(d)
        if Calendar.current.isDateInToday(d) {
            f.dateFormat = dateOnly ? "'today'" : "'today' HH:mm"
        } else {
            f.dateFormat = dateOnly ? "MMM d" : "MMM d, HH:mm"
        }
        return f.string(from: d)
    }

    private func startFocus(on task: TaskItem) {
        if store.activeTaskID == task.id, timer.isRunning {
            timer.toggle() // pause
            return
        }
        store.selectFocusTarget(task.id)
        timer.startFocusSession(kind: store.resolvedActiveKind)
    }

    /// The focus button and the pomodoro-progress badge fused into one circle:
    /// at rest it's the estimate ring with the done-count in the middle; on
    /// hover or while active it fills accent and shows the play / pause glyph.
    @ViewBuilder
    private func focusRing(_ task: TaskItem, isActive: Bool, hovered: Bool, accent: Color) -> some View {
        let showRing = timer.settings.showPomodoroBadges && task.effectiveEstimate != nil
        let est = task.effectiveEstimate ?? 0
        let frac = est > 0 ? min(1, Double(task.pomodorosDone) / Double(est)) : 0
        let complete = est > 0 && task.pomodorosDone >= est
        let running = isActive && timer.isRunning
        // Show the glyph while engaged (or when there's no count to show);
        // otherwise the ring's centre holds the done-count, badge-style.
        let showGlyph = isActive || hovered || task.pomodorosDone == 0
        Button { startFocus(on: task) } label: {
            ZStack {
                if showRing {
                    Circle().stroke(Color.dsFillStrong, lineWidth: 3)
                    Circle().trim(from: 0, to: frac)
                        .stroke(complete ? Color.green : accent,
                                style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Circle()
                    .fill(isActive ? accent : (hovered ? accent.opacity(0.9) : Color.clear))
                    .padding(showRing ? 4.5 : 0)
                if showGlyph {
                    Image(systemName: running ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(isActive || hovered ? .white : Color.dsSecondary)
                } else {
                    Text("\(task.pomodorosDone)")
                        .font(.system(size: 10, design: .rounded).weight(.bold))
                        .foregroundStyle(complete ? Color.green : Color.dsPrimary)
                }
            }
            .frame(width: 30, height: 30)
            .shadow(color: isActive ? accent.opacity(0.5) : .clear, radius: 5)
            .contentShape(Circle())
        }
        .buttonStyle(.pressableSubtle)
        .help(showRing ? "\(task.pomodorosDone) of \(est) pomodoros — click to focus"
                       : "Run a focus pomodoro on this task")
        .accessibilityLabel(running ? "Pause focus" : "Start focus on \(task.title)")
    }
}
