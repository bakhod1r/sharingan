import SwiftUI
import SharinganCore

/// Presented before a focus pomodoro starts: the user picks (or quickly adds)
/// the task to run the session against. Choosing a task makes it active and
/// immediately starts the focus timer.
///
/// With `onPick` set the sheet runs in "pick" mode instead (the post-break
/// "What's next?" prompt): choosing a task — or skipping — reports the id to
/// the host (which answers `SharinganCoordinator.resolveTaskPick(with:)`) rather
/// than starting a session itself.
struct TaskPickerSheet: View {
    @ObservedObject var timer: PomodoroTimer
    /// Pick-mode callback; nil id means "no task, thanks". nil closure =
    /// classic pick-and-start behavior.
    var onPick: ((UUID?) -> Void)? = nil
    @ObservedObject private var store = TaskStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var newTitle = ""
    /// Tasks whose subtask list is expanded so a specific step can be targeted.
    @State private var expanded: Set<UUID> = []
    /// Same ordering the Tasks list uses — one shared preference.
    @AppStorage("tasks.sortMode") private var sortModeRaw = TaskSortMode.manual.rawValue
    private var sortMode: TaskSortMode { TaskSortMode(rawValue: sortModeRaw) ?? .manual }
    /// Step ordering, shared with the expanded subtask panels.
    @AppStorage("tasks.subtaskSortMode") private var subSortRaw = SubtaskSortMode.manual.rawValue
    private var subSort: SubtaskSortMode { SubtaskSortMode(rawValue: subSortRaw) ?? .manual }
    /// One-dimension narrowing (category / tag / priority) — transient, the
    /// sheet is short-lived.
    @State private var categoryFilter: String?
    @State private var tagFilter: String?
    @State private var priorityFilter: TaskPriority?
    private var isNarrowed: Bool {
        categoryFilter != nil || tagFilter != nil || priorityFilter != nil
    }

    private var allOpenTasks: [TaskItem] {
        store.tasks.filter { !$0.isDone && $0.trashedAt == nil }
    }

