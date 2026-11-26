import SwiftUI
import SharinganCore

/// Sidebar ▸ Habits: range + KPIs, two chart cards, today's habits with an
/// inline per-habit detail (one open at a time).
struct HabitsView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var store = TaskStore.shared
    @ObservedObject private var router = AppRouter.shared
    @State private var days = 30
    @State private var expanded: UUID?

    /// `initialExpanded` lets the headless dev-preview photograph an open row.
    init(timer: PomodoroTimer, initialExpanded: UUID? = nil) {
        self.timer = timer
        _expanded = State(initialValue: initialExpanded)
    }

    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: Date()) }

    var body: some View {
        let report = store.habitReport(days: days, today: today, calendar: calendar)
        let inputs = store.habitInputs()
        VStack(alignment: .leading, spacing: 18) {
            Text("Habits").font(.system(.largeTitle, design: .rounded).weight(.bold)).foregroundStyle(.white)
            if inputs.isEmpty {
                emptyState
            } else {
                HabitRangePicker(days: $days)
                HabitKPIRow(report: report, calendar: calendar)
                HabitChartsRow(report: report, calendar: calendar)
                todayHeader(inputs)
                VStack(spacing: DS.Space.sm) {
                    ForEach(inputs) { input in
                        HabitRowView(input: input, timer: timer, expanded: expanded == input.taskID) {
                            withAnimation(DS.Motion.standard) {
                                expanded = expanded == input.taskID ? nil : input.taskID
                            }
                        }
                    }
                }
            }
        }
    }

    private func todayHeader(_ inputs: [HabitInput]) -> some View {
        var total = 0, done = 0
        for i in inputs {
            let s = HabitEngine.status(for: today, habit: i.habit, taskID: i.taskID, focusLog: store.focusLog,
                                       checks: store.habitChecks, today: today, calendar: calendar)
            if s == .done { done += 1; total += 1 } else if s == .pending { total += 1 }
        }
        return Text("Today · \(done)/\(total) done").dsSectionLabel()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            HabitEyeView(stage: .dormant, diameter: 56)
            Text("No habits yet — turn on Habit in any task")
                .font(.system(.headline, design: .rounded)).foregroundStyle(.white)
            Button { router.openTasks() } label: {
                Text("Go to Tasks")
                    .font(.system(.callout, design: .rounded).weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).frame(height: 32)
                    .background(Capsule().fill(Color.habitRed))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 48)
    }
}

