import SwiftUI
import SharinganCore

/// Full-task editor presented as a sheet. Unlike the old inline title-only edit,
/// this lets you change EVERY field of an existing task — category, priority,
/// due date, tags, estimate, recurrence, project, notes and subtasks — then
/// saves the whole thing atomically through `store.update`.
struct TaskEditorView: View {
    /// `.sheet` is the original centered modal. `.docked` renders as an
    /// inline card meant to sit beside the task list (main window only) —
    /// same fields, different chrome: an "X" close instead of Cancel/Save in
    /// the header, and a pinned Delete/Save footer below the scroll content.
    enum Presentation { case sheet, docked }

    @ObservedObject private var store = TaskStore.shared
    @Environment(\.dismiss) private var dismiss

    /// A local working copy; nothing touches the store until Save.
    @State private var draft: TaskItem
    @State private var tagDraft = ""
    @State private var subtaskDraft = ""
    @State private var showCustomDue = false
    @FocusState private var titleFocused: Bool
    /// Step narrowing for the Subtasks section. The editor deliberately has
    /// no step *sort* — rows stay in manual order because this sheet is where
    /// that order is edited (drag to reorder).
    @State private var subStatus: SubtaskStatusFilter = .all
    @State private var subPriority: SharinganCore.TaskPriority?

    var accent: Color = .paletteFocusStart
    /// Snapshot of app settings for defaults & badge visibility (value copy is
    /// fine for a modal sheet). No default value on purpose: a call site that
    /// forgets it would silently run the editor on factory settings.
    let settings: PomodoroSettings
    var presentation: Presentation = .sheet
    /// Called instead of `dismiss()` when `presentation == .docked`, since a
    /// docked panel isn't a real SwiftUI presentation — the parent owns the
    /// state that shows/hides it.
    var onClose: (() -> Void)? = nil

