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
                    ForEach(TaskCategory.presets) { c in
                        Button(c.name) { newCategory = c.name }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: TaskCategory.color(for: newCategory)))
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
                Circle().fill(Color(hex: TaskCategory.color(for: category)))
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
                            .background(Color.white.opacity(0.1), in: Capsule())
                            .foregroundStyle(.secondary)
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

fileprivate extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255,
                  opacity: 1)
    }
}