    /// The list as shown: open tasks, narrowed by the filter menu, in the
    /// shared sort order (manual = the Tasks list's drag order).
    private var openTasks: [TaskItem] {
        narrowTasks(allOpenTasks, category: categoryFilter, tag: tagFilter,
                    priority: priorityFilter)
            .sorted(by: sortMode.inOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.25)

            if allOpenTasks.isEmpty {
                emptyState
            } else {
                sortFilterBar
                if openTasks.isEmpty {
                    // The filter emptied the list — say so instead of the
                    // "add one below" empty state, and keep the bar visible
                    // so the filter can be cleared.
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("No tasks match the filter")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
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
            }

            Divider().opacity(0.25)
            footer
        }
        .frame(width: 400, height: 480)
        .background(backdrop)
        .onExitCommand { onPick?(nil) }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            Text(onPick == nil ? "Choose a task" : "What's next?")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
            Text(onPick == nil ? "Pick what to focus on, then the pomodoro starts."
                               : "Pick the task for your next focus session.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20).padding(.bottom, 16)
    }

    // MARK: - Sort & filter

    /// Slim controls row under the header: sort (shared with the Tasks list)
    /// and a one-dimension filter, both as quiet capsule chips.
    private var sortFilterBar: some View {
        HStack(spacing: 6) {
            Menu {
                TaskSortMenuItems(sortModeRaw: $sortModeRaw)
            } label: {
                pickerChip(icon: "arrow.up.arrow.down",
                           text: sortMode == .manual ? "Sort" : sortMode.label,
                           active: sortMode != .manual)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Sort tasks")

            Menu {
                TaskFilterMenuItems(store: store, settings: timer.settings,
                                    categoryFilter: $categoryFilter,
                                    tagFilter: $tagFilter,
                                    priorityFilter: $priorityFilter)
            } label: {
                pickerChip(icon: isNarrowed
                                ? "line.3.horizontal.decrease.circle.fill"
                                : "line.3.horizontal.decrease.circle",
                           text: filterChipLabel, active: isNarrowed)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Filter by category, tag, or priority")

            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 10)
    }

    private var filterChipLabel: String {
        if let c = categoryFilter { return c }
        if let t = tagFilter { return "#\(t)" }
        if let p = priorityFilter { return timer.settings.priorityName(p) }
        return "Filter"
    }

    private func pickerChip(icon: String, text: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
            Text(text).font(.system(.caption2, design: .rounded).weight(.medium))
        }
        .foregroundStyle(active ? Color.accentColor : .white.opacity(0.65))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(active ? Color.accentColor.opacity(0.18)
                                          : Color.white.opacity(0.08)))
    }

    // MARK: - Task row

    private func row(_ task: TaskItem) -> some View {
        // The kind chip is a `Menu`, which doesn't play well nested inside a
        // `Button`'s label (its taps don't route through reliably). So the
        // pick action lives on its own leading/trailing `Button`s and the
        // chip sits as a plain sibling between them — a tap on the chip hits
        // the Menu directly and never reaches either Button's action.
        HStack(spacing: 10) {
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
                    Spacer(minLength: 4)
                    if timer.settings.showPomodoroBadges, task.pomodorosDone > 0 {
                        Text("🍅\(task.pomodorosDone)")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressableSubtle)

            kindChip(for: task)

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
            Button {
                choose(task)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressableSubtle)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glassRounded(12, material: .regular)
    }

    /// Compact pomodoro-size chip, styled like `TaskEditorView`'s: a `Menu`
    /// showing the task's current kind (or "Auto" for the default), with a
    /// "Default" entry plus one per `PomodoroKind`. Selecting an entry
    /// persists immediately via `TaskStore.update` — same save path the
    /// editor uses — so the choice sticks for future sessions.
    private func kindChip(for task: TaskItem) -> some View {
        Menu {
            Button("Default") { setKind(nil, for: task) }
            Divider()
            ForEach(PomodoroKind.allCases) { kind in
                Button {
                    setKind(kind, for: task)
                } label: {
                    Label(kind.label,
                          systemImage: task.pomodoroKind == kind ? "checkmark" : kind.systemImage)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: task.pomodoroKind?.systemImage ?? "timer")
                    .font(.system(size: 9, weight: .semibold))
                Text(task.pomodoroKind?.label ?? "Auto")
                    .font(.system(.caption2, design: .rounded).weight(.medium))
            }
            .foregroundStyle(.white.opacity(0.65))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .fixedSize()
        .help("Pomodoro size for this task")
    }

    private func setKind(_ kind: PomodoroKind?, for task: TaskItem) {
        var updated = task
        updated.pomodoroKind = kind
        store.update(updated)
    }

    /// Open steps of an expanded task; choosing one starts the session with
    /// that step as the pomodoro-credit target.
    private func subtaskRows(_ task: TaskItem) -> some View {
        VStack(spacing: 4) {
            ForEach(subSort.apply(task.subtasks.filter { !$0.isDone })) { sub in
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
                TextField("New task…", text: $newTitle)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.white)
                    .onSubmit(addAndStart)
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
                Text(onPick == nil ? "Start without a task" : "Skip — no task for now")
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
        // An explicit subtask pick is honored as-is; picking the task itself
        // focuses its first unfinished subtask (if any).
        if let subtask {
            store.setActiveSubtask(taskID: task.id, subtaskID: subtask)
        } else {
            store.selectFocusTarget(task.id)
        }
        finish(with: task.id)
    }

    private func addAndStart() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        // A pasted document imports in bulk and focus starts on its first task.
        let countBefore = store.tasks.count
        if let result = store.importIfDocument(title) {
            ImportDuplicatePrompt.resolve(result, store: store)
            let added = store.tasks.count - countBefore
            let first = store.tasks.sorted { $0.sortOrder < $1.sortOrder }
                .suffix(added).first
            if let first { store.setActive(first.id) }
            newTitle = ""
            finish(with: first?.id)
            return
        }
        store.add(title: title)
        let added = store.tasks.last(where: { $0.title == title })
        if let added { store.setActive(added.id) }
        newTitle = ""
        finish(with: added?.id)
    }

    private func startWithoutTask() {
        if onPick == nil { store.setActive(nil) }
        finish(with: nil)
    }

    /// Pick mode reports the choice to the host; classic mode starts the
    /// focus session and closes the sheet.
    private func finish(with id: UUID?) {
        if let onPick {
            onPick(id)
        } else {
            timer.startFocusSession(kind: store.resolvedActiveKind)
            dismiss()
        }
    }
}