    init(task: TaskItem, accent: Color = .paletteFocusStart,
         settings: PomodoroSettings, presentation: Presentation = .sheet,
         onClose: (() -> Void)? = nil) {
        _draft = State(initialValue: task)
        self.accent = accent
        self.settings = settings
        self.presentation = presentation
        self.onClose = onClose
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
                    if !history.isEmpty { historySection }
                    if !taskAppTotals.isEmpty { appsUsedSection }
                    if !taskDeviceTotals.isEmpty { devicesUsedSection }
                    if presentation == .sheet { deleteButton }
                }
                .padding(20)
            }
            if presentation == .docked {
                Divider().overlay(Color.white.opacity(0.12))
                dockedFooter
            }
        }
        .modifier(SizingModifier(presentation: presentation))
        .background(presentation == .docked ? AnyView(dockedBackground) : AnyView(editorBackground))
        .tint(accent)
    }

    /// `.sheet` keeps its original comfortable modal sizing; `.docked` just
    /// fills the panel container its parent sized (`TasksView`'s side-panel
    /// `HStack` gives it a fixed width).
    private struct SizingModifier: ViewModifier {
        let presentation: Presentation
        func body(content: Content) -> some View {
            if presentation == .docked {
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content.frame(minWidth: 440, idealWidth: 460, maxWidth: 620,
                               minHeight: 560, idealHeight: 640, maxHeight: 820)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            if presentation == .docked {
                Text("Task:")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Button { close() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressableSubtle)
                .help("Close")
            } else {
            Button("Cancel") { close() }
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
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    // MARK: - Title

    private var titleField: some View {
        TextField("Task name", text: $draft.title, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(.title2, design: .rounded).weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1...3)
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
                SharinganCalendar(date: Binding(
                    get: { draft.dueDate ?? Date() },
                    // Picking a day sets a date-only due — the time is optional.
                    set: { draft.dueDate = DueDate.dateOnly($0) }),
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
            // Selectable, like category — projects are a registry now, not free
            // text. New projects are born in the composer or the sidebar "+".
            Menu {
                Button {
                    draft.project = nil
                } label: {
                    Label("No project", systemImage: draft.project == nil ? "checkmark" : "slash.circle")
                }
                if !store.allProjects.isEmpty { Divider() }
                ForEach(store.allProjects) { p in
                    Button {
                        draft.project = p.name
                    } label: {
                        Label(p.name, systemImage: draft.project == p.name ? "checkmark" : p.icon)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if let project = draft.project {
                        Image(systemName: store.projectIcon(project))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: store.projectColor(project)))
                        Text(project).foregroundStyle(.white)
                    } else {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.dsSecondary)
                        Text("No project").foregroundStyle(Color.dsSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.dsTertiary)
                }
                .font(.system(.callout, design: .rounded))
                .padding(.vertical, 7).padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .fill(Color.white.opacity(0.05)))
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
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
                if draft.subtasks.count > 1 {
                    Menu {
                        SubtaskFilterMenuItems(settings: settings,
                                               status: $subStatus,
                                               priorityFilter: $subPriority)
                    } label: {
                        let active = subStatus != .all || subPriority != nil
                        Image(systemName: active ? "line.3.horizontal.decrease.circle.fill"
                                                 : "line.3.horizontal.decrease.circle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(active ? accent : Color.dsTertiary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Filter steps — status or priority")
                }
            }
            ForEach($draft.subtasks) { $sub in
                if subtaskShown(sub) {
                    subtaskRow($sub)
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

    /// One step, stacked like a task row: title across the full width, its
    /// badges on a second line underneath. Putting the badges beside the title
    /// (as this once did) starved it of width in the docked panel and wrapped
    /// long step names into a one-word-per-line column.
    private func subtaskRow(_ sub: Binding<Subtask>) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button { sub.wrappedValue.isDone.toggle() } label: {
                Image(systemName: sub.wrappedValue.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(sub.wrappedValue.isDone ? .green : Color.dsSecondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text(sub.wrappedValue.title)
                    .font(.system(.callout, design: .rounded))
                    .strikethrough(sub.wrappedValue.isDone, color: .dsTertiary)
                    .foregroundStyle(sub.wrappedValue.isDone ? Color.dsTertiary : Color.dsPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                subtaskBadges(sub)
            }

            Button { draft.subtasks.removeAll { $0.id == sub.wrappedValue.id } } label: {
                Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(Color.dsTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
            .fill(Color.white.opacity(0.05)))
        .contentShape(Rectangle())
        // Same drag idiom as the task rows (this stack isn't a List, so
        // `.onMove` has nothing to hook into).
        .draggable(sub.wrappedValue.id.uuidString)
        .dropDestination(for: String.self) { dropped, _ in
            guard let s = dropped.first, let id = UUID(uuidString: s) else { return false }
            return moveSubtask(id, before: sub.wrappedValue.id)
        }
        .contextMenu {
            Button {
                if store.promoteSubtask(draft.id, sub.wrappedValue.id) != nil {
                    draft.subtasks.removeAll { $0.id == sub.wrappedValue.id }
                }
            } label: {
                Label("Make a task", systemImage: "arrow.up.right.square")
            }
        }
    }

    /// A step's second line: done-count, priority, pomodoro size and estimate.
    private func subtaskBadges(_ sub: Binding<Subtask>) -> some View {
        HStack(spacing: 6) {
            if settings.showPomodoroBadges, sub.wrappedValue.pomodorosDone > 0 {
                Text("🍅\(sub.wrappedValue.pomodorosDone)")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(Color.dsSecondary)
            }
            subtaskPriorityMenu(sub)
            subtaskKindMenu(sub)
            Text(sub.wrappedValue.estimatedPomodoros.map { "est \($0)" } ?? "no est")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(Color.dsTertiary)
            // Estimate stepper stays visible even with badges hidden — the
            // editor is the only place estimates can be set.
            DSStepper(value: Binding(
                get: { sub.wrappedValue.estimatedPomodoros ?? 0 },
                set: { sub.wrappedValue.estimatedPomodoros = $0 == 0 ? nil : $0 }),
                      range: 0...8)
                .scaleEffect(0.8)
            Spacer(minLength: 0)
        }
    }

    /// Per-step priority flag — imported from templates (`p1` tokens) and
    /// editable here; promote carries it over.
    private func subtaskPriorityMenu(_ sub: Binding<Subtask>) -> some View {
        Menu {
            ForEach(SharinganCore.TaskPriority.levels(custom: settings.customPriorityLevels)) { p in
                Button { sub.wrappedValue.priority = p } label: {
                    Label(settings.priorityName(p),
                          systemImage: sub.wrappedValue.priority == p ? "checkmark"
                                       : (p == .none ? "flag.slash" : "flag.fill"))
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: sub.wrappedValue.priority == .none ? "flag" : "flag.fill")
                    .font(.system(size: 9, weight: .semibold))
                if sub.wrappedValue.priority != .none {
                    Text(settings.priorityShortLabel(sub.wrappedValue.priority))
                        .font(.system(size: 10, design: .rounded).weight(.semibold))
                }
            }
            .foregroundStyle(settings.priorityColorHex(sub.wrappedValue.priority)
                .map { Color(hex: $0) } ?? Color.dsTertiary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.06)))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Priority for this step")
    }

    /// Per-step pomodoro size: overrides the task's kind when this step is the
    /// focus target.
    private func subtaskKindMenu(_ sub: Binding<Subtask>) -> some View {
        Menu {
            Button("Task default") { sub.wrappedValue.pomodoroKind = nil }
            Divider()
            ForEach(PomodoroKind.allCases) { kind in
                Button {
                    sub.wrappedValue.pomodoroKind = kind
                } label: {
                    let cfg = settings.config(for: kind)
                    Label("\(kind.label) · \(cfg.focusMinutes)/\(cfg.breakMinutes) min",
                          systemImage: sub.wrappedValue.pomodoroKind == kind
                              ? "checkmark" : kind.systemImage)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: sub.wrappedValue.pomodoroKind?.systemImage ?? "timer")
                    .font(.system(size: 9, weight: .semibold))
                Text(sub.wrappedValue.pomodoroKind?.label ?? "Auto")
                    .font(.system(size: 10, design: .rounded).weight(.medium))
            }
            .foregroundStyle(sub.wrappedValue.pomodoroKind == nil ? Color.dsTertiary : accent)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.06)))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Pomodoro size for this step")
    }

    // MARK: - Focus history

    /// This task's focus-log rows (its own and its subtasks') for the last
    /// 14 days. The task-level row already includes subtask credits — subtask
    /// lines are detail, not addends (see FocusLog.swift).
    private var history: [FocusLogEntry] {
        store.focusHistory(for: draft.id, days: 14)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HISTORY — LAST 14 DAYS")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.5))
            let byDay = Dictionary(grouping: history, by: \.day)
            ForEach(byDay.keys.sorted(by: >), id: \.self) { day in
                let rows = byDay[day] ?? []
                let taskRow = rows.first { $0.subtaskID == nil }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(Self.historyDayLabel(day))
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer(minLength: 8)
                        Text("🍅 ×\(taskRow?.count ?? 0)")
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white.opacity(0.75))
                        Text(FocusReport.durationLabel(taskRow?.seconds ?? 0))
                            .font(.system(.caption2, design: .rounded).weight(.bold).monospacedDigit())
                            .foregroundStyle(accent)
                            .frame(minWidth: 40, alignment: .trailing)
                    }
                    ForEach(rows.filter { $0.subtaskID != nil }) { sub in
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white.opacity(0.3))
                            Text(sub.title)
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text("🍅 ×\(sub.count) · \(FocusReport.durationLabel(sub.seconds))")
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        .padding(.leading, 12)
                    }
                }
            }
        }
    }

    /// Apps that were frontmost while focusing on this task (its own + subtask
    /// sessions carry the parent `taskID`), aggregated across the whole log and
    /// ranked by time — answers "which apps did I use on this todo".
    private var taskAppTotals: [AnalyticsEngine.AppTotal] {
        let sessions = FocusSessionLog.shared.records.filter { $0.taskID == draft.id }
        return AnalyticsEngine.appTotals(sessions: sessions)
    }

    /// Which Mac(s) this task's focus sessions ran on, with total focus time
    /// each — answers "which device did I run this todo on", ranked by time.
    private var taskDeviceTotals: [(name: String, seconds: TimeInterval)] {
        let sessions = FocusSessionLog.shared.records.filter {
            $0.taskID == draft.id && $0.phase == .focus
        }
        var byDevice: [String: TimeInterval] = [:]
        for s in sessions {
            byDevice[s.deviceName ?? "Unknown Mac", default: 0] += s.seconds
        }
        return byDevice.map { (name: $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
    }

    private var devicesUsedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RUN ON")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.5))
            ForEach(taskDeviceTotals, id: \.name) { dev in
                HStack(spacing: 10) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 20)
                    Text(dev.name)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(FocusReport.durationLabel(dev.seconds))
                        .font(.system(.caption2, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(accent)
                }
            }
        }
    }

    private var appsUsedSection: some View {
        let totals = taskAppTotals
        let peak = totals.first?.seconds ?? 1
        return VStack(alignment: .leading, spacing: 8) {
            Text("APPS USED WHILE FOCUSING")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.5))
            ForEach(totals.prefix(6)) { total in
                HStack(spacing: 10) {
                    Image(nsImage: AnalyticsAppsView.icon(for: total.bundleID))
                        .resizable().frame(width: 20, height: 20)
                    Text(AnalyticsAppsView.name(for: total.bundleID))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    GeometryReader { geo in
                        Capsule().fill(Color.white.opacity(0.07))
                            .overlay(alignment: .leading) {
                                Capsule().fill(accent.opacity(0.8))
                                    .frame(width: geo.size.width
                                           * CGFloat(total.seconds / peak))
                            }
                    }
                    .frame(height: 5)
                    Text(AnalyticsAppsView.durationLabel(total.seconds))
                        .font(.system(.caption2, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(accent)
                        .frame(minWidth: 40, alignment: .trailing)
                }
            }
        }
    }

    private static func historyDayLabel(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d"
        return f.string(from: day)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            store.delete(draft.id)
            close()
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

    /// `.docked`'s pinned Delete Task / Save changes pair, mirroring the
    /// reference mock's footer instead of the sheet's in-scroll delete row +
    /// header Save.
    private var dockedFooter: some View {
        HStack(spacing: 10) {
            Button(role: .destructive) {
                store.delete(draft.id)
                close()
            } label: {
                Text("Delete Task")
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .foregroundStyle(.red.opacity(0.9))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(Color.red.opacity(0.12)))
            }
            .buttonStyle(.pressableSubtle)

            Button { save() } label: {
                Text("Save changes")
                    .font(.system(.callout, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(accent))
            }
            .buttonStyle(.pressableSubtle)
            .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(16)
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

    /// Docked-panel chrome — the same glass-card recipe as the sidebar
    /// (`MainWindowView.sidebar`) instead of the sheet's full-bleed scrim, so
    /// the panel reads as part of the window rather than a modal overlay.
    private var dockedBackground: some View {
        RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .fill(accent.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .stroke(
                        LinearGradient(colors: [Color.white.opacity(0.35),
                                                Color.white.opacity(0.08)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
            )
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
        return cal.startOfDay(for: base)
    }
    private func upcomingWeekend() -> Date {
        let cal = Calendar.current
        var d = Date()
        for _ in 0..<7 {
            if cal.component(.weekday, from: d) == 7 { break }   // Saturday
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return cal.startOfDay(for: d)
    }
    private func nextMonday() -> Date {
        let cal = Calendar.current
        var d = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        for _ in 0..<7 { if cal.component(.weekday, from: d) == 2 { break }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
        return cal.startOfDay(for: d)
    }

    private func commitTag() {
        for part in tagDraft.split(whereSeparator: { $0 == "," || $0 == " " }) {
            let t = part.trimmingCharacters(in: .whitespaces).lowercased()
            if !t.isEmpty, !draft.tags.contains(t) { draft.tags.append(t) }
        }
        tagDraft = ""
    }
    /// Whether a step passes the section's filter menu.
    private func subtaskShown(_ sub: Subtask) -> Bool {
        switch subStatus {
        case .all:  break
        case .open: if sub.isDone { return false }
        case .done: if !sub.isDone { return false }
        }
        if let p = subPriority, sub.priority != p { return false }
        return true
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
        close()
    }

    /// `.sheet` dismisses itself; `.docked` isn't a real presentation, so its
    /// parent's `onClose` owns hiding the panel.
    private func close() {
        if presentation == .docked { onClose?() } else { dismiss() }
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
