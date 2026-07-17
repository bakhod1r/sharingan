import SwiftUI
import SharinganCore

/// The one tag pill used across the Tasks feature — composer, row meta, and the
/// editor. Deliberately **neutral** (no accent/category tint) so tags stop
/// competing with the category bar and the priority flag for color attention;
/// color in a row now means exactly one thing per channel. Pass `onRemove` to
/// get the editable variant (with an ✕); omit it for a read-only chip.
struct TaskTag: View {
    let tag: String
    var onRemove: (() -> Void)? = nil
    /// Custom label color (from the sidebar tag editor); nil keeps the chip
    /// neutral as designed.
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 4) {
            Text("#\(tag)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(tint ?? (onRemove == nil ? Color.dsSecondary : Color.dsPrimary))
                .lineLimit(1)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.dsTertiary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressableSubtle)
                .accessibilityLabel("Remove tag \(tag)")
            }
        }
        .foregroundStyle(onRemove == nil ? Color.dsSecondary : Color.dsPrimary)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.dsFillStrong))
    }
}

/// A muted "+N" pill shown after a truncated tag list so a busy task reads as
/// "two tags and more" instead of silently dropping the rest.
struct TaskTagOverflow: View {
    let count: Int
    var body: some View {
        Text("+\(count)")
            .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(Color.dsTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.dsFill))
    }
}

/// Subtask progress — "2/2", green once every item is ticked off.
///
/// One definition for the three rows that show it: the main window's task rows,
/// the menu-bar popover's, and the notch island's expanded panel. The popover
/// used to spell it "☑2/2" in a *different* font; that copy is gone. The size
/// defaults to the 10pt semibold rounded the main window's meta row already
/// sets, so the main window renders exactly what it rendered before.
/// Marks a task that mirrors a Jira issue: the key in a capsule tinted by the
/// issue type — Epic purple, Story green, Bug red, Sub-task grey, Task (and
/// anything unrecognized) blue. Doubles as the "came from Jira" marker.
struct JiraIssueBadge: View {
    let key: String
    let issueType: String?
    var size: CGFloat = 9

    /// The badge hides itself rather than being filtered out at each call site:
    /// it is drawn from several rows and the board, and a setting that only some
    /// of them honoured would be worse than no setting.
    @AppStorage(JiraService.showTypeBadgeDefaultsKey) private var showTypeBadge = true

    private var tint: Color {
        switch issueType?.lowercased() {
        case "epic":                return Color(hex: "#904EE2")
        case "story":               return Color(hex: "#36B37E")
        case "bug":                 return Color(hex: "#FF5630")
        case "sub-task", "subtask": return Color(hex: "#9AA3AF")
        default:                    return Color(hex: "#4F8DFD")
        }
    }

    @ViewBuilder
    var body: some View {
        if showTypeBadge {
            Text(key)
                .font(.system(size: size, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(tint.opacity(0.14)))
                .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.5))
                .help("\(issueType ?? "Issue") from Jira — \(key)")
                .accessibilityLabel("Jira \(issueType ?? "issue") \(key)")
        }
    }
}

/// The Jira status of a linked task, tinted by category, as a menu button:
/// tap to see the workflow transitions and move the issue (and the board card)
/// without opening Jira. Reads the cached status; transitions are fetched on
/// open. Nothing renders when the task isn't linked or the status isn't cached.
struct JiraStatusChip: View {
    let task: TaskItem
    @State private var transitions: [JiraTransition] = []
    @State private var loading = false
    @State private var status: (name: String, category: String)?

    private var tint: Color {
        switch status?.category {
        case "done":          return Color(hex: "#36B37E")
        case "indeterminate": return Color(hex: "#4F8DFD")
        case "new":           return Color(hex: "#9AA3AF")
        default:              return Color(hex: "#9AA3AF")
        }
    }

