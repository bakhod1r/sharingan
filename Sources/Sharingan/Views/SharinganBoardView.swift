import SwiftUI
import SharinganCore

/// Sharingan's own kanban board: three frosted-glass columns — **To Do**,
/// **In Progress**, **Done** — over the local task list, shaped after
/// `WeeklyBoardView`/`JiraBoardView` (same column width, `.draggable`/
/// `.dropDestination` idiom, drop-target glow and hover lift).
///
/// The columns are derived from existing task state — there is no separate
/// "status" field — which keeps every drag deterministic and reversible:
///   • To Do        = an open task that isn't the current focus task
///   • In Progress  = the one active/focus task (`TaskStore.activeTaskID`)
///   • Done         = `isDone`
/// Dragging a card just calls the matching store mutator; setting a new focus
/// task displaces the previous one back to To Do on its own.
struct SharinganBoardView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var store = TaskStore.shared

    /// Card currently under the pointer — lifts slightly.
    @State private var hoveredCard: UUID?
    /// Column currently being dragged over — highlighted.
    @State private var targetedColumn: Column?
    /// Task open in the full editor sheet (click a card).
    @State private var editorTask: TaskItem?
    /// Draft for the quick-add field in the To Do column.
    @State private var todoDraft = ""

    /// Same ordering the Tasks list uses — one shared preference.
    @AppStorage("tasks.sortMode") private var sortModeRaw = TaskSortMode.manual.rawValue
    private var sortMode: TaskSortMode { TaskSortMode(rawValue: sortModeRaw) ?? .manual }

    private let columnWidth: CGFloat = 240
    private var accent: Color { timer.settings.theme.accent }

    private enum Column: String, CaseIterable, Identifiable {
        case todo, inProgress, done
        var id: String { rawValue }
        var title: String {
            switch self {
            case .todo:       return "To Do"
            case .inProgress: return "In Progress"
            case .done:       return "Done"
            }
        }
        var icon: String {
            switch self {
            case .todo:       return "circle"
            case .inProgress: return "circle.lefthalf.filled"
            case .done:       return "checkmark.circle.fill"
            }
        }
    }

    // MARK: - Column contents

    /// Cards for a column, in the shared sort order.
    private func items(_ column: Column) -> [TaskItem] {
        let all = store.tasks
        let filtered: [TaskItem]
        switch column {
        case .todo:
            filtered = all.filter { !$0.isDone && $0.id != store.activeTaskID }
        case .inProgress:
            filtered = all.filter { !$0.isDone && $0.id == store.activeTaskID }
        case .done:
            filtered = all.filter { $0.isDone }
        }
        return filtered.sorted(by: sortMode.inOrder)
    }

    /// The store change a drop onto `column` performs, kept reversible.
    private func drop(_ id: UUID, into column: Column) {
        guard let task = store.tasks.first(where: { $0.id == id }) else { return }
        switch column {
        case .todo:
            if task.isDone { store.toggleDone(id) }
            if store.activeTaskID == id { store.setActive(nil) }
        case .inProgress:
            if task.isDone { store.toggleDone(id) }
            store.setActive(id)
        case .done:
            if store.activeTaskID == id { store.setActive(nil) }
            if !task.isDone { store.toggleDone(id) }
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Column.allCases) { column in
                        columnView(column)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
        }
        .sheet(item: $editorTask) { task in
            TaskEditorView(task: task, accent: accent, settings: timer.settings)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Board")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                let open = store.tasks.filter { !$0.isDone }.count
                Text(open == 0 ? "All clear" : "\(open) open task\(open == 1 ? "" : "s")")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .contentTransition(.opacity)
            }
            Spacer()
            Menu {
                TaskSortMenuItems(sortModeRaw: $sortModeRaw)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(sortMode == .manual ? .white : accent)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help(sortMode == .manual ? "Sort tasks" : "Sorted by \(sortMode.label)")
            .accessibilityLabel("Sort tasks")
        }
    }

    // MARK: - Columns

    private func columnView(_ column: Column) -> some View {
        let cards = items(column)
        let targeted = targetedColumn == column
        return VStack(alignment: .leading, spacing: 12) {
            columnHeader(column, count: cards.count)
            if column == .todo { quickAdd }
            if cards.isEmpty {
                emptyDrop(targeted: targeted)
            } else {
                VStack(spacing: 9) {
                    ForEach(cards) { card($0, column: column) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: columnWidth, alignment: .top)
        .frame(minHeight: 440, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .fill(Color.white.opacity(targeted ? 0.07 : 0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .stroke(targeted ? accent.opacity(0.8) : Color.white.opacity(0.08),
                        lineWidth: targeted ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
        .scaleEffect(targeted ? 1.015 : 1)
        .animation(DS.Motion.standard, value: targeted)
        .dropDestination(for: String.self) { dropped, _ in
            guard let s = dropped.first, let id = UUID(uuidString: s) else { return false }
            withAnimation(DS.Motion.standard) { drop(id, into: column) }
            return true
        } isTargeted: { inside in
            targetedColumn = inside ? column : (targetedColumn == column ? nil : targetedColumn)
        }
    }

    private func columnHeader(_ column: Column, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: column.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(column == .done ? Color.green
                                 : column == .inProgress ? accent : Color.dsSecondary)
            Text(column.title)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
            Spacer()
            Text("\(count)")
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(count == 0 ? .white.opacity(0.3) : .white.opacity(0.55))
                .frame(minWidth: 20, minHeight: 20)
                .background(Circle().fill(Color.white.opacity(count == 0 ? 0.03 : 0.08)))
        }
    }

    private var quickAdd: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(accent)
            TextField("Add task", text: $todoDraft)
                .textFieldStyle(.plain)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.white)
                .onSubmit(addTodo)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
            .fill(Color.dsFill))
    }

    private func addTodo() {
        let t = todoDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var documentResult: TaskStore.DocumentImport?
        withAnimation(DS.Motion.standard) {
            documentResult = store.importIfDocument(t)
            if documentResult == nil { store.add(title: t) }
        }
        todoDraft = ""
        if let documentResult { ImportDuplicatePrompt.resolve(documentResult, store: store) }
    }

    private func emptyDrop(targeted: Bool) -> some View {
        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .foregroundStyle(targeted ? accent.opacity(0.8) : Color.white.opacity(0.12))
            .frame(height: 60)
            .overlay(
                Text(targeted ? "Drop here" : "—")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(targeted ? 0.7 : 0.25))
            )
    }

    // MARK: - Card

    private func card(_ task: TaskItem, column: Column) -> some View {
        let color = Color(hex: store.color(for: task.category))
        let hovered = hoveredCard == task.id
        return HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(color).frame(width: 3)
            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .foregroundStyle(task.isDone ? .white.opacity(0.55) : .white)
                    .strikethrough(task.isDone, color: .white.opacity(0.4))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                cardMeta(task)
            }
            .padding(.leading, 10).padding(.trailing, 9).padding(.vertical, 9)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(Color.white.opacity(hovered ? 0.13 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .scaleEffect(hovered ? 1.02 : 1)
        .shadow(color: .black.opacity(hovered ? 0.25 : 0), radius: 8, y: 3)
        .animation(DS.Motion.hover, value: hovered)
        .contentShape(Rectangle())
        .onHover { hoveredCard = $0 ? task.id : (hoveredCard == task.id ? nil : hoveredCard) }
        .onTapGesture { editorTask = task }
        .draggable(task.id.uuidString) {
            Text(task.title)
                .font(.system(.callout, design: .rounded).weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(color.opacity(0.9)))
        }
    }

    @ViewBuilder
    private func cardMeta(_ task: TaskItem) -> some View {
        let showBadge = timer.settings.showPomodoroBadges
            && (task.pomodorosDone > 0 || task.effectiveEstimate != nil)
        let hasMeta = task.dueDate != nil || task.subtaskProgress.total > 0
            || showBadge || !task.tags.isEmpty || task.priority != .none
        if hasMeta {
            HStack(spacing: 7) {
                if task.priority != .none, let hex = timer.settings.priorityColorHex(task.priority) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(hex: hex))
                }
                if let due = task.dueDate {
                    Label(shortDue(due), systemImage: "calendar")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(task.isOverdue() ? Color.red : .white.opacity(0.55))
                }
                if let tag = task.tags.first {
                    Text("#\(tag)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(hex: store.color(for: task.category)))
                }
                if task.subtaskProgress.total > 0 {
                    Label("\(task.subtaskProgress.done)/\(task.subtaskProgress.total)", systemImage: "checklist")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(task.subtaskProgress.done == task.subtaskProgress.total
                                         ? Color.green : .white.opacity(0.55))
                }
                Spacer(minLength: 0)
                if showBadge {
                    Text(task.effectiveEstimate.map { "🍅\(task.pomodorosDone)/\($0)" }
                         ?? "🍅\(task.pomodorosDone)")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    private func shortDue(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}
