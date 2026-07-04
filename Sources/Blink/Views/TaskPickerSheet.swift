import SwiftUI
import BlinkCore

/// Presented before a focus pomodoro starts: the user picks (or quickly adds)
/// the task to run the session against. Choosing a task makes it active and
/// immediately starts the focus timer.
struct TaskPickerSheet: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var store = TaskStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var newTitle = ""

    private var openTasks: [TaskItem] {
        store.tasks.filter { !$0.isDone }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.25)

            if openTasks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(openTasks) { task in
                            row(task)
                        }
                    }
                    .padding(16)
                }
            }

            Divider().opacity(0.25)
            footer
        }
        .frame(width: 400, height: 480)
        .background(backdrop)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            Text("Choose a task")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
            Text("Pick what to focus on, then the pomodoro starts.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20).padding(.bottom, 16)
    }

    // MARK: - Task row

    private func row(_ task: TaskItem) -> some View {
        Button {
            choose(task)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(hex: TaskCategory.color(for: task.category)))
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(task.category)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                if task.pomodorosDone > 0 {
                    Text("🍅\(task.pomodorosDone)")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .glassRounded(12, material: .regular)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "checklist")
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.7))
            Text("No open tasks")
                .font(.system(.callout, design: .rounded).weight(.medium))
                .foregroundStyle(.white)
            Text("Add one below to start a focus session.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer (quick add + escape)

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField("New task…", text: $newTitle, onCommit: addAndStart)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.white)
                Button(action: addAndStart) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .glassRounded(12, material: .regular)

            Button {
                startWithoutTask()
            } label: {
                Text("Start without a task")
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    private var backdrop: some View {
        LinearGradient(colors: timer.phase.gradient.map { $0.opacity(0.85) } + [Color(white: 0.06)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(Color.black.opacity(0.25))
            .ignoresSafeArea()
    }

    // MARK: - Actions

    private func choose(_ task: TaskItem) {
        store.setActive(task.id)
        startFocus()
    }

    private func addAndStart() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        store.add(title: title)
        if let added = store.tasks.last(where: { $0.title == title }) {
            store.setActive(added.id)
        }
        newTitle = ""
        startFocus()
    }

    private func startWithoutTask() {
        store.setActive(nil)
        startFocus()
    }

    private func startFocus() {
        if timer.phase != .focus { timer.stop() }
        timer.start()
        dismiss()
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
