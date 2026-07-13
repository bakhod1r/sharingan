import SwiftUI
import SharinganCore

/// Full-task editor presented as a sheet. Unlike the old inline title-only edit,
/// this lets you change EVERY field of an existing task — category, priority,
/// due date, tags, estimate, recurrence, project, notes and subtasks — then
/// saves the whole thing atomically through `store.update`.
struct TaskEditorView: View {
    @ObservedObject private var store = TaskStore.shared
    @Environment(\.dismiss) private var dismiss

    /// A local working copy; nothing touches the store until Save.
    @State private var draft: TaskItem
    @State private var tagDraft = ""
    @State private var subtaskDraft = ""
    @State private var showCustomDue = false
    @FocusState private var titleFocused: Bool

    var accent: Color = .paletteFocusStart
    /// Snapshot of app settings for defaults & badge visibility (value copy is
    /// fine for a modal sheet). No default value on purpose: a call site that
    /// forgets it would silently run the editor on factory settings.
    let settings: PomodoroSettings

    init(task: TaskItem, accent: Color = .paletteFocusStart,
         settings: PomodoroSettings) {
        _draft = State(initialValue: task)
        self.accent = accent
        self.settings = settings
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.12))
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    titleField
                    chipsRow
                    tagsSection
                    estimateRecurrenceRow
                    projectField
                    notesSection
                    subtasksSection
                    deleteButton
                }
                .padding(20)
            }
        }
        // A comfortable default that can grow — long notes/subtask lists no
        // longer scroll inside a locked 420×560 box.
        .frame(minWidth: 440, idealWidth: 460, maxWidth: 620,
               minHeight: 560, idealHeight: 640, maxHeight: 820)
        .background(editorBackground)
        .tint(accent)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .buttonStyle(.pressableSubtle)
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text("Edit task")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
            Spacer()
            Button("Save") { save() }
                .buttonStyle(.pressableSubtle)
                .fontWeight(.bold)
                .foregroundStyle(accent)
                .keyboardShortcut(.defaultAction)
                .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    // MARK: - Title

    private var titleField: some View {
        TextField("Task name", text: $draft.title)
            .textFieldStyle(.plain)
            .font(.system(.title2, design: .rounded).weight(.semibold))
            .foregroundStyle(.white)
            .focused($titleFocused)
            .padding(.vertical, 10).padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(Color.white.opacity(0.06)))
    }

    // MARK: - Category / Priority / Due chips

    private var chipsRow: some View {
        HStack(spacing: 8) {
            categoryMenu
            PriorityMenu(priority: $draft.priority, settings: settings)
            dueMenu
            Spacer(minLength: 0)
        }
    }

    private var categoryMenu: some View {
        Menu {
            ForEach(store.allCategories) { c in
                Button {
                    draft.category = c.name
                } label: {
                    Label(c.name, systemImage: draft.category == c.name ? "checkmark" : c.icon)
                }
            }
        } label: {
            let color = Color(hex: store.color(for: draft.category))
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 9, height: 9)
                Text(draft.category)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(color.opacity(0.22)))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }

    private var dueMenu: some View {
        Menu {
            Button { setDue(dueAt(0)) } label: { Label("Today", systemImage: "star") }
            Button { setDue(dueAt(1)) } label: { Label("Tomorrow", systemImage: "sun.max") }
            Button { setDue(upcomingWeekend()) } label: { Label("This weekend", systemImage: "beach.umbrella") }
            Button { setDue(nextMonday()) } label: { Label("Next week", systemImage: "calendar") }
            Divider()
            Button { showCustomDue = true } label: { Label("Pick a date…", systemImage: "calendar.badge.clock") }
            if draft.dueDate != nil {
                Divider()
                Button(role: .destructive) { draft.dueDate = nil } label: {
                    Label("No date", systemImage: "xmark")
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: draft.dueDate == nil ? "calendar" : "calendar.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(dueLabel)
                    .font(.system(.caption, design: .rounded).weight(.medium))
            }
            .foregroundStyle(draft.dueDate == nil ? Color.dsSecondary : accent)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.06)))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .popover(isPresented: $showCustomDue, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Due date").dsSectionLabel()
                BlinkCalendar(date: Binding(
                    get: { draft.dueDate ?? Date() },
                    set: { draft.dueDate = $0 }),
                    accent: accent,
                    weekStartsOnMonday: settings.weekStartsOnMonday)
                HStack {
                    Button("Clear") { draft.dueDate = nil; showCustomDue = false }
                        .buttonStyle(.plain).foregroundStyle(.red.opacity(0.9))
                    Spacer()
                    Button("Done") { showCustomDue = false }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(16).frame(width: 292)
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags").dsSectionLabel()
            FlowTags(tags: draft.tags,
                     onRemove: { tag in draft.tags.removeAll { $0 == tag } })
            HStack(spacing: 6) {
                Image(systemName: "number").font(.system(size: 11)).foregroundStyle(Color.dsTertiary)
                TextField("add a tag", text: $tagDraft)
                    .textFieldStyle(.plain)
                    .font(.system(.callout, design: .rounded))
                    .onChange(of: tagDraft) { _, v in
                        if v.hasSuffix(",") || v.hasSuffix(" ") { commitTag() }
                    }
                    .onSubmit { commitTag() }
            }
            .padding(.vertical, 7).padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(Color.white.opacity(0.05)))
            let suggestions = store.allTags.filter { !draft.tags.contains($0) }.prefix(6)
            if !suggestions.isEmpty {
                FlowTags(tags: Array(suggestions), muted: true,
                         onTap: { draft.tags.append($0) })
            }
        }
    }

    // MARK: - Estimate / Recurrence

    private var estimateRecurrenceRow: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Estimate").dsSectionLabel()
                Menu {
                    Button("No estimate") { draft.estimatedPomodoros = nil }
                    Divider()
                    ForEach(1...8, id: \.self) { n in
                        Button("\(n) 🍅") { draft.estimatedPomodoros = n }
                    }
                } label: {
                    chip(draft.estimatedPomodoros.map { "\($0) 🍅" } ?? "None",
                         icon: "target")
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Pomodoro").dsSectionLabel()
                Menu {
                    Button("Default") { draft.pomodoroKind = nil }
                    Divider()
                    ForEach(PomodoroKind.allCases) { kind in
                        Button {
                            draft.pomodoroKind = kind
                        } label: {
                            let cfg = settings.config(for: kind)
                            Label("\(kind.label) · \(cfg.focusMinutes)/\(cfg.breakMinutes) min",
                                  systemImage: draft.pomodoroKind == kind
                                      ? "checkmark" : kind.systemImage)
                        }
                    }
                } label: {
                    chip(kindChipText(draft.pomodoroKind),
                         icon: draft.pomodoroKind?.systemImage ?? "timer")
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Which pomodoro size focus sessions on this task use")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Repeat").dsSectionLabel()
                HStack(spacing: 8) {
                    Menu {
                        ForEach(Recurrence.allCases) { r in
                            Button(r.label) { draft.recurrence = r }
                        }
                    } label: {
                        chip(draft.recurrence.label, icon: "repeat")
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    // Presets pick the shape; the stepper refines N / the day.
                    if case .everyNDays(let n) = draft.recurrence {
                        DSStepper(value: Binding(
                            get: { n },
                            set: { draft.recurrence = .everyNDays($0) }),
                                  range: 2...30)
                            .scaleEffect(0.8)
                            .help("Repeat interval in days")
                    } else if case .monthly(let day) = draft.recurrence {
                        DSStepper(value: Binding(
                            get: { day },
                            set: { draft.recurrence = .monthly($0) }),
                                  range: 1...31)
                            .scaleEffect(0.8)
                            .help("Day of the month")
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Project

    private var projectField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Project").dsSectionLabel()
            TextField("optional project", text: Binding(
                get: { draft.project ?? "" },
                set: { draft.project = $0.isEmpty ? nil : $0 }))
                .textFieldStyle(.plain)
                .font(.system(.callout, design: .rounded))
                .padding(.vertical, 7).padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .fill(Color.white.opacity(0.05)))
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes").dsSectionLabel()
            TextEditor(text: $draft.notes)
                .font(.system(.callout, design: .rounded))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 110, maxHeight: 240)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .fill(Color.white.opacity(0.05)))
        }
    }

    // MARK: - Subtasks

    private var subtasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Subtasks").dsSectionLabel()
                Spacer()
                if settings.showPomodoroBadges, let est = draft.effectiveEstimate {
                    Text("🍅 \(draft.pomodorosDone)/\(est)")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(draft.pomodorosDone >= est ? Color.green : Color.dsSecondary)
                }
            }
            ForEach($draft.subtasks) { $sub in
                HStack(spacing: 8) {
                    Button { sub.isDone.toggle() } label: {
                        Image(systemName: sub.isDone ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(sub.isDone ? .green : Color.dsSecondary)
                    }
                    .buttonStyle(.plain)
                    Text(sub.title)
                        .font(.system(.callout, design: .rounded))
                        .strikethrough(sub.isDone, color: .dsTertiary)
                        .foregroundStyle(sub.isDone ? Color.dsTertiary : Color.dsPrimary)
                    Spacer()
                    if settings.showPomodoroBadges, sub.pomodorosDone > 0 {
                        Text("🍅\(sub.pomodorosDone)")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(Color.dsSecondary)
                    }
                    // Estimate stepper stays visible even with badges hidden —
                    // the editor is the only place estimates can be set.
                    // Per-step pomodoro size: overrides the task's kind when
                    // this step is the focus target.
                    Menu {
                        Button("Task default") { sub.pomodoroKind = nil }
                        Divider()
                        ForEach(PomodoroKind.allCases) { kind in
                            Button {
                                sub.pomodoroKind = kind
                            } label: {
                                let cfg = settings.config(for: kind)
                                Label("\(kind.label) · \(cfg.focusMinutes)/\(cfg.breakMinutes) min",
                                      systemImage: sub.pomodoroKind == kind
                                          ? "checkmark" : kind.systemImage)
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: sub.pomodoroKind?.systemImage ?? "timer")
                                .font(.system(size: 9, weight: .semibold))
                            Text(sub.pomodoroKind?.label ?? "Auto")
                                .font(.system(size: 10, design: .rounded).weight(.medium))
                        }
                        .foregroundStyle(sub.pomodoroKind == nil ? Color.dsTertiary : accent)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Pomodoro size for this step")
                    Text(sub.estimatedPomodoros.map { "est \($0)" } ?? "no est")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(Color.dsTertiary)
                    DSStepper(value: Binding(
                        get: { sub.estimatedPomodoros ?? 0 },
                        set: { sub.estimatedPomodoros = $0 == 0 ? nil : $0 }),
                              range: 0...8)
                        .scaleEffect(0.8)
                    Button { draft.subtasks.removeAll { $0.id == sub.id } } label: {
                        Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(Color.dsTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .contentShape(Rectangle())
                // Same drag idiom as the task rows (this stack isn't a List,
                // so `.onMove` has nothing to hook into).
                .draggable(sub.id.uuidString)
                .dropDestination(for: String.self) { dropped, _ in
                    guard let s = dropped.first, let id = UUID(uuidString: s) else { return false }
                    return moveSubtask(id, before: sub.id)
                }
                .contextMenu {
                    Button {
                        if store.promoteSubtask(draft.id, sub.id) != nil {
                            draft.subtasks.removeAll { $0.id == sub.id }
                        }
                    } label: {
                        Label("Make a task", systemImage: "arrow.up.right.square")
                    }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 11)).foregroundStyle(Color.dsTertiary)
                TextField("add a step", text: $subtaskDraft)
                    .textFieldStyle(.plain)
                    .font(.system(.callout, design: .rounded))
                    .onSubmit { commitSubtask() }
            }
            .padding(.vertical, 7).padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(Color.white.opacity(0.05)))
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            store.delete(draft.id)
            dismiss()
        } label: {
            Label("Delete task", systemImage: "trash")
                .font(.system(.callout, design: .rounded).weight(.medium))
                .foregroundStyle(.red.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(Color.red.opacity(0.12)))
        }
        .buttonStyle(.pressableSubtle)
        .padding(.top, 4)
    }

    // MARK: - Helpers

    /// Chip label for the task-level pomodoro kind ("Big · 90/15" or "Default").
    private func kindChipText(_ kind: PomodoroKind?) -> String {
        guard let kind else { return "Default" }
        let cfg = settings.config(for: kind)
        return "\(kind.label) · \(cfg.focusMinutes)/\(cfg.breakMinutes)"
    }

    private func chip(_ text: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            Text(text).font(.system(.caption, design: .rounded).weight(.medium))
            Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
        }
        .foregroundStyle(Color.dsSecondary)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private var editorBackground: some View {
        ZStack {
            Color.black.opacity(0.3)
            LinearGradient(colors: [accent.opacity(0.18), .clear],
                           startPoint: .top, endPoint: .bottom)
        }
        .background(.ultraThinMaterial)
        .ignoresSafeArea()
    }

    private var dueLabel: String {
        guard let d = draft.dueDate else { return "Due" }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInTomorrow(d) { return "Tomorrow" }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "MMM d"
        return f.string(from: d)
    }

    private func setDue(_ date: Date) { draft.dueDate = date }
    private func dueAt(_ days: Int) -> Date {
        let cal = Calendar.current
        let base = cal.date(byAdding: .day, value: days, to: Date()) ?? Date()
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: base) ?? base
    }
    private func upcomingWeekend() -> Date {
        let cal = Calendar.current
        var d = Date()
        for _ in 0..<7 {
            if cal.component(.weekday, from: d) == 7 { break }   // Saturday
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: d) ?? d
    }
    private func nextMonday() -> Date {
        let cal = Calendar.current
        var d = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        for _ in 0..<7 { if cal.component(.weekday, from: d) == 2 { break }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: d) ?? d
    }

    private func commitTag() {
        for part in tagDraft.split(whereSeparator: { $0 == "," || $0 == " " }) {
            let t = part.trimmingCharacters(in: .whitespaces).lowercased()
            if !t.isEmpty, !draft.tags.contains(t) { draft.tags.append(t) }
        }
        tagDraft = ""
    }
    /// Applies a subtask drag: reorders the draft (what the sheet shows) and
    /// mirrors it into the store so the new order sticks even without Save.
    private func moveSubtask(_ id: UUID, before targetID: UUID) -> Bool {
        guard id != targetID,
              let from = draft.subtasks.firstIndex(where: { $0.id == id }),
              let to = draft.subtasks.firstIndex(where: { $0.id == targetID }) else { return false }
        let source = IndexSet(integer: from)
        let destination = to > from ? to + 1 : to
        draft.subtasks.move(fromOffsets: source, toOffset: destination)
        store.reorderSubtasks(draft.id, from: source, to: destination)
        return true
    }

    private func commitSubtask() {
        let t = subtaskDraft.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let est = settings.defaultSubtaskEstimate
        draft.subtasks.append(Subtask(title: t, estimatedPomodoros: est > 0 ? est : nil))
        subtaskDraft = ""
    }

    private func save() {
        commitTag()
        var clean = draft
        clean.title = clean.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.title.isEmpty else { return }
        store.update(clean)
        dismiss()
    }
}

/// Wrapping flow layout (chips reflow onto new lines as width runs out).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxWidth, x > 0 { y += rowHeight + spacing; x = 0; rowHeight = 0 }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { y += rowHeight + spacing; x = bounds.minX; rowHeight = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

/// A wrapping row of the shared `TaskTag` pills — removable (current tags) or
/// tappable (muted suggestions). Same pill as the composer and row, so tags
/// read identically everywhere.
private struct FlowTags: View {
    let tags: [String]
    var muted = false
    var onRemove: ((String) -> Void)? = nil
    var onTap: ((String) -> Void)? = nil

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                if let onTap {
                    Button { onTap(tag) } label: { TaskTag(tag: tag) }
                        .buttonStyle(.pressableSubtle)
                } else {
                    TaskTag(tag: tag, onRemove: onRemove.map { remove in { remove(tag) } })
                }
            }
        }
    }
}
