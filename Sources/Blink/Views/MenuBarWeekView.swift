import SwiftUI
import BlinkCore

/// The main-window weekly board at popover scale: an Unscheduled backlog column
/// plus Mon–Sun day columns in a horizontal scroll, frosted-glass drop targets
/// and draggable cards — same interaction language as `WeeklyBoardView`, sized
/// for the 360pt menu bar popover. Rescheduling also works without dragging via
/// each card's context menu.
struct MenuBarWeekView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var store = TaskStore.shared

    /// Weeks away from the current week (0 = this week).
    @State private var weekOffset = 0
    /// Column currently being dragged over — highlighted.
    @State private var targetedColumn: String?
    /// Draft for the quick-add field in the Unscheduled column.
    @State private var backlogDraft = ""

    /// Column geometry, shared with `MenuBarView` so the popover can widen to
    /// fit the full board (backlog + 7 days) when this tab is selected.
    static let columnWidth: CGFloat = 140
    static let columnSpacing: CGFloat = 8
    /// Board content width: 8 columns + 7 gaps.
    static let boardWidth: CGFloat = 8 * columnWidth + 7 * columnSpacing

    private let columnHeight: CGFloat = 452

    private var cal: Calendar { Calendar.current }
    private var accent: Color { timer.settings.theme.accent }
    private var weekStart: Date { timer.settings.weekStart(offset: weekOffset, calendar: cal) }
    private var days: [Date] {
        (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            // The popover widens to fit all 8 columns (see MenuBarView); the
            // scroll is a safety net for small screens where it can't.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Self.columnSpacing) {
                    backlogColumn
                    ForEach(days, id: \.self) { day in
                        dayColumn(day)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(DS.Motion.standard) { weekOffset -= 1 }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressableSubtle)
            .help("Previous week")

            Text(weekRangeLabel)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .frame(maxWidth: .infinity)

            Button {
                withAnimation(DS.Motion.standard) { weekOffset += 1 }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressableSubtle)
            .help("Next week")

            if weekOffset != 0 {
                Button {
                    withAnimation(DS.Motion.standard) { weekOffset = 0 }
                } label: {
                    Text("This week")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(accent.opacity(0.18)))
                        .foregroundStyle(accent)
                }
                .buttonStyle(.pressableSubtle)
            }
        }
        .padding(.horizontal, 4)
    }

    private var weekRangeLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d"
        let end = cal.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "\(f.string(from: weekStart)) – \(f.string(from: end))"
    }

    // MARK: - Columns

    private var backlogColumn: some View {
        let items = store.unscheduledTasks
        return columnContainer(
            id: "unscheduled", isToday: false,
            header: AnyView(backlogHeader(count: items.count)),
            items: items,
            onDrop: { store.setPlannedDate($0, nil) })
    }

    private func dayColumn(_ day: Date) -> some View {
        let items = store.tasksPlanned(on: day)
        let isToday = cal.isDateInToday(day)
        return columnContainer(
            id: dayKey(day), isToday: isToday,
            header: AnyView(dayHeader(day, isToday: isToday, count: items.count)),
            items: items,
            onDrop: { store.setPlannedDate($0, day) })
    }

    private func backlogHeader(count: Int) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "tray.full")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.dsSecondary)
                Text("Unscheduled")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                countBadge(count, tint: Color.dsSecondary)
            }
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(accent)
                TextField("Add task", text: $backlogDraft)
                    .textFieldStyle(.plain)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white)
                    .onSubmit(addBacklog)
            }
            .padding(.horizontal, 6).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(Color.dsFill))
        }
    }

    private func addBacklog() {
        let t = backlogDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        withAnimation(DS.Motion.standard) { store.add(title: t) }
        backlogDraft = ""
    }

    private func dayHeader(_ day: Date, isToday: Bool, count: Int) -> some View {
        HStack(spacing: 7) {
            Text("\(cal.component(.day, from: day))")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(isToday ? .white : .white.opacity(0.9))
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(isToday ? AnyShapeStyle(accent)
                                          : AnyShapeStyle(Color.white.opacity(0.06)))
                )
                .shadow(color: isToday ? accent.opacity(0.6) : .clear, radius: 5, y: 2)
            VStack(alignment: .leading, spacing: 0) {
                Text(dayName(day).uppercased())
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(isToday ? accent : .white.opacity(0.75))
                Text(isToday ? "Today" : monthName(day))
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer(minLength: 0)
            countBadge(count, tint: isToday ? accent : .white.opacity(0.45))
        }
    }

    private func countBadge(_ n: Int, tint: Color) -> some View {
        Text("\(n)")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(n == 0 ? .white.opacity(0.3) : tint)
            .frame(minWidth: 16, minHeight: 16)
            .background(Circle().fill(Color.white.opacity(n == 0 ? 0.03 : 0.08)))
    }

    private func columnContainer(id: String, isToday: Bool,
                                 header: AnyView, items: [TaskItem],
                                 onDrop: @escaping (UUID) -> Void) -> some View {
        let targeted = targetedColumn == id
        return VStack(alignment: .leading, spacing: 8) {
            header
            if items.isEmpty {
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(targeted ? accent.opacity(0.7) : Color.white.opacity(0.12))
                    .frame(height: 44)
                    .overlay(
                        Text(targeted ? "Drop here" : "—")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.white.opacity(targeted ? 0.8 : 0.25))
                    )
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(items) { task in
                            card(task)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.88).combined(with: .opacity),
                                    removal: .scale(scale: 0.9).combined(with: .opacity)))
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: Self.columnWidth, alignment: .top)
        .frame(height: columnHeight, alignment: .top)
        .background(columnBackground(isToday: isToday, targeted: targeted))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(targeted ? accent.opacity(0.8)
                        : (isToday ? accent.opacity(0.4) : Color.white.opacity(0.08)),
                        lineWidth: targeted ? 2 : 1)
        )
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

    private func columnBackground(isToday: Bool, targeted: Bool) -> some View {
        RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(LinearGradient(
                        colors: targeted ? [accent.opacity(0.22), accent.opacity(0.05)]
                            : isToday ? [accent.opacity(0.16), accent.opacity(0.02)]
                            : [Color.white.opacity(0.05), .clear],
                        startPoint: .top, endPoint: .bottom))
            )
    }

    // MARK: - Cards

    private func card(_ task: TaskItem) -> some View {
        // Resolve through the store, like WeeklyBoardView — the static preset
        // table renders custom categories and user recolors as gray.
        let color = Color(hex: store.color(for: task.category))
        return VStack(alignment: .leading, spacing: 4) {
            Text(task.title)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if timer.settings.showPomodoroBadges,
               task.pomodorosDone > 0 || task.displayEstimate != nil {
                Text(task.displayEstimate.map { "🍅\(task.pomodorosDone)/\($0)" }
                     ?? "🍅\(task.pomodorosDone)")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.leading, 9).padding(.trailing, 7).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.09),
                                              Color.white.opacity(0.04)],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 3)
                .padding(.vertical, 5)
        }
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
        .draggable(task.id.uuidString) {
            Text(task.title)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: DS.Radius.sm).fill(Color.black.opacity(0.7)))
        }
        .contextMenu {
            Button("Start focus") { startFocus(on: task) }
            Button(task.isDone ? "Mark not done" : "Mark done") { store.toggleDone(task.id) }
            Divider()
            ForEach(days, id: \.self) { d in
                Button {
                    store.setPlannedDate(task.id, d)
                } label: {
                    if let planned = task.plannedDate, cal.isDate(planned, inSameDayAs: d) {
                        Label(fullDayLabel(d), systemImage: "checkmark")
                    } else {
                        Text(fullDayLabel(d))
                    }
                }
            }
            Divider()
            Button("Unschedule") { store.setPlannedDate(task.id, nil) }
        }
    }

    // MARK: - Helpers

    private func dayKey(_ day: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: day)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    private func dayName(_ day: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEE"
        return f.string(from: day)
    }

    private func monthName(_ day: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM"
        return f.string(from: day)
    }

    private func fullDayLabel(_ day: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEEE, MMM d"
        let name = f.string(from: day)
        return cal.isDateInToday(day) ? "\(name) (today)" : name
    }

    private func startFocus(on task: TaskItem) {
        if store.activeTaskID == task.id, timer.isRunning {
            timer.toggle()
            return
        }
        store.setActive(task.id)
        timer.startFocusSession()
    }
}