    var body: some View {
        if let status {
            Menu {
                // Transitions load when the menu opens, not per visible row —
                // a getTransitions call for every card on every scroll would
                // hammer the API.
                menuContent
                    .onAppear { if transitions.isEmpty { Task { await loadTransitions() } } }
            } label: {
                Text(status.name)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 6).padding(.vertical, 1.5)
                    .background(Capsule().fill(tint.opacity(0.14)))
                    .overlay(Capsule().strokeBorder(tint.opacity(0.3), lineWidth: 0.5))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .onAppear { refreshStatus() }
        } else {
            Color.clear.frame(width: 0, height: 0).onAppear { refreshStatus() }
        }
    }

    @ViewBuilder
    private var menuContent: some View {
        if loading {
            Text("Loading…")
        } else if transitions.isEmpty {
            Text("No moves available")
        } else {
            ForEach(transitions, id: \.id) { t in
                Button { apply(t) } label: {
                    Label(t.name, systemImage: t.hasScreen ? "arrow.up.forward.square" : "arrow.right")
                }
            }
        }
    }

    private func refreshStatus() {
        guard let id = task.jiraIssueID else { return }
        status = AppServices.jiraService?.cachedStatus(issueID: id)
    }

    private func loadTransitions() async {
        guard let key = task.jiraKey, let jira = AppServices.jiraService else { return }
        loading = true
        transitions = await jira.transitions(forIssueKey: key)
        loading = false
    }

    private func apply(_ t: JiraTransition) {
        guard let key = task.jiraKey, let jira = AppServices.jiraService else { return }
        Task {
            if await jira.applyTransition(issueKey: key, transition: t) {
                refreshStatus()
                await loadTransitions()
            }
        }
    }
}

struct SubtaskProgressBadge: View {
    let done: Int
    let total: Int
    var size: CGFloat = 10

    init(_ progress: (done: Int, total: Int), size: CGFloat = 10) {
        self.done = progress.done
        self.total = progress.total
        self.size = size
    }

    var body: some View {
        Label("\(done)/\(total)", systemImage: "checklist")
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(done == total ? Color.green : Color.dsSecondary)
            .help("\(done) of \(total) subtasks done")
            .accessibilityLabel("\(done) of \(total) subtasks done")
    }
}

/// The pomodoro badge on a task row: a progress ring when the task has an
/// estimate to fill against, a plain 🍅 count when it has none, and nothing at
/// all when it has neither.
///
/// Lifted out of `TasksView.estimateRing` — with its no-estimate sibling, which
/// is half the behavior and was written next to it — so the notch island can
/// draw the *same* badge instead of a third variant of one. The estimate is
/// `task.effectiveEstimate` (the subtask sum wins over the task's own), which is
/// the caller's business; this view only draws what it is handed.
///
/// Call sites gate on `settings.showPomodoroBadges`, as they always did.
struct TaskPomodoroBadge: View {
    let done: Int
    /// `nil` = no estimate anywhere on the task, so there is no ring to fill.
    let estimate: Int?
    /// The task's category tint. Green replaces it once the estimate is met.
    var color: Color = .accentColor
    /// 26pt is the main window's row. The notch island's rows are tighter and
    /// pass a smaller one — stroke and digit scale off this, so a small badge is
    /// a small badge and not a fat one.
    var diameter: CGFloat = 26

    private var stroke: CGFloat { diameter * 3 / 26 }
    private var digit: CGFloat { diameter * 10 / 26 }

