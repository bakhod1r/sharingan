import SwiftUI
import SharinganCore

/// The "Habit" section of the task editor: toggle, schedule and completion mode.
struct HabitEditorSection: View {
    @Binding var habit: TaskHabit?
    var accent: Color

    private let calendar = Calendar.current

    private enum Kind: String, CaseIterable, Identifiable {
        case daily = "Every day", days = "Specific days", perWeek = "Times per week"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Habit").dsSectionLabel()
            HStack {
                Text("Track as a habit").font(.system(.callout, design: .rounded)).foregroundStyle(.white)
                Spacer(minLength: 8)
                Toggle("Track as a habit", isOn: Binding(
                    get: { habit != nil },
                    set: { on in
                        habit = on ? (habit ?? TaskHabit(schedule: .daily, mode: .manual,
                                                        startDay: calendar.startOfDay(for: Date()))) : nil
                    }))
                .toggleStyle(.glassSwitch(tint: .habitRed))
                .labelsHidden()
            }

            if let h = habit {
                scheduleControls(h)
                modeControls(h)
            }
        }
    }

    private func kind(_ s: HabitSchedule) -> Kind {
        switch s {
        case .daily: return .daily
        case .weekdays: return .days
        case .timesPerWeek: return .perWeek
        }
    }

    @ViewBuilder private func scheduleControls(_ h: TaskHabit) -> some View {
        GlassSegmentedPicker(selection: Binding(
            get: { kind(h.schedule) },
            set: { k in
                guard k != kind(h.schedule) else { return }
                switch k {
                case .daily: habit?.schedule = .daily
                case .days: habit?.schedule = .weekdays([2, 3, 4, 5, 6])
                case .perWeek: habit?.schedule = .timesPerWeek(3)
                }
            }), cases: Kind.allCases, label: \.rawValue)

        switch h.schedule {
        case .daily: EmptyView()
        case .weekdays(let set):
            HStack(spacing: 6) {
                ForEach(HabitFormat.weekdayOrder(calendar: calendar), id: \.self) { wd in
                    let on = set.contains(wd)
                    Button {
                        var s = set
                        if on { if s.count > 1 { s.remove(wd) } } else { s.insert(wd) }
                        habit?.schedule = .weekdays(s)
                    } label: {
                        Text(String(HabitFormat.weekdayShort(wd, calendar: calendar).prefix(2)))
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(on ? .white : Color.dsSecondary)
                            .frame(width: 32, height: 28)
                            .background(Capsule().fill(on ? Color.habitRed.opacity(0.85) : .white.opacity(0.04)))
                            .glassCapsule(strokeOpacity: on ? 0.35 : 0.15)
                    }
                    .buttonStyle(.plain)
                }
            }
        case .timesPerWeek(let n):
            Stepper(value: Binding(get: { n }, set: { habit?.schedule = .timesPerWeek($0) }), in: 1...7) {
                Text("\(n) time\(n == 1 ? "" : "s") per week")
                    .font(.system(.callout, design: .rounded)).foregroundStyle(.white)
            }
        }
    }

    @ViewBuilder private func modeControls(_ h: TaskHabit) -> some View {
        let isPomo: Bool = { if case .pomodoro = h.mode { return true } else { return false } }()
        GlassSegmentedPicker(selection: Binding(
            get: { isPomo },
            set: { pomo in
                guard pomo != isPomo else { return }
                habit?.mode = pomo ? .pomodoro(target: 1) : .manual
            }), options: [(true, "Pomodoro"), (false, "Manual check")])

        if case .pomodoro(let t) = h.mode {
            Stepper(value: Binding(get: { t }, set: { habit?.mode = .pomodoro(target: $0) }), in: 1...12) {
                Text("Done at \(t) pomodoro\(t == 1 ? "" : "s") a day")
                    .font(.system(.callout, design: .rounded)).foregroundStyle(.white)
            }
        } else {
            Text("You tick each day yourself.")
                .font(.system(.caption, design: .rounded)).foregroundStyle(Color.dsTertiary)
        }
    }
}
