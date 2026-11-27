import SwiftUI
import SharinganCore

/// The "Habit" section of the task editor: toggle, schedule and completion mode.
struct HabitEditorSection: View {
    @Binding var habit: TaskHabit?
    var accent: Color

    private let calendar = Calendar.current
    /// Last pomodoro target, so toggling Pomodoro off and on keeps it.
    @State private var lastTarget = 1

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
                // Empty label: GlassSwitchStyle draws `configuration.label` itself
                // and ignores `.labelsHidden()`, which doubled the text.
                Toggle(isOn: Binding(
                    get: { habit != nil },
                    set: { on in
                        habit = on ? (habit ?? TaskHabit(schedule: .daily, mode: .manual,
                                                        startDay: calendar.startOfDay(for: Date()))) : nil
                    })) { EmptyView() }
                .toggleStyle(.glassSwitch(tint: accent))
                .accessibilityLabel("Track as a habit")
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
                            .background(Capsule().fill(on ? accent.opacity(0.85) : .white.opacity(0.04)))
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

    /// Two independent chips; at least one stays on. Only Pomodoro -> `.pomodoro`,
    /// only Manual -> `.manual`, both -> `.both`. The target survives toggling Manual.
    @ViewBuilder private func modeControls(_ h: TaskHabit) -> some View {
        let target = h.mode.pomodoroTarget
        let pomoOn = target != nil
        let manualOn = h.mode.allowsManualCheck
        HStack(spacing: 8) {
            modeChip("Pomodoro", on: pomoOn) {
                guard !(pomoOn && !manualOn) else { return }   // last active chip stays on
                if let t = target { lastTarget = t }
                habit?.mode = pomoOn ? .manual : (manualOn ? .both(target: lastTarget) : .pomodoro(target: lastTarget))
            }
            modeChip("Manual check", on: manualOn) {
                guard !(manualOn && !pomoOn) else { return }
                if manualOn, let t = target { lastTarget = t; habit?.mode = .pomodoro(target: t) }
                else if let t = target { habit?.mode = .both(target: t) }
            }
        }

        if let t = target {
            Stepper(value: Binding(get: { t }, set: { n in
                lastTarget = n
                habit?.mode = manualOn ? .both(target: n) : .pomodoro(target: n)
            }), in: 1...12) {
                Text("Pomodoro target: \(t) a day")
                    .font(.system(.callout, design: .rounded)).foregroundStyle(.white)
            }
        }
        Text(modeCaption(pomo: pomoOn, manual: manualOn))
            .font(.system(.caption, design: .rounded)).foregroundStyle(Color.dsTertiary)
    }

    private func modeCaption(pomo: Bool, manual: Bool) -> String {
        switch (pomo, manual) {
        case (true, true): return "Done when the pomodoro target is reached or you check it"
        case (true, false): return "Done when the pomodoro target is reached"
        default: return "You tick each day yourself."
        }
    }

    private func modeChip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(on ? .white : Color.dsSecondary)
                .padding(.horizontal, 14).frame(height: 28)
                .background(Capsule().fill(on ? accent.opacity(0.85) : .white.opacity(0.04)))
                .glassCapsule(strokeOpacity: on ? 0.35 : 0.15)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