/// One habit row + its expandable detail.
struct HabitRowView: View {
    let input: HabitInput
    @ObservedObject var timer: PomodoroTimer
    var expanded: Bool
    var onToggleExpand: () -> Void
    @ObservedObject private var store = TaskStore.shared
    @State private var pulse = false

    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: Date()) }

    private func eye() -> HabitEyeStage {
        HabitEngine.eyeStage(habit: input.habit, taskID: input.taskID, focusLog: store.focusLog,
                             checks: store.habitChecks, today: today, calendar: calendar)
    }
    private func streak() -> Int {
        HabitEngine.currentStreak(habit: input.habit, taskID: input.taskID, focusLog: store.focusLog,
                                  checks: store.habitChecks, today: today, calendar: calendar)
    }

    var body: some View {
        let stage = eye()
        let current = streak()
        let progress = HabitEngine.progress(on: today, habit: input.habit, taskID: input.taskID,
                                            focusLog: store.focusLog, checks: store.habitChecks, calendar: calendar)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.md) {
                ring(stage: stage, progress: progress)
                VStack(alignment: .leading, spacing: 2) {
                    Text(input.title).font(.dsCallout).foregroundStyle(Color.dsPrimary).lineLimit(1)
                    Text("\(input.habit.schedule.label) · \(HabitFormat.modeLabel(input.habit))")
                        .font(.dsCaption).foregroundStyle(Color.dsSecondary).lineLimit(1)
                    Text(HabitFormat.stageLine(eye: stage, streak: current, habit: input.habit))
                        .font(.dsMicro).foregroundStyle(Color.habitRed).lineLimit(1)
                }
                Spacer(minLength: 8)
                weekStrip
                if case .pomodoro(let target) = input.habit.mode {
                    let n = HabitEngine.pomodoroCount(taskID: input.taskID, on: today, focusLog: store.focusLog, calendar: calendar)
                    Text("🍅 \(n)/\(target)").font(.dsMicro).foregroundStyle(Color.dsSecondary)
                    Button { startFocus() } label: {
                        Image(systemName: store.activeTaskID == input.taskID && timer.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 11, weight: .black)).foregroundStyle(.white)
                            .frame(width: 26, height: 26).background(Circle().fill(Color.habitRed))
                    }
                    .buttonStyle(.plain).help("Start a pomodoro on this task")
                }
                Text("🔥 \(current)").font(.dsCallout).foregroundStyle(Color.dsPrimary)
                    .frame(minWidth: 44, alignment: .trailing)
                    .contentTransition(.numericText())
            }
            .padding(DS.Space.md)
            .contentShape(Rectangle())
            .onTapGesture { onToggleExpand() }

            if expanded { detail.transition(.opacity.combined(with: .move(edge: .top))) }
        }
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(Color.dsFill))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .stroke(expanded ? Color.habitRed.opacity(0.5) : Color.dsHairline, lineWidth: 1))
        .onChange(of: stage) { old, new in
            guard new > old else { return }
            withAnimation(DS.Motion.celebrate) { pulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(DS.Motion.celebrate) { pulse = false }
            }
        }
    }

    // Leading eye wrapped in today's progress ring; tap to check today (any mode).
    @ViewBuilder private func ring(stage: HabitEyeStage, progress: Double) -> some View {
        let r = HabitRing(progress: progress, size: 46) {
            HabitEyeView(stage: stage, diameter: 34)
                .scaleEffect(pulse ? 1.3 : 1)
                .shadow(color: Color.habitRed.opacity(pulse ? 0.9 : 0), radius: 10)
        }
        Button { store.toggleHabitCheck(taskID: input.taskID, day: today) } label: { r }
            .buttonStyle(.plain).help(progress >= 1 ? "Uncheck today" : "Check today")
    }

    // Mon...Sun of the current week.
    private var weekStrip: some View {
        let start = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        return HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                let d = calendar.date(byAdding: .day, value: i, to: start) ?? start
                let s = HabitEngine.status(for: d, habit: input.habit, taskID: input.taskID, focusLog: store.focusLog,
                                           checks: store.habitChecks, today: today, calendar: calendar)
                let clickable = (s == .done || s == .missed || s == .pending)
                VStack(spacing: 2) {
                    Text(String(HabitFormat.weekdayShort(calendar.component(.weekday, from: d), calendar: calendar).prefix(1)))
                        .font(.system(size: 8, design: .rounded).weight(.semibold)).foregroundStyle(Color.dsTertiary)
                    Button { store.toggleHabitCheck(taskID: input.taskID, day: d) } label: {
                        HabitDayDot(look: look(s), isToday: d == today, size: 18)
                    }
                    .buttonStyle(.plain).disabled(!clickable)
                    .help(d.formatted(date: .abbreviated, time: .omitted))
                }
            }
        }
    }

    private func look(_ s: HabitDayStatus) -> HabitDayDot.Look {
        switch s {
        case .done: return .done
        case .missed: return .missed
        case .pending: return .pending
        case .notScheduled, .beforeStart: return .dim
        case .future: return .dim
        }
    }

    private func startFocus() {
        if store.activeTaskID == input.taskID, timer.isRunning { timer.toggle(); return }
        store.selectFocusTarget(input.taskID)
        timer.startFocusSession(kind: store.resolvedActiveKind)
    }

    private var detail: some View {
        let r = HabitStats.report(for: input, store: store, days: 90, today: today, calendar: calendar)
        let longest = HabitEngine.longestStreak(habit: input.habit, taskID: input.taskID, focusLog: store.focusLog,
                                                checks: store.habitChecks, today: today, calendar: calendar)
        return VStack(alignment: .leading, spacing: DS.Space.md) {
            Divider().overlay(Color.dsHairline)
            HStack(alignment: .top, spacing: DS.Space.xl) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Last 12 weeks").dsSectionLabel()
                    HabitHeatmap(input: input, focusLog: store.focusLog, checks: store.habitChecks,
                                 today: today, weeks: 12, calendar: calendar)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Streak").dsSectionLabel()
                    Text("Current \(streak()) \(HabitFormat.unit(input.habit, streak()))").font(.dsCallout).foregroundStyle(Color.dsPrimary)
                    Text("Longest \(longest) \(HabitFormat.unit(input.habit, longest))").font(.dsCaption).foregroundStyle(Color.dsSecondary)
                }
                Spacer(minLength: 0)
            }
            HabitChartsRow(report: r, calendar: calendar)
        }
        .padding([.horizontal, .bottom], DS.Space.md)
    }
}
