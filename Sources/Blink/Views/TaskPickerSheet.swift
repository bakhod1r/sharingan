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
    /// Tasks whose subtask list is expanded so a specific step can be targeted.
    @State private var expanded: Set<UUID> = []

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
                            if expanded.contains(task.id) {
                                subtaskRows(task)
                            }
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
                    .fill(Color(hex: store.color(for: task.category)))
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
                if timer.settings.showPomodoroBadges, task.pomodorosDone > 0 {
                    Text("🍅\(task.pomodorosDone)")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
                // Disclosure for tasks with open steps — lets the user aim the
                // session at one step instead of the whole task.
                if task.subtasks.contains(where: { !$0.isDone }) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            if expanded.contains(task.id) { expanded.remove(task.id) }
                            else { expanded.insert(task.id) }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                            .rotationEffect(.degrees(expanded.contains(task.id) ? 180 : 0))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressableSubtle)
                    .help("Pick a step to focus on")
                }
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .glassRounded(12, material: .regular)
        }
        .buttonStyle(.pressableSubtle)
    }

    /// Open steps of an expanded task; choosing one starts the session with
    /// that step as the pomodoro-credit target.
    private func subtaskRows(_ task: TaskItem) -> some View {
        VStack(spacing: 4) {
            ForEach(task.subtasks.filter { !$0.isDone }) { sub in
                Button {
                    choose(task, subtask: sub.id)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "scope")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                        Text(sub.title)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                        Spacer()
                        if timer.settings.showPomodoroBadges,
                           sub.pomodorosDone > 0 || sub.estimatedPomodoros != nil {
                            Text(sub.estimatedPomodoros.map { "🍅\(sub.pomodorosDone)/\($0)" }
                                 ?? "🍅\(sub.pomodorosDone)")
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        Image(systemName: "play.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .glassRounded(10, material: .thin)
                }
                .buttonStyle(.pressableSubtle)
            }
        }
        .padding(.leading, 26)
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
                .buttonStyle(.pressableSubtle)
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
            .buttonStyle(.pressableSubtle)
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

    private func choose(_ task: TaskItem, subtask: UUID? = nil) {
        store.setActiveSubtask(taskID: task.id, subtaskID: subtask)
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
        timer.startFocusSession()
        dismiss()
    }
}
