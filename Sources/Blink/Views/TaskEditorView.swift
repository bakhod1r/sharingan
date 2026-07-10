import SwiftUI
import BlinkCore

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

    init(task: TaskItem, accent: Color = .paletteFocusStart) {
        _draft = State(initialValue: task)
        self.accent = accent
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
            PriorityMenu(priority: $draft.priority)
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
                DatePicker("", selection: Binding(
                    get: { draft.dueDate ?? Date() },
                    set: { draft.dueDate = $0 }),
                    displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical).labelsHidden().frame(width: 260)
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
                    .onChange(of: tagDraft) { v in
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
                Text("Repeat").dsSectionLabel()
                Menu {
                    ForEach(Recurrence.allCases) { r in
                        Button(r.label) { draft.recurrence = r }
                    }
                } label: {
                    chip(draft.recurrence.label, icon: "repeat")
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
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
            Text("Subtasks").dsSectionLabel()
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
                    Button { draft.subtasks.removeAll { $0.id == sub.id } } label: {
                        Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(Color.dsTertiary)
                    }
                    .buttonStyle(.plain)
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
    private func commitSubtask() {
        let t = subtaskDraft.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        draft.subtasks.append(Subtask(title: t))
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
