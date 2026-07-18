import SwiftUI
import SharinganCore

private extension String {
    /// The column id inside a `"column:<id>"` drag payload, or nil for a
    /// plain task-card (UUID) drag.
    var columnDragID: String? {
        hasPrefix("column:") ? String(dropFirst("column:".count)) : nil
    }
}

/// Sharingan's own kanban board: user-defined columns (`BoardColumnStore`)
/// over the local task list. Shaped after `WeeklyBoardView`/`JiraBoardView`
/// — same column width, `.draggable`/`.dropDestination` idiom, drop glow and
/// hover lift.
///
/// A task names its column through `TaskItem.boardColumnID`; a task in a
/// disabled/deleted column falls back to the first column. The one built-in
/// coupling: a column whose role is `.done` drives `isDone`, so dragging a
/// card in or out completes / reopens the task. Columns can be added, renamed,
/// reordered, disabled and deleted from the header and per-column menus.
struct SharinganBoardView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var store = TaskStore.shared
    @ObservedObject private var columns = BoardColumnStore.shared

    @State private var hoveredCard: UUID?
    @State private var targetedColumn: String?
    @State private var editorTask: TaskItem?
    @State private var draft = ""

    /// Column-management text prompts.
    @State private var addingColumn = false
    @State private var newColumnName = ""
    @State private var renamingColumn: BoardColumn?
    @State private var renameText = ""

    @AppStorage("tasks.sortMode") private var sortModeRaw = TaskSortMode.manual.rawValue
    private var sortMode: TaskSortMode { TaskSortMode(rawValue: sortModeRaw) ?? .manual }

    private let columnWidth: CGFloat = 240
    private var accent: Color { timer.settings.theme.accent }

    // MARK: - Column contents

    /// Tasks shown in a column: the Done column holds every completed task;
    /// other columns hold open tasks that resolve to them.
    private func tasks(in column: BoardColumn) -> [TaskItem] {
        let all = store.tasks.filter { $0.trashedAt == nil }
        let picked: [TaskItem]
        if column.role == .done {
            picked = all.filter(\.isDone)
        } else {
            picked = all.filter { !$0.isDone
                && columns.resolvedColumn(for: $0.boardColumnID)?.id == column.id }
        }
        return picked.sorted(by: sortMode.inOrder)
    }

    private func drop(_ id: UUID, into column: BoardColumn) {
        store.setBoardColumn(id, columnID: column.id, markDone: column.role == .done)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(columns.enabled) { columnView($0) }
                    addColumnTile
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
        }
        .onAppear(perform: backfillOnce)
        .sheet(item: $editorTask) { task in
            TaskEditorView(task: task, accent: accent, settings: timer.settings)
        }
        .alert("New column", isPresented: $addingColumn) {
            TextField("Name", text: $newColumnName)
            Button("Add") {
                let name = newColumnName; newColumnName = ""
                if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                    withAnimation(DS.Motion.standard) { columns.addColumn(name: name) }
                }
            }
            Button("Cancel", role: .cancel) { newColumnName = "" }
        }
        .alert("Rename column", isPresented: Binding(
            get: { renamingColumn != nil },
            set: { if !$0 { renamingColumn = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let col = renamingColumn { columns.rename(col.id, to: renameText) }
                renamingColumn = nil
            }
            Button("Cancel", role: .cancel) { renamingColumn = nil }
        }
    }

    /// Seed done tasks into the Done column the first time the board is shown.
    private func backfillOnce() {
        if let done = columns.doneColumnID { store.backfillBoardColumns(doneColumnID: done) }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Board")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                let open = store.tasks.filter { !$0.isDone && $0.trashedAt == nil }.count
                Text(open == 0 ? "All clear" : "\(open) open task\(open == 1 ? "" : "s")")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .contentTransition(.opacity)
            }
            Spacer()
            Menu {
                TaskSortMenuItems(sortModeRaw: $sortModeRaw)
            } label: {
                circleIcon("arrow.up.arrow.down", active: sortMode != .manual)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help(sortMode == .manual ? "Sort tasks" : "Sorted by \(sortMode.label)")
            .accessibilityLabel("Sort tasks")

            Button { newColumnName = ""; addingColumn = true } label: {
                Label("Add column", systemImage: "plus")
                    .font(.system(.callout, design: .rounded).weight(.semibold))
            }
            .buttonStyle(.glass)
            .help("Add a board column")
        }
    }

    private func circleIcon(_ name: String, active: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(active ? accent : .white)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color.white.opacity(0.08)))
            .contentShape(Circle())
    }

    // MARK: - Columns

    private func columnView(_ column: BoardColumn) -> some View {
        let cards = tasks(in: column)
        let targeted = targetedColumn == column.id
        let isFirst = columns.enabled.first?.id == column.id
        return VStack(alignment: .leading, spacing: 12) {
            columnHeader(column, count: cards.count)
            if isFirst { quickAdd }
            if cards.isEmpty {
                emptyDrop(targeted: targeted)
            } else {
                VStack(spacing: 9) {
                    ForEach(cards) { card($0) }
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
            guard let s = dropped.first else { return false }
            // A column drag (reorder) is prefixed; anything else is a task card.
            if let colID = s.columnDragID {
                withAnimation(DS.Motion.standard) { columns.moveColumn(colID, toSlotOf: column.id) }
                return true
            }
            guard let id = UUID(uuidString: s) else { return false }
            withAnimation(DS.Motion.standard) { drop(id, into: column) }
            return true
        } isTargeted: { inside in
            targetedColumn = inside ? column.id : (targetedColumn == column.id ? nil : targetedColumn)
        }
    }

    private func columnHeader(_ column: BoardColumn, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .contentShape(Rectangle())
                .help("Drag to reorder this column")
                .draggable("column:\(column.id)") {
                    Text(column.name)
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(accent.opacity(0.9)))
                }
            if column.role == .done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.green)
            }
            Text(column.name)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text("\(count)")
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(count == 0 ? .white.opacity(0.3) : .white.opacity(0.55))
                .frame(minWidth: 20, minHeight: 20)
                .background(Circle().fill(Color.white.opacity(count == 0 ? 0.03 : 0.08)))
            Spacer()
            columnMenu(column)
        }
    }

    private func columnMenu(_ column: BoardColumn) -> some View {
        Menu {
            Button { renamingColumn = column; renameText = column.name } label: {
                Label("Rename…", systemImage: "pencil")
            }
            Button { withAnimation(DS.Motion.standard) { columns.move(column.id, by: -1) } } label: {
                Label("Move left", systemImage: "arrow.left")
            }
            Button { withAnimation(DS.Motion.standard) { columns.move(column.id, by: 1) } } label: {
                Label("Move right", systemImage: "arrow.right")
            }
            Divider()
            Button { withAnimation(DS.Motion.standard) { columns.setEnabled(column.id, false) } } label: {
                Label("Hide column", systemImage: "eye.slash")
            }
            Button(role: .destructive) {
                withAnimation(DS.Motion.standard) { columns.delete(column.id) }
            } label: {
                Label("Delete column", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Column options")
    }

    private var addColumnTile: some View {
        Button { newColumnName = ""; addingColumn = true } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                Text("Add column")
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
            }
            .foregroundStyle(.white.opacity(0.4))
            .frame(width: 150, height: 120)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(Color.white.opacity(0.14))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableSubtle)
    }

    private var quickAdd: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(accent)
            TextField("Add task", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.white)
                .onSubmit(addTask)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
            .fill(Color.dsFill))
    }

    private func addTask() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var documentResult: TaskStore.DocumentImport?
        withAnimation(DS.Motion.standard) {
            documentResult = store.importIfDocument(t)
            if documentResult == nil { store.add(title: t) }
        }
        draft = ""
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

    private func card(_ task: TaskItem) -> some View {
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
