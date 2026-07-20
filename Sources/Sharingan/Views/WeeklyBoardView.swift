import SwiftUI
import SharinganCore

/// A beautiful Trello/Todoist-style weekly planner: a backlog + Mon–Sun columns,
/// each a frosted-glass drop target. Drag a task card onto a day to plan it, or
/// back onto "Unscheduled" to clear its plan. Everything animates — cards spring
/// into place, the target column glows, cards lift on hover, the week slides.
struct WeeklyBoardView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var store = TaskStore.shared

    /// Weeks away from the current week (0 = this week).
    @State private var weekOffset = 0
    /// Card currently under the pointer — lifts slightly.
    @State private var hoveredCard: UUID?
    /// Column currently being dragged over — highlighted.
    @State private var targetedColumn: String?
    /// Draft for the quick-add field in the Unscheduled column.
    @State private var backlogDraft = ""
    /// Task being edited in the full editor sheet (click a card, or context menu → Edit…).
    @State private var editorTask: TaskItem?
    /// Same ordering the Tasks list uses — one shared preference; applies
    /// within every column.
    @AppStorage("tasks.sortMode") private var sortModeRaw = TaskSortMode.manual.rawValue
    private var sortMode: TaskSortMode { TaskSortMode(rawValue: sortModeRaw) ?? .manual }
    /// One-dimension narrowing (category / tag / priority) across the board.
    @State private var categoryFilter: String?
    @State private var tagFilter: String?
    @State private var priorityFilter: TaskPriority?
    @State private var deviceFilter: String?
    private var isNarrowed: Bool {
        categoryFilter != nil || tagFilter != nil || priorityFilter != nil || deviceFilter != nil
    }

    private let columnWidth: CGFloat = 204
    /// Cards must be sized, not merely capped: the board scrolls horizontally,
    /// so the column is handed an unspecified width proposal, and under one a
    /// `maxWidth: .infinity` card resolves to its own ideal width — which for a
    /// long title is far wider than the column, spilling over both neighbours.
    private var cardWidth: CGFloat { columnWidth - 24 }   // minus the column's padding

    /// A column's cards as shown: narrowed by the filter, in the shared sort
    /// order (the store already hands columns over in manual order).
    private func boardItems(_ items: [TaskItem]) -> [TaskItem] {
        narrowTasks(items, category: categoryFilter, tag: tagFilter,
                    priority: priorityFilter, device: deviceFilter)
            .sorted(by: sortMode.inOrder)
    }

    private var cal: Calendar { Calendar.current }
    private var accent: Color { timer.settings.theme.accent }

    /// First day (Monday or Sunday, per settings) of the visible week.
    private var weekStart: Date {
        timer.settings.weekStart(offset: weekOffset, calendar: cal)
    }

    private var days: [Date] {
        (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }

    /// Count of open tasks planned within the visible week — filtered, so the
    /// header agrees with the cards actually on the board.
    private var plannedThisWeek: Int {
        days.reduce(0) { $0 + boardItems(store.tasksDue(on: $1)).count }
    }

    private var hasAnyOpenTask: Bool { store.tasks.contains { !$0.isDone && $0.trashedAt == nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            if !hasAnyOpenTask {
                Label("Add a task in the Unscheduled column, then drag it onto a day to plan your week.",
                      systemImage: "hand.draw")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.dsSecondary)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(Color.dsFill))
                    .transition(.opacity)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    backlogColumn
                    ForEach(days, id: \.self) { day in
                        dayColumn(day)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
                // Slide + fade the whole week when navigating.
                .id(weekOffset)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(x: weekOffset >= 0 ? 44 : -44)),
                    removal: .opacity))
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(maxHeight: .infinity)
        }
        .sheet(item: $editorTask) { task in
            TaskEditorView(task: task, accent: accent, settings: timer.settings)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Week")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                Text(plannedThisWeek == 0 ? "Nothing planned yet"
                     : "\(plannedThisWeek) task\(plannedThisWeek == 1 ? "" : "s") planned")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .contentTransition(.opacity)
            }

            Spacer()

            if weekOffset != 0 {
                Button {
                    withAnimation(DS.Motion.standard) { weekOffset = 0 }
                } label: {
                    Text("Today")
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Capsule().fill(accent.opacity(0.9)))
                        .foregroundStyle(.white)
                        .shadow(color: accent.opacity(0.5), radius: 8, y: 3)
                }
                .buttonStyle(.pressableSubtle)
                .transition(.opacity.combined(with: .scale))
            }

            sortMenu
            filterMenu

            HStack(spacing: 6) {
                navButton("chevron.left") { weekOffset -= 1 }
                Text(rangeLabel)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(minWidth: 152)
                    .contentTransition(.opacity)
                navButton("chevron.right") { weekOffset += 1 }
            }
            .padding(6)
            .background(
                Capsule().fill(.ultraThinMaterial)
                    .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
            )
        }
    }

    /// Sort + filter, styled like the week-nav circles. Sort applies within
    /// every column; the filter narrows cards across the whole board.
    private var sortMenu: some View {
        Menu {
            TaskSortMenuItems(sortModeRaw: $sortModeRaw)
        } label: {
            menuCircle("arrow.up.arrow.down", active: sortMode != .manual)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help(sortMode == .manual ? "Sort tasks" : "Sorted by \(sortMode.label)")
        .accessibilityLabel("Sort tasks")
    }

    private var filterMenu: some View {
        Menu {
            TaskFilterMenuItems(store: store, settings: timer.settings,
                                categoryFilter: $categoryFilter,
                                tagFilter: $tagFilter,
                                priorityFilter: $priorityFilter,
                                deviceFilter: $deviceFilter)
        } label: {
            menuCircle(isNarrowed ? "line.3.horizontal.decrease.circle.fill"
                                  : "line.3.horizontal.decrease.circle",
                       active: isNarrowed)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Filter by category, tag, or priority")
        .accessibilityLabel("Filter tasks")
    }

    private func menuCircle(_ icon: String, active: Bool) -> some View {
        Image(systemName: icon)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(active ? accent : .white)
            .frame(width: 28, height: 28)
            .background(Circle().fill(active ? accent.opacity(0.2)
                                             : Color.white.opacity(0.08)))
            .contentShape(Circle())
    }

    private func navButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(DS.Motion.standard) { action() }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.pressableSubtle)
    }

    private var rangeLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d"
        let end = days.last ?? weekStart
        return "\(f.string(from: weekStart)) – \(f.string(from: end))"
    }

    // MARK: - Columns

    private var backlogColumn: some View {
        let items = boardItems(store.undatedTasks)
        return columnContainer(
            id: "unscheduled", isToday: false, isWeekend: false,
            header: AnyView(backlogHeader(count: items.count)),
            items: items,
            onDrop: { store.clearDueDate($0) })
    }

    private func dayColumn(_ day: Date) -> some View {
        let items = boardItems(store.tasksDue(on: day))
        let isToday = cal.isDateInToday(day)
        return columnContainer(
            id: dayKey(day), isToday: isToday, isWeekend: cal.isDateInWeekend(day),
            header: AnyView(dayHeader(day, isToday: isToday, count: items.count)),
            items: items,
            onDrop: { store.snooze($0, to: day) })
    }

    private func backlogHeader(count: Int) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "tray.full")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dsSecondary)
                Text("Unscheduled")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                countBadge(count, tint: Color.dsSecondary)
            }
            // Quick-add straight into the backlog — no need to leave the board.
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accent)
                TextField("Add task", text: $backlogDraft)
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white)
                    .onSubmit(addBacklog)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(Color.dsFill))
        }
    }

    private func addBacklog() {
        let t = backlogDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        // Whole pasted documents import in bulk; a line adds one task.
        var documentResult: TaskStore.DocumentImport?
        withAnimation(DS.Motion.standard) {
            documentResult = store.importIfDocument(t)
            if documentResult == nil { store.add(title: t) }
        }
        backlogDraft = ""
        if let documentResult { ImportDuplicatePrompt.resolve(documentResult, store: store) }
    }

    private func dayHeader(_ day: Date, isToday: Bool, count: Int) -> some View {
        HStack(spacing: 9) {
            // Date chip — filled accent circle for today, like a calendar's "today".
            Text(dayNumber(day))
                .font(.system(.callout, design: .rounded).weight(.bold))
                .foregroundStyle(isToday ? .white : .white.opacity(0.9))
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(isToday
                                  ? AnyShapeStyle(accent)
                                  : AnyShapeStyle(Color.white.opacity(0.06)))
                )
                .shadow(color: isToday ? accent.opacity(0.6) : .clear, radius: 6, y: 2)
            VStack(alignment: .leading, spacing: 0) {
                Text(weekdayName(day).uppercased())
                    .font(.system(.caption2, design: .rounded).weight(.heavy))
                    .tracking(1.1)
                    .foregroundStyle(isToday ? accent : .white.opacity(0.75))
                Text(isToday ? "Today" : monthName(day))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
            countBadge(count, tint: isToday ? accent : .white.opacity(0.45))
        }
    }

    private func countBadge(_ n: Int, tint: Color) -> some View {
        Text("\(n)")
            .font(.system(.caption2, design: .rounded).weight(.bold))
            .foregroundStyle(n == 0 ? .white.opacity(0.3) : tint)
            .frame(minWidth: 20, minHeight: 20)
            .background(Circle().fill(Color.white.opacity(n == 0 ? 0.03 : 0.08)))
    }

    private func columnContainer(id: String, isToday: Bool, isWeekend: Bool,
                                 header: AnyView, items: [TaskItem],
                                 onDrop: @escaping (UUID) -> Void) -> some View {
        let targeted = targetedColumn == id
        return VStack(alignment: .leading, spacing: 12) {
            header
            // Cards scroll within the column so a long day never overflows the
            // board; the header stays pinned.
            ScrollView(.vertical, showsIndicators: false) {
                if items.isEmpty {
                    emptyDrop(targeted: targeted)
                } else {
                    VStack(spacing: 9) {
                        ForEach(items) { task in
                            card(task)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.88).combined(with: .opacity),
                                    removal: .scale(scale: 0.9).combined(with: .opacity)))
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(12)
        .frame(width: columnWidth, alignment: .top)
        .frame(minHeight: 440, maxHeight: .infinity, alignment: .top)
        .background(columnBackground(isToday: isToday, isWeekend: isWeekend, targeted: targeted))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .stroke(targeted ? accent.opacity(0.8)
                        : (isToday ? accent.opacity(0.4) : Color.white.opacity(0.08)),
                        lineWidth: targeted ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
        .scaleEffect(targeted ? 1.015 : 1)
        .animation(DS.Motion.standard, value: targeted)
        .dropDestination(for: String.self) { dropped, _ in
            guard let s = dropped.first, let id = UUID(uuidString: s) else { return false }
            withAnimation(DS.Motion.standard) { onDrop(id) }
            return true
        } isTargeted: { hovering in
            targetedColumn = hovering ? id : (targetedColumn == id ? nil : targetedColumn)
        }
    }

    private func columnBackground(isToday: Bool, isWeekend: Bool, targeted: Bool) -> some View {
        RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .fill(LinearGradient(
                        colors: targeted ? [accent.opacity(0.22), accent.opacity(0.05)]
                            : isToday ? [accent.opacity(0.16), accent.opacity(0.02)]
                            : isWeekend ? [Color.white.opacity(0.015), .clear]
                            : [Color.white.opacity(0.07), .clear],
                        startPoint: .top, endPoint: .bottom))
            )
            .overlay( // top glass highlight
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.25), .clear],
                                           startPoint: .top, endPoint: .center),
                            lineWidth: 1)
                    .blendMode(.overlay)
            )
    }

    /// Empty column: a quiet blank normally, a lit dashed prompt only when a card
    /// is being dragged over it — so an empty week isn't a wall of "Drop here".
    private func emptyDrop(targeted: Bool) -> some View {
        Group {
            if targeted {
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(accent.opacity(0.8),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .overlay(
                        Text("Release to plan")
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(accent))
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, minHeight: 60)
        .animation(DS.Motion.gentle, value: targeted)
    }

    // MARK: - Card

    /// A Jira issue card: title on top, then a meta lane carrying the issue-type
    /// square, the issue key, and — pushed right — priority, subtask count and
    /// the estimate pill. Flat surface, tight radius, hairline border: the card
    /// reads as a document, not as glass.
    private func card(_ task: TaskItem) -> some View {
        let color = Color(hex: store.color(for: task.category))
        let hovered = hoveredCard == task.id
        return VStack(alignment: .leading, spacing: 8) {
            Text(task.title)
                .font(.system(size: 12.5, design: .rounded).weight(.regular))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            // The deadline gets a row of its own: squeezed onto the meta lane it
            // had no width left for its text and collapsed to a bare icon.
            if let due = task.dueDate {
                dueLozenge(task, due)
            }

            metaLane(task, color)
        }
        .padding(.horizontal, 10).padding(.vertical, 10)
        .frame(width: cardWidth, alignment: .leading)
        .frame(minHeight: 78, alignment: .top)
        // Only as tall as its content — without this the greedy background
        // stretched each card to fill the whole 440pt column.
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(hovered ? 0.13 : 0.075))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Color.white.opacity(hovered ? 0.18 : 0.09), lineWidth: 1)
        )
        .shadow(color: .black.opacity(hovered ? 0.28 : 0.14), radius: hovered ? 6 : 2, y: hovered ? 3 : 1)
        .animation(DS.Motion.standard, value: hovered)
        .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .onTapGesture { editorTask = task }
        .onHover { inside in
            hoveredCard = inside ? task.id : (hoveredCard == task.id ? nil : hoveredCard)
        }
        .draggable(task.id.uuidString) {
            // Jira's drag ghost is the card itself, tilted a couple of degrees.
            HStack(spacing: 6) {
                typeSquare(color)
                Text(task.title)
                    .font(.system(size: 12.5, design: .rounded).weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .frame(maxWidth: cardWidth, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.black.opacity(0.75)))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
            .rotationEffect(.degrees(-2))
        }
        .contextMenu {
            Button { startFocus(task) } label: {
                Label("Start focus", systemImage: "play.fill")
            }
            Button { editorTask = task } label: {
                Label("Edit…", systemImage: "pencil")
            }
            Menu {
                ForEach(TaskPriority.levels(custom: timer.settings.customPriorityLevels)) { p in
                    Button {
                        store.setPriority(task.id, p)
                    } label: {
                        Label(timer.settings.priorityName(p),
                              systemImage: task.priority == p ? "checkmark" : "flag.fill")
                    }
                }
            } label: { Label("Priority", systemImage: "flag.fill") }
            Button { store.clearDueDate(task.id) } label: {
                Label("Clear date", systemImage: "calendar.badge.minus")
            }
            Divider()
            Button(role: .destructive) { store.delete(task.id) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// The card's footer: what the task *is* (type, code) on the left, how it's
    /// tracking (priority, steps, pomodoros) on the right. Every chip is
    /// `.fixedSize()` — without it they wrap character by character ("0 / 3") —
    /// and together they stay well inside the column at their natural width.
    private func metaLane(_ task: TaskItem, _ color: Color) -> some View {
        HStack(spacing: 6) {
            typeSquare(color)
            if let code = task.code {
                Text(code)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(.white.opacity(0.5))
                    .strikethrough(task.isDone, color: .white.opacity(0.4))
                    .fixedSize()
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
            if task.priority != .none, let hex = timer.settings.priorityColorHex(task.priority) {
                Image(systemName: priorityArrow(task.priority))
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Color(hex: hex))
                    .help(timer.settings.priorityName(task.priority))
                    .fixedSize()
            }
            if !task.subtasks.isEmpty {
                Label("\(task.subtasks.filter(\.isDone).count)/\(task.subtasks.count)",
                      systemImage: "checklist")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize()
            }
            if timer.settings.showPomodoroBadges,
               task.pomodorosDone > 0 || task.effectiveEstimate != nil {
                storyPoints(task)
            }
        }
        .lineLimit(1)
    }

    /// Jira's issue-type glyph: a small filled square, tinted by category.
    private func typeSquare(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(color)
            .frame(width: 12, height: 12)
            .overlay(
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(.white.opacity(0.95))
            )
    }

    /// Jira's due-date lozenge — the deadline reads by colour before it reads by
    /// text: red once missed, amber while it's today or tomorrow, quiet grey
    /// otherwise. In countdown mode the label is time-relative, so it has to be
    /// redrawn as the clock moves: a per-minute `TimelineView` is enough, since
    /// the finest unit shown is a minute.
    @ViewBuilder
    private func dueLozenge(_ task: TaskItem, _ due: Date) -> some View {
        if timer.settings.deadlineAsCountdown && !task.isDone {
            TimelineView(.periodic(from: .now, by: 60)) { ctx in
                lozengeBody(due, overdue: task.isOverdue(now: ctx.date),
                            text: DueDate.countdown(to: due, now: ctx.date))
            }
        } else {
            lozengeBody(due, overdue: task.isOverdue(), text: dueLabel(due))
        }
    }

    private func lozengeBody(_ due: Date, overdue: Bool, text: String) -> some View {
        let soon = !overdue && (cal.isDateInToday(due) || cal.isDateInTomorrow(due))
        let tint: Color = overdue ? .red : soon ? .orange : .white.opacity(0.55)
        return HStack(spacing: 3) {
            Image(systemName: overdue ? "clock.badge.exclamationmark.fill"
                              : timer.settings.deadlineAsCountdown ? "timer" : "calendar")
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .foregroundStyle(overdue || soon ? tint : .white.opacity(0.55))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(overdue || soon ? 0.16 : 0.08)))
            .contentTransition(.numericText())
            .help(overdue ? "Overdue — due \(fullDue(due))" : "Due \(fullDue(due))")
    }

    /// Short enough for a 204pt column: a weekday inside this week, a date
    /// outside it, plus the time when the deadline carries one.
    private func dueLabel(_ due: Date) -> String {
        let day: String
        if cal.isDateInToday(due) { day = "Today" }
        else if cal.isDateInTomorrow(due) { day = "Tomorrow" }
        else if cal.isDateInYesterday(due) { day = "Yesterday" }
        else if let days = cal.dateComponents([.day], from: Date(), to: due).day,
                (0..<7).contains(days) { day = fmt("EEE", due) }
        else { day = fmt("MMM d", due) }
        return DueDate.isDateOnly(due) ? day : "\(day) \(fmt("HH:mm", due))"
    }

    private func fullDue(_ due: Date) -> String {
        DueDate.isDateOnly(due) ? fmt("EEEE, MMM d", due) : fmt("EEEE, MMM d 'at' HH:mm", due)
    }

    /// Jira's story-point pill: a grey capsule at the card's trailing edge.
    private func storyPoints(_ task: TaskItem) -> some View {
        Text(task.effectiveEstimate.map { "\(task.pomodorosDone)/\($0)" }
             ?? "\(task.pomodorosDone)")
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Color.white.opacity(0.12)))
            .fixedSize()
            .help("\(task.pomodorosDone) of \(task.effectiveEstimate.map(String.init) ?? "—") pomodoros")
    }

    /// Jira ranks priority with arrows, not flags: up = high, down = low.
    private func priorityArrow(_ p: TaskPriority) -> String {
        switch p.rawValue {
        case 1:  return "arrow.down"
        case 2:  return "equal"
        default: return "arrow.up"   // 3 and any custom level above it
        }
    }

    // MARK: - Helpers

    private func startFocus(_ task: TaskItem) {
        store.setActive(task.id)
        timer.startFocusSession(kind: store.resolvedActiveKind)
    }

    private func weekdayName(_ d: Date) -> String { fmt("EEE", d) }
    private func monthName(_ d: Date) -> String { fmt("MMM", d) }
    private func dayNumber(_ d: Date) -> String { fmt("d", d) }
    private func dayKey(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }
    private func fmt(_ pattern: String, _ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US")
        f.dateFormat = pattern; return f.string(from: d)
    }
}
