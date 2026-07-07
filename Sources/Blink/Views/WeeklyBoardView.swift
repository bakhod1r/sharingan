import SwiftUI
import BlinkCore

/// A Trello/Todoist-style weekly planner: eight columns (a backlog + Mon–Sun),
/// each a drop target. Drag a task card onto a day to plan it for that day, or
/// back onto "Unscheduled" to clear its plan. Everything animates: cards spring
/// into place, the drop target glows, and week navigation slides.
struct WeeklyBoardView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var store = TaskStore.shared

    /// Weeks away from the current week (0 = this week).
    @State private var weekOffset = 0
    /// Card currently under the pointer — nudges up slightly.
    @State private var hoveredCard: UUID?
    /// Column currently being dragged over — highlighted.
    @State private var targetedColumn: String?

    private let columnWidth: CGFloat = 196

    private var cal: Calendar { Calendar.current }

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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    backlogColumn
                    ForEach(days, id: \.self) { day in
                        dayColumn(day)
                    }
                }
                .padding(.bottom, 10)
                // Slide + fade the whole week when navigating.
                .id(weekOffset)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(x: weekOffset >= 0 ? 40 : -40)),
                    removal: .opacity))
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            Text("Week")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(.white)

            Spacer()

            if weekOffset != 0 {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { weekOffset = 0 }
                } label: {
                    Text("Today")
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }

            HStack(spacing: 10) {
                navButton("chevron.left") { weekOffset -= 1 }
                Text(rangeLabel)
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(minWidth: 150)
                    .contentTransition(.opacity)
                navButton("chevron.right") { weekOffset += 1 }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.06)))
        }
    }

    private func navButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { action() }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
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
        return column(
            id: "unscheduled",
            title: "Unscheduled",
            subtitle: "\(items.count)",
            isToday: false,
            accent: .white.opacity(0.5),
            items: items,
            onDrop: { store.setPlannedDate($0, nil) })
    }

    private func dayColumn(_ day: Date) -> some View {
        let items = store.tasksPlanned(on: day)
        let isToday = cal.isDateInToday(day)
        return column(
            id: dayKey(day),
            title: weekdayName(day),
            subtitle: dayNumber(day),
            isToday: isToday,
            accent: isToday ? Color.accentColor : .white.opacity(0.4),
            items: items,
            onDrop: { store.setPlannedDate($0, day) })
    }

    private func column(id: String, title: String, subtitle: String,
                        isToday: Bool, accent: Color,
                        items: [TaskItem],
                        onDrop: @escaping (UUID) -> Void) -> some View {
        let targeted = targetedColumn == id
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 7, height: 7)
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(isToday ? Color.accentColor : .white)
                Spacer()
                Text(subtitle)
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(.white.opacity(0.5))
            }

            if items.isEmpty {
                Text("Drop here")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(targeted ? 0.7 : 0.28))
                    .frame(maxWidth: .infinity, minHeight: 54)
            } else {
                ForEach(items) { task in
                    card(task)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.9).combined(with: .opacity),
                            removal: .opacity))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: columnWidth, alignment: .top)
        .frame(minHeight: 420, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(targeted ? 0.12 : (isToday ? 0.06 : 0.03)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(targeted ? Color.accentColor.opacity(0.7)
                        : (isToday ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.06)),
                        lineWidth: targeted ? 2 : 1)
        )
        .scaleEffect(targeted ? 1.02 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: targeted)
        .dropDestination(for: String.self) { dropped, _ in
            guard let s = dropped.first, let id = UUID(uuidString: s) else { return false }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                onDrop(id)
            }
            return true
        } isTargeted: { hovering in
            targetedColumn = hovering ? id : (targetedColumn == id ? nil : targetedColumn)
        }
    }

    // MARK: - Card

    private func card(_ task: TaskItem) -> some View {
        let accent = Color(hex: store.color(for: task.category))
        let hovered = hoveredCard == task.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Circle().fill(accent).frame(width: 7, height: 7).padding(.top, 4)
                Text(task.title)
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if let due = task.dueDate {
                    Label(shortDue(due), systemImage: "calendar")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(task.isOverdue() ? Color.red : .white.opacity(0.55))
                }
                if task.subtaskProgress.total > 0 {
                    Text("☑\(task.subtaskProgress.done)/\(task.subtaskProgress.total)")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                if task.pomodorosDone > 0 || task.estimatedPomodoros != nil {
                    Text(task.estimatedPomodoros.map { "🍅\(task.pomodorosDone)/\($0)" }
                         ?? "🍅\(task.pomodorosDone)")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(hovered ? 0.12 : 0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(accent.opacity(hovered ? 0.5 : 0.18), lineWidth: 1)
        )
        .scaleEffect(hovered ? 1.03 : 1)
        .shadow(color: .black.opacity(hovered ? 0.25 : 0), radius: 6, y: 3)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovered)
        .onHover { inside in
            hoveredCard = inside ? task.id : (hoveredCard == task.id ? nil : hoveredCard)
        }
        .draggable(task.id.uuidString) {
            // Drag preview.
            Text(task.title)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(accent.opacity(0.9)))
        }
        .contextMenu {
            Button { store.setActive(task.id); startFocus(task) } label: {
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

    private func weekdayName(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "EEE"
        return f.string(from: d)
    }
    private func dayNumber(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "d"
        return f.string(from: d)
    }
    private func dayKey(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
    private func shortDue(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US")
        f.dateFormat = Calendar.current.isDateInToday(d) ? "'today'" : "MMM d"
        return f.string(from: d)
    }
}
