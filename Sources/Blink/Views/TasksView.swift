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
    @State private var newTags = ""
    @State private var hasDue = false
    @State private var newDue = Date().addingTimeInterval(3600)
    @State private var newEstimate = 0
    @State private var newRecurrence: Recurrence = .none
    @State private var newProject = ""
    @State private var newNotes = ""
    /// Tasks whose subtasks/notes panel is expanded.
    @State private var expanded: Set<UUID> = []
    @State private var subtaskDrafts: [UUID: String] = [:]
    /// Inline title editing (double-click a row or the context-menu "Edit").
    @State private var editingTaskID: UUID?
    @State private var editingText = ""
    @FocusState private var editFocused: Bool

    // Inline "add category" form state.
    @State private var showNewCategory = false
    @State private var newCatName = ""
    @State private var newCatColor = TaskCategory.palette[0]

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
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("New task…", text: $newTitle, onCommit: add)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .rounded))
                Button(action: add) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack(spacing: 8) {
                Menu {
                    ForEach(store.allCategories) { c in
                        Button(c.name) { newCategory = c.name }
                    }
                    Divider()
                    Button {
                        newCatName = ""
                        showNewCategory = true
                    } label: {
                        Label("Add category…", systemImage: "plus")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(newCategoryAccent)
                            .frame(width: 9, height: 9)
                        Text(newCategory)
                            .font(.system(.caption, design: .rounded).weight(.medium))
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                TextField("tags, comma, separated", text: $newTags)
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if showNewCategory { newCategoryForm }

            // Estimate · repeat · project
            HStack(spacing: 10) {
                Stepper(value: $newEstimate, in: 0...12) {
                    Text(newEstimate == 0 ? "Est: —" : "Est: \(newEstimate) 🍅")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .fixedSize()

                Menu {
                    ForEach(Recurrence.allCases) { r in
                        Button(r.label) { newRecurrence = r }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "repeat").font(.system(size: 10, weight: .semibold))
                        Text(newRecurrence == .none ? "No repeat" : newRecurrence.label)
                            .font(.system(.caption, design: .rounded))
                    }
                    .foregroundStyle(newRecurrence == .none ? .secondary : .primary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                TextField("project", text: $newProject)
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 120)
            }

            TextField("notes (optional)", text: $newNotes, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1...3)

            HStack(spacing: 8) {
                Toggle(isOn: $hasDue) {
                    Text("Due")
                        .font(.system(.caption, design: .rounded).weight(.medium))
                }
                .toggleStyle(.checkbox)
                if hasDue {
                    DatePicker("", selection: $newDue)
                        .datePickerStyle(.field)
                        .labelsHidden()
                        .font(.caption)
                }
                Spacer()
                if !store.tasks.isEmpty {
                    Button {
                        exportCSV()
                    } label: {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                            .font(.system(.caption, design: .rounded))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .glassRounded(16, material: .thin)
    }

    /// Inline form to create a custom, color-coded category.
    private var newCategoryForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: newCatColor)).frame(width: 10, height: 10)
                TextField("New category name", text: $newCatName, onCommit: addCategory)
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .rounded).weight(.medium))
                Button("Add", action: addCategory)
                    .buttonStyle(.borderless)
                    .disabled(newCatName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button {
                    showNewCategory = false
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 6) {
                ForEach(TaskCategory.palette, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle().stroke(Color.white,
                                            lineWidth: newCatColor == hex ? 2 : 0)
                        )
                        .onTapGesture { newCatColor = hex }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }

    private func addCategory() {
        guard let name = store.addCategory(name: newCatName, colorHex: newCatColor) else { return }
        newCategory = name
        newCatName = ""
        showNewCategory = false
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
                Circle().fill(Color(hex: store.color(for: category)))
                    .frame(width: 8, height: 8)
                Text(category.uppercased())
                    .font(.system(.caption2, design: .rounded).weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(items.filter { !$0.isDone }.count)")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
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
                    .buttonStyle(.plain)
                    Text(sub.title)
                        .font(.system(.caption, design: .rounded))
                        .strikethrough(sub.isDone, color: .secondary)
                        .foregroundStyle(sub.isDone ? .secondary : .primary)
                    Spacer()
                    Button { store.deleteSubtask(task.id, sub.id) } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
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

    private func row(_ task: TaskItem) -> some View {
        let isActive = store.activeTaskID == task.id
        let accent = Color(hex: store.color(for: task.category))
        return HStack(spacing: 10) {
            Button {
                store.toggleDone(task.id)
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(task.isDone ? Color.green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                if editingTaskID == task.id {
                    TextField("Task name", text: $editingText)
                        .textFieldStyle(.plain)
                        .font(.system(.callout, design: .rounded).weight(.medium))
                        .focused($editFocused)
                        .onSubmit { commitEdit(task) }
                        .onExitCommand { editingTaskID = nil }
                        .onAppear { editFocused = true }
                } else {
                    Text(task.title)
                        .font(.system(.callout, design: .rounded).weight(.medium))
                        .strikethrough(task.isDone, color: .secondary)
                        .foregroundStyle(task.isDone ? .secondary : .primary)
                        .lineLimit(1)
                        // Double-click to rename, like Finder / Todoist.
                        .onTapGesture(count: 2) { beginEdit(task) }
                }
                let hasMeta = !task.tags.isEmpty || task.dueDate != nil
                    || task.recurrence != .none || task.project != nil
                    || task.subtaskProgress.total > 0
                if hasMeta {
                    HStack(spacing: 6) {
                        ForEach(task.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(accent.opacity(0.22), in: Capsule())
                                .foregroundStyle(accent)
                        }
                        if let project = task.project {
                            Label(project, systemImage: "folder.fill")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        if task.recurrence != .none {
                            Image(systemName: "repeat")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .help(task.recurrence.label)
                        }
                        if task.subtaskProgress.total > 0 {
                            Text("☑\(task.subtaskProgress.done)/\(task.subtaskProgress.total)")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(task.subtaskProgress.done == task.subtaskProgress.total
                                                 ? Color.green : .secondary)
                        }
                        if let due = task.dueDate {
                            Label(dueText(due), systemImage: "calendar")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(task.isOverdue() ? Color.red : .secondary)
                        }
                    }
                }
            }
            Spacer()

            if task.isPlannedToday() {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .help("On today's plan")
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expanded.contains(task.id) { expanded.remove(task.id) }
                    else { expanded.insert(task.id) }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded.contains(task.id) ? 180 : 0))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Subtasks & notes")

            if let est = task.estimatedPomodoros {
                Text("🍅\(task.pomodorosDone)/\(est)")
                    .font(.system(.caption2, design: .rounded).weight(.medium))
                    .foregroundStyle(task.pomodorosDone >= est ? Color.green : .secondary)
            } else if task.pomodorosDone > 0 {
                Text("🍅\(task.pomodorosDone)")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }

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
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.04))
        )
        .contextMenu {
            Button { beginEdit(task) } label: {
                Label("Edit", systemImage: "pencil")
            }
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
        defer { editingTaskID = nil }
        let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != task.title else { return }
        var updated = task
        updated.title = trimmed
        store.update(updated)
    }

    private func add() {
        let tags = newTags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        store.add(title: newTitle, category: newCategory, tags: tags,
                  dueDate: hasDue ? newDue : nil,
                  estimatedPomodoros: newEstimate > 0 ? newEstimate : nil,
                  recurrence: newRecurrence,
                  project: newProject.isEmpty ? nil : newProject,
                  notes: newNotes)
        newTitle = ""
        newTags = ""
        hasDue = false
        newEstimate = 0
        newRecurrence = .none
        newProject = ""
        newNotes = ""
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
