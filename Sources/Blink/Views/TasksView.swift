import SwiftUI
import AppKit
import UniformTypeIdentifiers
import BlinkCore

struct TasksView: View {
    @ObservedObject var timer: PomodoroTimer
    /// When true (main window), rows flow into the parent scroll view instead of
    /// the fixed-height inner scroll used by the compact menu-bar popover.
    var embeddedInScroll: Bool = false
    @ObservedObject private var store = TaskStore.shared

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
    /// Tasks whose subtasks/notes panel is expanded.
    @State private var expanded: Set<UUID> = []
    @State private var subtaskDrafts: [UUID: String] = [:]
    /// Inline title editing (double-click a row or the context-menu "Edit").
    @State private var editingTaskID: UUID?
    @State private var editingText = ""
    @FocusState private var editFocused: Bool
    /// Row the pointer is over — reveals its delete button.
    @State private var hoveredTask: UUID?

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

    private var newCategoryAccent: Color { Color(hex: store.color(for: newCategory)) }

    var body: some View {
        VStack(spacing: 12) {
            composer

            if store.tasks.isEmpty {
                emptyState
            } else if embeddedInScroll {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(store.grouped(), id: \.category) { group in
                        section(group.category, group.items)
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(store.grouped(), id: \.category) { group in
                            section(group.category, group.items)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 320)
            }
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

                TextField("Add a task…", text: $newTitle, onCommit: add)
                    .textFieldStyle(.plain)
                    .font(.system(.title3, design: .rounded))
                    .focused($composerFocused)
            }

            // Row 2 — the three you set most: category, priority, due. One tap each.
            HStack(spacing: 8) {
                categoryMenu
                priorityMenu
                dueMenu
                Spacer(minLength: 4)
                // Everything else (tags, estimate, repeat, project, notes).
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showDetails.toggle() }
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

    /// Priority flag menu (P1–P4) for the quick-setter row.
    private var priorityMenu: some View {
        Menu {
            ForEach(TaskPriority.allCases.reversed()) { p in
                Button {
                    newPriority = p
                } label: {
                    if p == .none {
                        Label(p.menuLabel, systemImage: newPriority == p ? "checkmark" : "flag.slash")
                    } else {
                        Label(p.menuLabel, systemImage: newPriority == p ? "checkmark" : "flag.fill")
                    }
                }
            }
        } label: {
            let hex = newPriority.colorHex
            HStack(spacing: 5) {
                Image(systemName: newPriority == .none ? "flag" : "flag.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(newPriority == .none ? "Priority" : newPriority.label)
                    .font(.system(.caption, design: .rounded).weight(.medium))
            }
            .foregroundStyle(hex.map { Color(hex: $0) } ?? Color.dsSecondary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(Color.dsFill))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
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
                DatePicker("", selection: $newDue,
                           displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .frame(width: 260)
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
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
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
                            HStack(spacing: 4) {
                                Text("#\(tag)")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                Button { removeTag(tag) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.8))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.pressableSubtle)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(Color.accentColor.opacity(0.28)))
                            .transition(.scale.combined(with: .opacity))
                        }
                        TextField(newTagList.isEmpty ? "add tags" : "", text: $tagDraft)
                            .textFieldStyle(.plain)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(minWidth: 60)
                            .onChange(of: tagDraft) { v in
                                // Commit on comma/space so typing flows into chips.
                                if v.hasSuffix(",") || v.hasSuffix(" ") { commitTagDraft() }
                            }
                            .onSubmit { commitTagDraft() }
                    }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
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
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { newTagList.append(t) }
    }

    private func removeTag(_ tag: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
                TextField("New category name", text: $newCatName, onCommit: addCategory)
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .rounded).weight(.medium))
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
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { pick(hex) } }
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
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { pick(icon) } }
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
                    TextField("Name", text: $renameText, onCommit: { commitRename(c.name) })
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
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("No tasks yet")
                .font(.system(.callout, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
            Text("Add one above, then press ▶ to run a focus pomodoro on it.")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Section

    private func section(_ category: String, _ items: [TaskItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: store.icon(for: category))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(hex: store.color(for: category)))
                Text(category).dsSectionLabel()
                Spacer()
                Text("\(items.filter { !$0.isDone }.count)")
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.dsTertiary)
            }
            ForEach(items) { task in
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
            }
        }
    }

    /// Expanded subtasks + notes for a task in the main window.
    private func subtaskPanel(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(task.subtasks) { sub in
                HStack(spacing: 8) {
                    Button { store.toggleSubtask(task.id, sub.id) } label: {
                        Image(systemName: sub.isDone ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 13))
                            .foregroundStyle(sub.isDone ? Color.green : .secondary)
                    }
                    .buttonStyle(.pressableSubtle)
                    Text(sub.title)
                        .font(.system(.caption, design: .rounded))
                        .strikethrough(sub.isDone, color: .secondary)
                        .foregroundStyle(sub.isDone ? .secondary : .primary)
                    Spacer()
                    Button { store.deleteSubtask(task.id, sub.id) } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.pressableSubtle)
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundStyle(.tint)
                TextField("Add step…", text: Binding(
                    get: { subtaskDrafts[task.id] ?? "" },
                    set: { subtaskDrafts[task.id] = $0 }
                ), onCommit: { commitSubtask(task.id) })
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
        store.addSubtask(taskID, title: text)
        subtaskDrafts[taskID] = ""
    }

    /// Secondary metadata line: tags, project, repeat, subtasks, due.
    @ViewBuilder
    private func metaRow(_ task: TaskItem, accent: Color) -> some View {
        let hasMeta = !task.tags.isEmpty || task.dueDate != nil
            || task.recurrence != .none || task.project != nil
            || task.subtaskProgress.total > 0 || task.priority != .none
        if hasMeta {
            HStack(spacing: 7) {
                if task.priority != .none, let hex = task.priority.colorHex {
                    Label(task.priority.label, systemImage: "flag.fill")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: hex))
                }
                if let project = task.project {
                    Label(project, systemImage: "folder.fill")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.dsSecondary)
                }
                ForEach(task.tags.prefix(3), id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(accent.opacity(0.22), in: Capsule())
                        .foregroundStyle(accent)
                }
                if task.recurrence != .none {
                    Image(systemName: "repeat")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.dsSecondary)
                        .help(task.recurrence.label)
                }
                if task.subtaskProgress.total > 0 {
                    Label("\(task.subtaskProgress.done)/\(task.subtaskProgress.total)",
                          systemImage: "checklist")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(task.subtaskProgress.done == task.subtaskProgress.total
                                         ? Color.green : Color.dsSecondary)
                }
                if let due = task.dueDate {
                    Label(dueText(due), systemImage: "calendar")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(task.isOverdue() ? Color.red : Color.dsSecondary)
                }
            }
        }
    }

    /// A small circular progress ring for pomodoro estimates (done / total).
    private func estimateRing(done: Int, total: Int, color: Color) -> some View {
        let frac = min(1, Double(done) / Double(max(1, total)))
        let complete = done >= total
        return ZStack {
            Circle().stroke(Color.dsFillStrong, lineWidth: 3)
            Circle()
                .trim(from: 0, to: frac)
                .stroke(complete ? Color.green : color,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(done)")
                .font(.system(size: 10, design: .rounded).weight(.bold))
                .foregroundStyle(complete ? Color.green : Color.dsPrimary)
        }
        .frame(width: 26, height: 26)
        .help("\(done) of \(total) pomodoros")
    }

    private func row(_ task: TaskItem) -> some View {
        let isActive = store.activeTaskID == task.id
        let accent = Color(hex: store.color(for: task.category))
        let hovered = hoveredTask == task.id
        let prio = task.priority.colorHex.map { Color(hex: $0) }
        return HStack(spacing: 11) {
            // Checkbox — priority-tinted ring (Todoist-style), fills green when done.
            Button { store.toggleDone(task.id) } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(task.isDone ? Color.green
                                     : (prio ?? (hovered ? accent : Color.dsSecondary)))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressableSubtle)
            .help(task.priority == .none ? "" : task.priority.menuLabel)

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
                metaRow(task, accent: accent)
            }
            Spacer(minLength: 6)

            if task.isPlannedToday() {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .help("On today's plan")
            }

            // Estimate progress ring (or a plain count when no estimate).
            if let est = task.estimatedPomodoros {
                estimateRing(done: task.pomodorosDone, total: est, color: accent)
            } else if task.pomodorosDone > 0 {
                Text("🍅\(task.pomodorosDone)")
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.dsSecondary)
            }

            if task.subtaskProgress.total > 0 || !task.notes.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if expanded.contains(task.id) { expanded.remove(task.id) }
                        else { expanded.insert(task.id) }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.dsSecondary)
                        .rotationEffect(.degrees(expanded.contains(task.id) ? 180 : 0))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressableSubtle)
                .help("Subtasks & notes")
            }

            Button { store.delete(task.id) } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dsSecondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressableSubtle)
            .opacity(hovered ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: hovered)
            .help("Delete task")

            Button { startFocus(on: task) } label: {
                Image(systemName: isActive && timer.isRunning ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(isActive ? accent : (hovered ? Color.dsPrimary : Color.dsSecondary))
                    .shadow(color: isActive ? accent.opacity(0.5) : .clear, radius: 5)
            }
            .buttonStyle(.pressableSubtle)
            .help("Run a focus pomodoro on this task")
        }
        .padding(.leading, 14).padding(.trailing, 12).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(isActive ? accent.opacity(0.16)
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
                .stroke(isActive ? accent.opacity(0.5) : .clear, lineWidth: 1)
        )
        .shadow(color: .black.opacity(hovered ? 0.18 : 0), radius: 6, y: 3)
        .scaleEffect(hovered && !isActive ? 1.006 : 1)
        .animation(.easeInOut(duration: 0.15), value: hovered)
        .onHover { inside in
            if inside { hoveredTask = task.id }
            else if hoveredTask == task.id { hoveredTask = nil }
        }
        .contextMenu {
            Button { beginEdit(task) } label: {
                Label("Edit", systemImage: "pencil")
            }
            Menu {
                ForEach(TaskPriority.allCases.reversed()) { p in
                    Button {
                        store.setPriority(task.id, p)
                    } label: {
                        Label(p.menuLabel,
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
        commitTagDraft()   // fold any half-typed tag in before saving
        store.add(title: newTitle, category: newCategory, tags: newTagList,
                  dueDate: hasDue ? newDue : nil,
                  estimatedPomodoros: newEstimate > 0 ? newEstimate : nil,
                  recurrence: newRecurrence,
                  project: newProject.isEmpty ? nil : newProject,
                  notes: newNotes,
                  priority: newPriority)
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
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "blink-tasks.csv"
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
        if timer.phase != .focus { timer.stop() }
        timer.start()
    }
}
