import SwiftUI
import SharinganCore

/// Menu bar popover ▸ Habits tab: today's habits as compact rows (tick a
/// manual one, start a pomodoro on a pomodoro one), then the habits that
/// aren't due today, dimmed.
struct MenuBarHabitsView: View {
    @Environment(\.habitAccent) private var accent
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
        HStack(spacing: DS.Space.md) {
            let ring = HabitRing(progress: item.progress, size: Self.ringSize, lineWidth: 3,
                                 color: item.isDone ? .green : nil) { ringContent(item, input: input) }
            if item.allowsCheck {
                Button { toggleCheck(item) } label: { ring }
                    .buttonStyle(.pressableSubtle)
                    .help(item.isChecked ? "Uncheck today" : "Check today")
            } else {
                ring
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.dsCallout).foregroundStyle(Color.dsPrimary).lineLimit(1)
                Text(subtitle(item, input: input))
                    .font(.dsCaption).foregroundStyle(Color.dsSecondary).lineLimit(1)
            }
            .layoutPriority(0)
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                if item.pomodoroTarget != nil {
                    Button { startFocus(item) } label: {
                        Image(systemName: isActiveRunning(item) ? "pause.fill" : "play.fill")
                            .font(.system(size: 11, weight: .black)).foregroundStyle(.white)
                            .frame(width: 28, height: 28).background(Circle().fill(accent))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.pressableSubtle)
                    .help("Start a pomodoro on this habit")
                }
                if item.allowsCheck {
                    Button { toggleCheck(item) } label: { checkLabel(item) }
                        .buttonStyle(.pressableSubtle)
                        .help(item.isChecked ? "Uncheck today" : "Check today")
                }
            }
            .layoutPriority(1)
        }
        .padding(DS.Space.md)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .fill(item.isDone ? Color.green.opacity(0.14) : Color.dsFill))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(item.isDone ? Color.green.opacity(0.45) : Color.dsHairline, lineWidth: 1))
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

    private static let ringSize: CGFloat = 32

    @ViewBuilder private func ringContent(_ item: HabitTodayItem, input: HabitInput?) -> some View {
        if item.isDone {
            HabitEyeView(stage: .tomoe3, diameter: Self.ringSize - 8)
        } else {
            Color.clear
        }
    }

    private func checkLabel(_ item: HabitTodayItem) -> some View {
        // "Done" reflects the habit being done today; a pomodoro-completed
        // `.both` habit shows it too, and tapping still toggles the manual tick.
        HStack(spacing: 4) {
            if item.isDone { Image(systemName: "checkmark").font(.system(size: 9, weight: .black)) }
            Text(item.isDone ? "Done" : "Check")
        }
        .font(.dsMicro).lineLimit(1).fixedSize()
        .foregroundStyle(item.isDone ? Color.white : Color.green)
        .padding(.horizontal, 10).frame(height: 28)
        .background {
            ZStack {
                Capsule().fill(item.isDone ? Color.green : Color.green.opacity(0.18))
                if !item.isDone { Capsule().strokeBorder(Color.green.opacity(0.5), lineWidth: 1).clipShape(Capsule()) }
            }
            .compositingGroup()
        }
        .contentShape(Capsule())
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
                .foregroundStyle(accent.opacity(0.8))
            Text("No habits yet — turn on Habit in any task")
                .font(.dsCallout).foregroundStyle(Color.dsPrimary).multilineTextAlignment(.center)
            Button {
                AppRouter.shared.openTasks()
                MainWindowManager.shared.show()
            } label: {
                Text("Go to Tasks")
                    .font(.system(.callout, design: .rounded).weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).frame(height: 32)
                    .background(Capsule().fill(accent))
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

    private func toggleCheck(_ item: HabitTodayItem) {
        withAnimation(DS.Motion.standard) { store.toggleHabitCheck(taskID: item.taskID, day: today) }
    }

    private func startFocus(_ item: HabitTodayItem) {
        if isActiveRunning(item) { timer.toggle(); return }
        store.selectFocusTarget(item.taskID)
        timer.startFocusSession(kind: store.resolvedActiveKind)
    }
}
