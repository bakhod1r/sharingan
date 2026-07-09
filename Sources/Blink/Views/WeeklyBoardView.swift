import SwiftUI
import BlinkCore

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

    private let columnWidth: CGFloat = 204

    private var cal: Calendar { Calendar.current }
    private var accent: Color { timer.settings.theme.accent }

    /// Monday that starts the visible week.
    private var weekStart: Date {
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)   // 1=Sun … 7=Sat
        let sinceMonday = (weekday + 5) % 7
        let thisMonday = cal.date(byAdding: .day, value: -sinceMonday, to: today) ?? today
        return cal.date(byAdding: .day, value: weekOffset * 7, to: thisMonday) ?? thisMonday
    }

    private var days: [Date] {
        (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }

    /// Count of open tasks planned within the visible week.
    private var plannedThisWeek: Int {
        days.reduce(0) { $0 + store.tasksPlanned(on: $1).count }
    }

    private var hasAnyOpenTask: Bool { store.tasks.contains { !$0.isDone } }

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
            }
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
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { weekOffset = 0 }
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

    private func navButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { action() }
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
        let items = store.unscheduledTasks
        return columnContainer(
            id: "unscheduled", isToday: false, isWeekend: false,
            header: AnyView(backlogHeader(count: items.count)),
            items: items,
            onDrop: { store.setPlannedDate($0, nil) })
    }

    private func dayColumn(_ day: Date) -> some View {
        let items = store.tasksPlanned(on: day)
        let isToday = cal.isDateInToday(day)
        return columnContainer(
            id: dayKey(day), isToday: isToday, isWeekend: cal.isDateInWeekend(day),
            header: AnyView(dayHeader(day, isToday: isToday, count: items.count)),
            items: items,
            onDrop: { store.setPlannedDate($0, day) })
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
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { store.add(title: t) }
        backlogDraft = ""
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
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: columnWidth, alignment: .top)
        .frame(minHeight: 440, alignment: .top)
        .background(columnBackground(isToday: isToday, isWeekend: isWeekend, targeted: targeted))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .stroke(targeted ? accent.opacity(0.8)
                        : (isToday ? accent.opacity(0.4) : Color.white.opacity(0.08)),
                        lineWidth: targeted ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
        .scaleEffect(targeted ? 1.015 : 1)
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: targeted)
        .dropDestination(for: String.self) { dropped, _ in
            guard let s = dropped.first, let id = UUID(uuidString: s) else { return false }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { onDrop(id) }
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
        .animation(.easeInOut(duration: 0.2), value: targeted)
    }

    // MARK: - Card

    private func card(_ task: TaskItem) -> some View {
        let color = Color(hex: store.color(for: task.category))
        let hovered = hoveredCard == task.id
        return VStack(alignment: .leading, spacing: 6) {
            Text(task.title)
                .font(.system(.callout, design: .rounded).weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            let hasMeta = task.dueDate != nil || task.subtaskProgress.total > 0
                || task.pomodorosDone > 0 || task.estimatedPomodoros != nil
                || !task.tags.isEmpty
            if hasMeta {
                HStack(spacing: 7) {
                    if let due = task.dueDate {
                        Label(shortDue(due), systemImage: "calendar")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(task.isOverdue() ? Color.red : .white.opacity(0.55))
                    }
                    if let tag = task.tags.first {
                        Text("#\(tag)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(color)
                    }
                    if task.subtaskProgress.total > 0 {
                        Text("☑\(task.subtaskProgress.done)/\(task.subtaskProgress.total)")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(task.subtaskProgress.done == task.subtaskProgress.total
                                             ? Color.green : .white.opacity(0.55))
                    }
                    Spacer(minLength: 0)
                    if task.pomodorosDone > 0 || task.estimatedPomodoros != nil {
                        Text(task.estimatedPomodoros.map { "🍅\(task.pomodorosDone)/\($0)" }
                             ?? "🍅\(task.pomodorosDone)")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        }
        .padding(.leading, 12).padding(.trailing, 9).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Only as tall as its content — without this the greedy accent shape
        // stretched each card to fill the whole 440pt column.
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.white.opacity(hovered ? 0.15 : 0.09),
                             Color.white.opacity(hovered ? 0.08 : 0.04)],
                    startPoint: .top, endPoint: .bottom))
        )
        // Category accent as a leading bar sized to the card, not a greedy sibling.
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 3)
                .padding(.vertical, 6)
        }
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(color.opacity(hovered ? 0.55 : 0.2), lineWidth: 1)
        )
        .scaleEffect(hovered ? 1.035 : 1)
        .shadow(color: .black.opacity(hovered ? 0.3 : 0.12), radius: hovered ? 9 : 4, y: hovered ? 5 : 2)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovered)
        .onHover { inside in
            hoveredCard = inside ? task.id : (hoveredCard == task.id ? nil : hoveredCard)
        }
        .draggable(task.id.uuidString) {
            Text(task.title)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.95)))
                .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
        }
        .contextMenu {
            Button { startFocus(task) } label: {
                Label("Start focus", systemImage: "play.fill")
            }
            Button { store.setPlannedDate(task.id, nil) } label: {
                Label("Unschedule", systemImage: "calendar.badge.minus")
            }
            Divider()
            Button(role: .destructive) { store.delete(task.id) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Helpers

    private func startFocus(_ task: TaskItem) {
        store.setActive(task.id)
        if timer.phase != .focus { timer.stop() }
        timer.start()
    }

    private func weekdayName(_ d: Date) -> String { fmt("EEE", d) }
    private func monthName(_ d: Date) -> String { fmt("MMM", d) }
    private func dayNumber(_ d: Date) -> String { fmt("d", d) }
    private func dayKey(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }
    private func shortDue(_ d: Date) -> String {
        Calendar.current.isDateInToday(d) ? "today" : fmt("MMM d", d)
    }
    private func fmt(_ pattern: String, _ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US")
        f.dateFormat = pattern; return f.string(from: d)
    }
}
