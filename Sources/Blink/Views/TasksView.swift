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
                row(task)
            }
        }
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
                Text(task.title)
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .strikethrough(task.isDone, color: .secondary)
                    .foregroundStyle(task.isDone ? .secondary : .primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    ForEach(task.tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(accent.opacity(0.22), in: Capsule())
                            .foregroundStyle(accent)
                    }
                    if let due = task.dueDate {
                        Label(dueText(due), systemImage: "calendar")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(task.isOverdue() ? Color.red : .secondary)
                    }
                }
                .opacity(task.tags.isEmpty && task.dueDate == nil ? 0 : 1)
            }
            Spacer()

            if task.pomodorosDone > 0 {
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
            Button(role: .destructive) { store.delete(task.id) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    private func add() {
        let tags = newTags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        store.add(title: newTitle, category: newCategory, tags: tags,
                  dueDate: hasDue ? newDue : nil)
        newTitle = ""
        newTags = ""
        hasDue = false
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
