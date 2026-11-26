import SwiftUI
import SharinganCore

/// Menu bar popover ▸ Habits tab: today's habits as compact rows (tick a
/// manual one, start a pomodoro on a pomodoro one), then the habits that
/// aren't due today, dimmed.
struct MenuBarHabitsView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var store = TaskStore.shared

    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: Date()) }

    var body: some View {
        let inputs = store.habitInputs()
        let items = store.todayHabitItems(today: today, calendar: calendar)
        let dueIDs = Set(items.map(\.taskID))
        let notToday = inputs.filter { !dueIDs.contains($0.taskID) }
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            if inputs.isEmpty {
                emptyState
            } else {
                if !items.isEmpty {
                    Text("Today · \(items.filter(\.isDone).count)/\(items.count) done").dsSectionLabel()
                    ForEach(items) { item in
                        row(item, input: inputs.first { $0.taskID == item.taskID })
                    }
                }
                if !notToday.isEmpty {
                    Text("Not today").dsSectionLabel().padding(.top, items.isEmpty ? 0 : DS.Space.sm)
                    ForEach(notToday) { input in restingRow(input) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(DS.Motion.standard, value: items)
    }

    // MARK: Rows

    private func row(_ item: HabitTodayItem, input: HabitInput?) -> some View {
        Button { tap(item) } label: {
            HStack(spacing: DS.Space.md) {
                HabitRing(progress: item.progress, size: 32, lineWidth: 3) { glyph(item) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.dsCallout).foregroundStyle(Color.dsPrimary).lineLimit(1)
                    Text(subtitle(item, input: input))
                        .font(.dsCaption).foregroundStyle(Color.dsSecondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                action(item)
            }
            .padding(DS.Space.md)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(item.isDone ? Color.habitRed.opacity(0.14) : Color.dsFill))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(item.isDone ? Color.habitRed.opacity(0.45) : Color.dsHairline, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        }
        .buttonStyle(.pressableSubtle)
        .help(item.isManual ? (item.isDone ? "Uncheck today" : "Check today")
                            : "Start a pomodoro on this habit")
    }

    private func restingRow(_ input: HabitInput) -> some View {
        HStack(spacing: DS.Space.md) {
            HabitRing(progress: 0, size: 32, lineWidth: 3) { Color.clear }
            VStack(alignment: .leading, spacing: 2) {
                Text(input.title).font(.dsCallout).foregroundStyle(Color.dsPrimary).lineLimit(1)
                Text("\(input.habit.schedule.label) · 🔥 \(streak(input))")
                    .font(.dsCaption).foregroundStyle(Color.dsSecondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.md)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(Color.dsFill))
        .opacity(0.55)
    }

    @ViewBuilder private func glyph(_ item: HabitTodayItem) -> some View {
        if item.isDone {
            Image(systemName: "checkmark").font(.system(size: 11, weight: .black))
                .foregroundStyle(Color.habitRed)
        } else if !item.isManual {
            Image(systemName: isActiveRunning(item) ? "pause.fill" : "play.fill")
                .font(.system(size: 10, weight: .black)).foregroundStyle(Color.dsPrimary)
        } else {
            Color.clear
        }
    }

    private func action(_ item: HabitTodayItem) -> some View {
        let label: String = {
            if item.isDone { return "Done" }
            if item.isManual { return "Check" }
            return isActiveRunning(item) ? "Pause" : "Focus"
        }()
        return Text(label)
            .font(.dsMicro).foregroundStyle(.white)
            .padding(.horizontal, 10).frame(height: 24)
            .background(Capsule().fill(item.isDone ? Color.habitRed : Color.dsFillStrong))
    }

    private func subtitle(_ item: HabitTodayItem, input: HabitInput?) -> String {
        var parts: [String] = []
        if let input { parts.append(input.habit.schedule.label); parts.append("🔥 \(streak(input))") }
        if let target = item.pomodoroTarget { parts.append("🍅 \(item.pomodoroCount)/\(target)") }
        return parts.joined(separator: " · ")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "flame").font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.habitRed.opacity(0.8))
            Text("No habits yet — turn on Habit in any task")
                .font(.dsCallout).foregroundStyle(Color.dsPrimary).multilineTextAlignment(.center)
            Button {
                AppRouter.shared.openTasks()
                MainWindowManager.shared.show()
            } label: {
                Text("Go to Tasks")
                    .font(.system(.callout, design: .rounded).weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).frame(height: 32)
                    .background(Capsule().fill(Color.habitRed))
            }
            .buttonStyle(.pressableSubtle)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 48)
    }

    // MARK: Logic

    private func streak(_ input: HabitInput) -> Int {
        HabitEngine.currentStreak(habit: input.habit, taskID: input.taskID, focusLog: store.focusLog,
                                  checks: store.habitChecks, today: today, calendar: calendar)
    }

    private func isActiveRunning(_ item: HabitTodayItem) -> Bool {
        store.activeTaskID == item.taskID && timer.isRunning
    }

    private func tap(_ item: HabitTodayItem) {
        if item.isManual {
            withAnimation(DS.Motion.standard) { store.toggleHabitCheck(taskID: item.taskID, day: today) }
            return
        }
        if isActiveRunning(item) { timer.toggle(); return }
        store.selectFocusTarget(item.taskID)
        timer.startFocusSession(kind: store.resolvedActiveKind)
    }
}