    @ViewBuilder
    var body: some View {
        if let estimate {
            let frac = min(1, Double(done) / Double(max(1, estimate)))
            let complete = done >= estimate
            ZStack {
                Circle().stroke(Color.dsFillStrong, lineWidth: stroke)
                Circle()
                    .trim(from: 0, to: frac)
                    .stroke(complete ? Color.green : color,
                            style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(done)")
                    .font(.system(size: digit, design: .rounded).weight(.bold))
                    .foregroundStyle(complete ? Color.green : Color.dsPrimary)
            }
            .frame(width: diameter, height: diameter)
            .help("\(done) of \(estimate) pomodoros")
            .accessibilityLabel("\(done) of \(estimate) pomodoros")
        } else if done > 0 {
            Text("🍅\(done)")
                .font(.system(size: digit, design: .rounded).weight(.medium))
                .foregroundStyle(Color.dsSecondary)
                .help("\(done) pomodoros")
                .accessibilityLabel("\(done) pomodoros")
        }
    }
}

/// Priority flag menu (P1–P4) — one component shared by the task composer and the
/// editor, which previously carried near-identical copies that had already drifted.
struct PriorityMenu: View {
    @Binding var priority: SharinganCore.TaskPriority
    /// Priority names/colors/custom levels — the menu lists `levels(custom:)`
    /// and shows each level's user-facing name, rank chip, and flag color.
    let settings: PomodoroSettings
    var body: some View {
        Menu {
            ForEach(SharinganCore.TaskPriority.levels(custom: settings.customPriorityLevels)) { p in
                Button { priority = p } label: {
                    Label(settings.priorityName(p),
                          systemImage: priority == p ? "checkmark"
                                       : (p == .none ? "flag.slash" : "flag.fill"))
                }
            }
        } label: {
            let hex = settings.priorityColorHex(priority)
            HStack(spacing: 5) {
                Image(systemName: priority == .none ? "flag" : "flag.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(priority == .none ? "Priority" : settings.priorityShortLabel(priority))
                    .font(.system(.caption, design: .rounded).weight(.medium))
            }
            .foregroundStyle(hex.map { Color(hex: $0) } ?? Color.dsSecondary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(Color.dsFill))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }
}

/// The sort menu's entries — one per `TaskSortMode`, checkmarked on the
/// active mode. Shared by every surface with a sort control (Tasks view bar,
/// task picker, weekly board) so the mode list never drifts between them.
/// Hosts wrap this in their own `Menu` trigger; the binding is the raw value
/// behind the shared `@AppStorage("tasks.sortMode")`, so all surfaces follow
/// one ordering.
struct TaskSortMenuItems: View {
    @Binding var sortModeRaw: String
    var body: some View {
        let current = TaskSortMode(rawValue: sortModeRaw) ?? .manual
        ForEach(TaskSortMode.allCases) { mode in
            Button {
                withAnimation(DS.Motion.gentle) { sortModeRaw = mode.rawValue }
            } label: {
                Label(mode.label, systemImage: current == mode ? "checkmark" : mode.icon)
            }
        }
    }
}

/// The filter menu's entries — Category / Tag / Priority submenus plus a
/// "Clear filter" row once something is picked. One dimension at a time
/// (matching the sidebar's narrowing); picking the active entry toggles it
/// off. Shared by the Tasks view bar, the task picker, and the weekly board;
/// hosts wrap it in their own `Menu` trigger and bind their narrowing state.
struct TaskFilterMenuItems: View {
    @ObservedObject var store: TaskStore
    /// Priority names and custom levels for the Priority submenu.
    let settings: PomodoroSettings
    @Binding var categoryFilter: String?
    @Binding var tagFilter: String?
    @Binding var priorityFilter: SharinganCore.TaskPriority?
    /// Optional "Mac of origin" dimension — nil (default) hides the submenu, so
    /// call sites that don't filter by device need no extra state.
    var deviceFilter: Binding<String?>? = nil

    var body: some View {
        Menu("Category") {
            ForEach(store.allCategories) { c in
                Button {
                    let on = categoryFilter == c.name
                    set(category: on ? nil : c.name)
                } label: {
                    Label(c.name, systemImage: categoryFilter == c.name ? "checkmark" : c.icon)
                }
            }
        }
        if !store.allTags.isEmpty {
            Menu("Tag") {
                ForEach(store.allTags, id: \.self) { t in
                    Button {
                        let on = tagFilter == t
                        set(tag: on ? nil : t)
                    } label: {
                        Label("#\(t)", systemImage: tagFilter == t ? "checkmark" : "number")
                    }
                }
            }
        }
        Menu("Priority") {
            ForEach(SharinganCore.TaskPriority.levels(custom: settings.customPriorityLevels)) { p in
                Button {
                    let on = priorityFilter == p
                    set(priority: on ? nil : p)
                } label: {
                    Label(settings.priorityName(p),
                          systemImage: priorityFilter == p ? "checkmark" : "flag.fill")
                }
            }
        }
        if let deviceFilter, store.knownDevices.count > 1 {
            Menu("Mac") {
                ForEach(store.knownDevices, id: \.self) { d in
                    Button {
                        withAnimation(DS.Motion.gentle) {
                            deviceFilter.wrappedValue = deviceFilter.wrappedValue == d ? nil : d
                        }
                    } label: {
                        Label(d, systemImage: deviceFilter.wrappedValue == d ? "checkmark" : "desktopcomputer")
                    }
                }
            }
        }
        let deviceActive = deviceFilter?.wrappedValue != nil
        if categoryFilter != nil || tagFilter != nil || priorityFilter != nil || deviceActive {
            Divider()
            Button(role: .destructive) {
                set()
                deviceFilter?.wrappedValue = nil
            } label: {
                Label("Clear filter", systemImage: "xmark.circle")
            }
        }
    }

    /// Sets exactly one dimension (or none), clearing the others.
    private func set(category: String? = nil, tag: String? = nil,
                     priority: SharinganCore.TaskPriority? = nil) {
        withAnimation(DS.Motion.gentle) {
            categoryFilter = category
            tagFilter = tag
            priorityFilter = priority
        }
    }
}

/// Applies the one-dimension narrowing (category / tag / priority) to a flat
/// task list — the picker's and the board's counterpart of `TasksView.
/// narrowed(_:)`, which works on grouped sections.
func narrowTasks(_ items: [TaskItem], category: String?, tag: String?,
                 priority: SharinganCore.TaskPriority?, device: String? = nil) -> [TaskItem] {
    var out = items
    if let c = category { out = out.filter { $0.category == c } }
    if let t = tag { out = out.filter { $0.tags.contains(t) } }
    if let p = priority { out = out.filter { $0.priority == p } }
    if let d = device { out = out.filter { $0.originDevice == d } }
    return out
}

/// The subtask sort menu's entries — one per `SubtaskSortMode`, checkmarked
/// on the active mode. Shared by the expanded subtask panel and the focus
/// picker's step rows; the binding is the raw value behind the shared
/// `@AppStorage("tasks.subtaskSortMode")`.
struct SubtaskSortMenuItems: View {
    @Binding var sortModeRaw: String
    var body: some View {
        let current = SubtaskSortMode(rawValue: sortModeRaw) ?? .manual
        ForEach(SubtaskSortMode.allCases) { mode in
            Button {
                withAnimation(DS.Motion.gentle) { sortModeRaw = mode.rawValue }
            } label: {
                Label(mode.label, systemImage: current == mode ? "checkmark" : mode.icon)
            }
        }
    }
}

/// The subtask filter menu's entries — a status section (All / Open / Done)
/// plus a Priority submenu, and a "Clear filter" row once something narrows.
/// Shared by the subtask panel and the task editor.
struct SubtaskFilterMenuItems: View {
    /// Priority names and custom levels for the Priority submenu.
    let settings: PomodoroSettings
    @Binding var status: SubtaskStatusFilter
    @Binding var priorityFilter: SharinganCore.TaskPriority?

    var body: some View {
        ForEach(SubtaskStatusFilter.allCases) { s in
            Button {
                withAnimation(DS.Motion.gentle) { status = s }
            } label: {
                Label(s.label, systemImage: status == s ? "checkmark" : s.icon)
            }
        }
        Menu("Priority") {
            ForEach(SharinganCore.TaskPriority.levels(custom: settings.customPriorityLevels)) { p in
                Button {
                    withAnimation(DS.Motion.gentle) {
                        priorityFilter = priorityFilter == p ? nil : p
                    }
                } label: {
                    Label(settings.priorityName(p),
                          systemImage: priorityFilter == p ? "checkmark" : "flag.fill")
                }
            }
        }
        if status != .all || priorityFilter != nil {
            Divider()
            Button(role: .destructive) {
                withAnimation(DS.Motion.gentle) { status = .all; priorityFilter = nil }
            } label: {
                Label("Clear filter", systemImage: "xmark.circle")
            }
        }
    }
}
