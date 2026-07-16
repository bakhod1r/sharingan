import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SharinganCore

/// Identifiable wrapper so a Jira issue key can drive `.sheet(item:)`.
private struct JiraDetailKey: Identifiable { let key: String; var id: String { key } }

/// Identifiable wrapper so a category name can drive the push-preview `.sheet(item:)`.
private struct JiraPushCategory: Identifiable { let id: String }

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
    /// Issue key whose Jira detail sheet is open.
    @State private var jiraDetailKey: JiraDetailKey?

    /// Category whose unlinked tasks are being previewed before a Jira push.
    @State private var jiraPushCategory: JiraPushCategory?
    /// Last push result per category, shown next to that section's label.
    @State private var jiraPushStatus: [String: String] = [:]
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
    /// Infinite scroll: how many task rows are rendered right now. A sync can
    /// land 100+ tasks; we reveal a page at a time and grow the window (with an
    /// animation) as the sentinel at the bottom scrolls into view. Reset to the
    /// first page whenever the filter or search changes what's on screen.
    @State private var revealLimit = TasksView.revealPageSize
    private static let revealPageSize = 20
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
    @State private var tagFilter: String?
    @State private var priorityFilter: TaskPriority?
    /// Row being flash-highlighted after a reveal deep-link (see `AppRouter.
    /// revealTask`) — cleared a couple of seconds after the scroll lands.
    @State private var revealedTaskID: UUID?
    @ObservedObject private var router = AppRouter.shared

    private var newCategoryAccent: Color { Color(hex: store.color(for: newCategory)) }

    var body: some View {
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
                        taskList(groups)
                    } else {
                        ScrollView { taskList(groups).padding(.vertical, 2) }
                            .frame(height: 320)
                    }
                }
            }
        }
        .sheet(item: $editorTask) { task in
            TaskEditorView(task: task,
                           accent: timer.settings.theme.accent,
                           settings: timer.settings)
        }
        .sheet(item: $snoozeTask) { task in snoozeSheet(task) }
        .sheet(isPresented: $showTemplateManager) { templateManager }
        .sheet(isPresented: $showImportSheet) { importSheet }
        .sheet(item: $jiraDetailKey) { wrapped in
            if let model = AppServices.jiraService?.makeDetailModel(issueKey: wrapped.key) {
                JiraIssueDetailView(model: model)
                    .frame(minWidth: 560, minHeight: 520)
            }
        }
        .sheet(item: $jiraPushCategory) { wrapped in jiraPushSheet(wrapped.id) }
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
        .onAppear(perform: consumeDeepLink)
        .onChange(of: router.pendingTaskFilter) { consumeDeepLink() }
        .onChange(of: router.pendingTaskCategory) { consumeDeepLink() }
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
        if router.pendingTaskCategory != nil || router.pendingTaskTag != nil
            || router.pendingTaskPriority != nil {
            categoryFilter = router.pendingTaskCategory
            tagFilter = router.pendingTaskTag
            priorityFilter = router.pendingTaskPriority
            if filter == .completed { filter = .all }
            router.pendingTaskCategory = nil
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
            categoryFilter = nil; tagFilter = nil; priorityFilter = nil
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
        guard categoryFilter != nil || tagFilter != nil || priorityFilter != nil else {
            return groups
        }
        return groups.compactMap { g in
            if let c = categoryFilter, g.category != c { return nil }
            var items = g.items
            if let t = tagFilter { items = items.filter { $0.tags.contains(t) } }
            if let p = priorityFilter { items = items.filter { $0.priority == p } }
            return items.isEmpty ? nil : (g.category, items)
        }
    }

    /// Truncates the grouped list to `revealLimit` rows total, dropping empty
    /// groups. Returns the capped groups and whether anything was held back, so
    /// the list can show a "load more" sentinel.
    private func capped(_ groups: [(category: String, items: [TaskItem])])
        -> (groups: [(category: String, items: [TaskItem])], hasMore: Bool) {
        var remaining = revealLimit
        var out: [(category: String, items: [TaskItem])] = []
        var total = 0
        for g in groups {
            total += g.items.count
            guard remaining > 0 else { continue }
            if g.items.count <= remaining {
                out.append(g)
                remaining -= g.items.count
            } else {
                out.append((g.category, Array(g.items.prefix(remaining))))
                remaining = 0
            }
        }
        return (out, total > revealLimit)
    }

    /// "Filtered by …" pill (category / tag / priority) with a clear button.
    @ViewBuilder
    private var narrowFilterChip: some View {
        if categoryFilter != nil || tagFilter != nil || priorityFilter != nil {
            let (symbol, label, tint): (String, String, Color) = {
                if let c = categoryFilter { return ("#", c, Color(hex: store.color(for: c))) }
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
                        categoryFilter = nil; tagFilter = nil; priorityFilter = nil
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
        let window = capped(groups)
        return ScrollViewReader { proxy in
            // Lazy — and FLAT. A whole category used to be one child (a plain
            // VStack), so a 100-row group rendered all its rows the moment the
            // group was realized and stuttered on every window bump. Rows are
            // direct LazyVStack children now, so each one materializes only as
            // it scrolls into view; the sentinel grows the window a page at a
            // time.
            LazyVStack(alignment: .leading, spacing: 6) {
                if filter == .completed {
                    ForEach(doneGroups(groups), id: \.label) { group in
                        doneSectionHeader(group.label, count: group.items.count)
                        ForEach(group.items) { task in
                            row(task).id(task.id)   // scroll anchor for reveal deep-links
                        }
                    }
                } else {
                    ForEach(window.groups, id: \.category) { group in
                        sectionHeader(group.category, count: group.items.count)
                        ForEach(group.items) { task in
                            rowBlock(task)
                        }
                    }
                    if window.hasMore {
                        loadMoreSentinel
                            .transition(.opacity)
                    }
                }
            }
            // Both hooks matter: onChange for a reveal that arrives while the
            // list is on screen, onAppear for one consumed before it was (the
            // deep-link flipped the matrix / empty state back into the list).
            .onAppear { scrollToRevealed(proxy) }
            .onChange(of: revealedTaskID) { scrollToRevealed(proxy) }
            // A changed filter/search/sort re-lists from the top, so shrink the
            // window back to the first page.
            .onChange(of: filter) { revealLimit = Self.revealPageSize }
            .onChange(of: search) { revealLimit = Self.revealPageSize }
            .onChange(of: sortMode) { revealLimit = Self.revealPageSize }
        }
    }

    /// Sits below the last rendered row. When it scrolls into view it grows the
    /// window by one page — the animation on `revealLimit` fades the new rows in.
    private var loadMoreSentinel: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small).progressViewStyle(.circular)
            Text("Loading more…")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .onAppear {
            withAnimation(.easeOut(duration: 0.25)) {
                revealLimit += Self.revealPageSize
            }
        }
    }

    /// Centres the revealed row — one runloop later, so a filter change from
    /// the same deep-link has laid the row out before we scroll to it.
    private func scrollToRevealed(_ proxy: ScrollViewProxy) {
        guard let id = revealedTaskID else { return }
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

    /// One completion-day section of the Done history.
    private func doneSectionHeader(_ label: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.dsTertiary)
            Text(label).dsSectionLabel()
            Spacer()
            Text("\(count)")
                .font(.system(.caption2, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(Color.dsSecondary)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.06)))
        }
        .padding(.top, 10)
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
                jiraBoardToggle
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
                                priorityFilter: $priorityFilter)
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

    /// Opens the Jira sprint board — only while connected.
    @ViewBuilder
    private var jiraBoardToggle: some View {
        if AppServices.jiraService?.isConnected == true {
            Button { AppRouter.shared.openBoard(tab: .jira) } label: {
                Image(systemName: "rectangle.split.3x1")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.dsSecondary)
                    .frame(width: 27, height: 27)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .fill(Color.dsFill))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressableSubtle)
            .help("Jira sprint board — opens the Board section")
            .accessibilityLabel("Show Jira board")
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.dsTertiary)
            TextField("Search tasks", text: $search)
                .textFieldStyle(.plain)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.white)
                .focused($searchFocused)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.dsTertiary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressableSubtle)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous).fill(Color.dsFill))
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
                    Button("Set") { hasDue = true; showCustomDue = false }
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
    private func dueAt(daysFromNow days: Int) -> Date {
        let cal = Calendar.current
        let base = cal.date(byAdding: .day, value: days, to: Date()) ?? Date()
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: base) ?? base
    }

    /// The coming Saturday (today if it's already Saturday) at 9:00 AM.
    private func upcomingWeekend() -> Date {
        let cal = Calendar.current
        var d = Date()
        for _ in 0..<7 {
            if cal.component(.weekday, from: d) == 7 { break }   // 7 = Saturday
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: d) ?? d
    }

    /// The next Monday (never today) at 9:00 AM.
    private func nextMonday() -> Date {
        let cal = Calendar.current
        var d = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        for _ in 0..<7 {
            if cal.component(.weekday, from: d) == 2 { break }   // 2 = Monday
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: d) ?? d
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
            fieldBox { TextField("project", text: $newProject) }

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
                    Menu {
                        Button(role: .destructive) { templates.delete(t.id) } label: {
                            Label("Delete template", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6)).frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
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
                    Menu {
                        Button(role: .destructive) { store.deleteCategory(c.name) } label: {
                            Label("Delete category", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6)).frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
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

    // MARK: - Section

    /// Group header, a standalone lazy child — the top padding recreates the
    /// old 16pt inter-group gap on top of the list's 6pt row spacing.
    private func sectionHeader(_ category: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: store.icon(for: category))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(hex: store.color(for: category)))
            Text(category).dsSectionLabel()
            if let status = jiraPushStatus[category] {
                Text(status)
                    .font(.system(.caption2, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.dsSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            jiraCategoryMenu(category)
            Text("\(count)")
                .font(.system(.caption2, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(Color.dsSecondary)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.06)))
        }
        .padding(.top, 10)
    }

    /// Category-level Jira actions, behind a "…" menu and only while connected.
    /// The push itself is never one click away — it opens the preview sheet.
    @ViewBuilder
    private func jiraCategoryMenu(_ category: String) -> some View {
        if let jira = AppServices.jiraService, jira.isConnected {
            let unlinked = jira.unlinkedTasks(inCategory: category).count
            Menu {
                Button { jiraPushCategory = JiraPushCategory(id: category) } label: {
                    Label(unlinked == 0
                          ? "Push category to Jira"
                          : "Convert \(unlinked) task\(unlinked == 1 ? "" : "s") to Jira",
                          systemImage: "arrow.up.forward.app")
                }
                .disabled(unlinked == 0 || jira.isWorking)
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6)).frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Jira actions for \(category)")
        }
    }

    /// Preview + confirm for a category push. These issues land in a shared
    /// project, so the exact titles and the target project key are shown before
    /// anything is created.
    @ViewBuilder
    private func jiraPushSheet(_ category: String) -> some View {
        if let jira = AppServices.jiraService {
            let tasks = jira.unlinkedTasks(inCategory: category)
            let project = tasks.first.flatMap { jira.projectKey(forTask: $0) }
                ?? jira.categoryProjectMap[category]
            VStack(alignment: .leading, spacing: 14) {
                Text("Push \(category) to Jira").dsSectionLabel()

                Text(project.map {
                    "Creates \(tasks.count) issue\(tasks.count == 1 ? "" : "s") in \($0). Everyone on the project can see them."
                } ?? "No Jira project is mapped for \(category) — map one in Settings first.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.dsSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(tasks) { task in
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.dsSecondary)
                                Text(task.title)
                                    .font(.system(.caption, design: .rounded).weight(.medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)

                HStack {
                    Button("Cancel") { jiraPushCategory = nil }
                        .buttonStyle(.pressableSubtle)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Button("Create \(tasks.count) issue\(tasks.count == 1 ? "" : "s")") {
                        jiraPushCategory = nil
                        pushCategoryToJira(category)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(tasks.isEmpty || project == nil)
                }
            }
            .padding(16)
            .frame(width: 340)
            .background(Color.black.opacity(0.3).background(.ultraThinMaterial))
        }
    }

    /// Runs the confirmed push and parks the outcome in the section header.
    private func pushCategoryToJira(_ category: String) {
        guard let jira = AppServices.jiraService else { return }
        jiraPushStatus[category] = "Pushing…"
        Task {
            let created = await jira.pushUnlinkedTasks(inCategory: category)
            if let error = jira.lastErrorMessage, created == 0 {
                jiraPushStatus[category] = error
            } else {
                jiraPushStatus[category] = "Created \(created) issue\(created == 1 ? "" : "s")"
            }
        }
    }

    /// One task row as its own lazy child: drag/drop + the expanded subtask
    /// panel travel with the row.
    private func rowBlock(_ task: TaskItem) -> some View {
        VStack(spacing: 4) {
            row(task)
                .draggable(task.id.uuidString)
                .dropDestination(for: String.self) { dropped, _ in
                    guard let s = dropped.first, let id = UUID(uuidString: s) else { return false }
                    store.moveTask(id, before: task.id)
                    return true
                }
            if expanded.contains(task.id) {
                subtaskPanel(task)
            }
        }
        .id(task.id)   // scroll anchor for reveal deep-links
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
                    }
                    .buttonStyle(.pressableSubtle)
                    .accessibilityLabel(sub.isDone ? "Mark \(sub.title) not done" : "Mark \(sub.title) done")
                    Text(sub.title)
                        .font(.system(.caption, design: .rounded))
                        .strikethrough(sub.isDone, color: .secondary)
                        .foregroundStyle(sub.isDone ? AnyShapeStyle(.secondary)
                                         : isTarget ? AnyShapeStyle(Color.accentColor)
                                         : AnyShapeStyle(.primary))
                    // A nested Jira sub-task keeps its own key — worklogs and
                    // transitions target the sub-task issue, not the parent.
                    if let key = sub.jiraKey, sub.isJiraLinked {
                        JiraIssueBadge(key: key, issueType: "Sub-task", size: 8)
                    }
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
                        }
                        .buttonStyle(.pressableSubtle)
                        .help("Focus pomodoros credit this step")
                        .accessibilityLabel(isTarget ? "Stop targeting \(sub.title)"
                                                     : "Target focus at \(sub.title)")
                    }
                    Button { store.deleteSubtask(task.id, sub.id) } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
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
        let hasMeta = !task.tags.isEmpty || task.dueDate != nil
            || task.recurrence != .none || task.project != nil
            || task.subtaskProgress.total > 0 || task.priority != .none
            || task.pomodoroKind != nil || task.isJiraLinked
        if hasMeta {
            HStack(spacing: 7) {
                // Leads the row: the key answers "where did this come from"
                // before anything else on the line.
                if let key = task.jiraKey, task.isJiraLinked {
                    JiraIssueBadge(key: key, issueType: task.jiraIssueType)
                    JiraStatusChip(task: task)
                }
                if let due = task.dueDate {
                    Label(dueText(due), systemImage: "calendar")
                        .foregroundStyle(task.isOverdue() ? Color.red : Color.dsSecondary)
                }
                if task.priority != .none, let hex = timer.settings.priorityColorHex(task.priority) {
                    Label(timer.settings.priorityShortLabel(task.priority), systemImage: "flag.fill")
                        .foregroundStyle(Color(hex: hex))
                }
                ForEach(task.tags.prefix(2), id: \.self) { t in
                    TaskTag(tag: t,
                            tint: timer.settings.tagColorHex(t).map { Color(hex: $0) })
                }
                if task.tags.count > 2 { TaskTagOverflow(count: task.tags.count - 2) }
                if task.subtaskProgress.total > 0 {
                    SubtaskProgressBadge(task.subtaskProgress)
                }
                if task.recurrence != .none {
                    Image(systemName: "repeat")
                        .foregroundStyle(Color.dsTertiary)
                        .help(task.recurrence.label)
                }
                if let project = task.project {
                    Label(project, systemImage: "folder")
                        .foregroundStyle(Color.dsTertiary)
                }
                if let kind = task.pomodoroKind {
                    Label(kind.label, systemImage: kind.systemImage)
                        .foregroundStyle(Color.dsTertiary)
                }
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.top, 1)
        }
    }

    /// One icon in the hover action pill (edit / delete).
    private func rowActionButton(_ icon: String, _ help: String,
                                 danger: Bool = false,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(danger ? Color.red.opacity(0.75) : Color.dsSecondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressableSubtle)
        .help(help)
        .accessibilityLabel(help)
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
                    Text(task.title)
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .strikethrough(task.isDone, color: .dsTertiary)
                        .foregroundStyle(task.isDone ? Color.dsTertiary : Color.dsPrimary)
                        .lineLimit(1)
                        .onTapGesture(count: 2) { beginEdit(task) }
                }
                metaRow(task)
            }
            Spacer(minLength: 6)

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

            if task.isPlannedToday() {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .help("On today's plan")
            }

            // Estimate progress ring (or a plain count when no estimate).
            // Estimate is the subtask sum when subtasks carry estimates.
            // `TaskPomodoroBadge` is that pair of cases, shared with the notch.
            if timer.settings.showPomodoroBadges {
                TaskPomodoroBadge(done: task.pomodorosDone,
                                  estimate: task.effectiveEstimate, color: accent)
            }

            // Expand chevron — an info affordance, only when there's more to see.
            if task.subtaskProgress.total > 0 || !task.notes.isEmpty {
                Button {
                    withAnimation(DS.Motion.gentle) {
                        if expanded.contains(task.id) { expanded.remove(task.id) }
                        else { expanded.insert(task.id) }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.dsTertiary)
                        .rotationEffect(.degrees(expanded.contains(task.id) ? 180 : 0))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressableSubtle)
                .help("Subtasks & notes")
                .accessibilityLabel("Show subtasks and notes")
            }

            // Secondary actions live together in one quiet pill that only
            // appears on hover — separated from the primary Focus button so the
            // row reads calm at rest and Delete never sits under the cursor's
            // path to Play.
            // Always present (not conditionally inserted) so hovering never
            // changes the row's layout width — a conditional insert here would
            // shove the Play button left under the cursor, causing the row's
            // hover state to flicker on/off in a feedback loop.
            // Destructive actions hide behind "…" — a bare trash button on the
            // row invites misclicks and reads noisy.
            Menu {
                Button { editorTask = task } label: {
                    Label("Edit task…", systemImage: "pencil")
                }
                if task.isJiraLinked, let key = task.jiraKey {
                    Button { jiraDetailKey = JiraDetailKey(key: key) } label: {
                        Label("Jira details…", systemImage: "link")
                    }
                    if let url = task.jiraBrowseURL {
                        Button { NSWorkspace.shared.open(url) } label: {
                            Label("Open in Jira", systemImage: "arrow.up.forward.app")
                        }
                    }
                } else if AppServices.jiraService?.isConnected == true {
                    Button { Task { await AppServices.jiraService?.createIssue(from: task) } } label: {
                        Label("Create Jira issue", systemImage: "arrow.up.forward.app")
                    }
                }
                Divider()
                Button(role: .destructive) { store.delete(task.id) } label: {
                    Label("Delete task", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 24, height: 22)
                    .contentShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(2)
            .background(Capsule().fill(Color.white.opacity(0.07)))
            .opacity(hovered ? 1 : 0)
            .scaleEffect(hovered ? 1 : 0.9, anchor: .trailing)
            .allowsHitTesting(hovered)

            // Primary action: Focus. A filled circle so it's unmistakably THE
            // button — accent when active/hovered, calm at rest.
            Button { startFocus(on: task) } label: {
                Image(systemName: isActive && timer.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(isActive || hovered ? .white : Color.dsSecondary)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle().fill(isActive ? accent
                                      : (hovered ? accent.opacity(0.9) : Color.white.opacity(0.06))))
                    .shadow(color: isActive ? accent.opacity(0.5) : .clear, radius: 5)
                    .contentShape(Circle())
            }
            .buttonStyle(.pressableSubtle)
            .help("Run a focus pomodoro on this task")
            .accessibilityLabel(isActive && timer.isRunning ? "Pause focus" : "Start focus on \(task.title)")
        }
        .animation(DS.Motion.hover, value: hovered)
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
        .onHover { inside in
            if inside { hoveredTask = task.id }
            else if hoveredTask == task.id { hoveredTask = nil }
        }
        .contextMenu {
            if task.isDone {
                Button { store.toggleDone(task.id) } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
                Divider()
            }
            Button { editorTask = task } label: {
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
            Button(role: .destructive) { store.delete(task.id) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    private func beginEdit(_ task: TaskItem) {
        editingText = task.title
        editingTaskID = task.id
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
        // `jira SHRGN-5` isn't a new task — it pulls that issue in as a linked
        // one, through the same hierarchy-aware sync as the bulk import.
        if let key = parsed.jiraIssueKey, let jira = AppServices.jiraService, jira.isConnected {
            newTitle = ""
            Task { await jira.importIssue(key: key) }
            return
        }
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
        f.dateFormat = Calendar.current.isDateInToday(d) ? "'today' HH:mm" : "MMM d, HH:mm"
        return f.string(from: d)
    }

    private func startFocus(on task: TaskItem) {
        if store.activeTaskID == task.id, timer.isRunning {
            timer.toggle() // pause
            return
        }
        store.setActive(task.id)
        timer.startFocusSession(kind: store.resolvedActiveKind)
    }
}
