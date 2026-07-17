import SwiftUI
import SharinganCore

/// The Floating widget pill: a "now playing"-style strip that docks flush
/// against the Dock by default (and can be dragged anywhere — see
/// `FloatingWidgetWindowManager`). Progress ring + active task + remaining time on
/// the left, three always-standing transport buttons on the right —
/// ▶︎ start opens a mini picker of today's open tasks when there's an actual
/// choice to make (resuming a paused session, or starting with today empty,
/// skips straight past it — see `handleStart`/`FloatingWidgetStartAction`),
/// ⏸ stop (pause), ⟲ reset (the engine's stop(): fresh focus, counters
/// zeroed). Buttons disable rather than hide so the pill never changes shape
/// under the pointer.
struct FloatingWidgetView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var tasks = TaskStore.shared
    /// Which container edge the pill hugs — the Dock-nearest edge, supplied
    /// by `FloatingWidgetWindowManager` (`FloatingWidgetGeometry.expandAnchor`), not
    /// the raw Position setting: on a vertical Dock the pill must expand
    /// away from the Dock regardless of what Position says, since Position
    /// is a horizontal-Dock concept.
    var anchor: FloatingWidgetAlignment = .trailing
    /// True while the pointer sits over the pill — drives the compact ↔
    /// expanded spring when `dockWidgetExpandOnHover` is on.
    @State private var hovering = false
    /// Drives the ▶︎ button's `.popover` — the mini today-task picker.
    @State private var showTaskPicker = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var phaseColors: [Color] { timer.phase.gradient }
    /// The same set the Today panel shows (planned today OR due today OR
    /// overdue, always open), reused verbatim so "today" never drifts
    /// between the two surfaces — see `TodayPanelView.todayTasks`.
    private var todayTasks: [TaskItem] {
        tasks.grouped(filter: .today).flatMap(\.items)
    }
    private var preset: FloatingWidgetSize { timer.settings.dockWidgetSize }
    /// Every metric below is tuned at the medium preset (56pt tall, k = 1)
    /// and scales linearly with whichever size is chosen.
    private var k: CGFloat { preset.height / 56 }
    /// Off = always fully open; on = compact (ring + time) at rest, full pill
    /// under the pointer — the Dock's now-playing widgets' behavior. An open
    /// task picker pins the pill expanded: the pointer leaves the pill on its
    /// way into the popover, and collapsing would remove the ▶︎ button the
    /// popover is anchored to — dismissing it before a task can be picked.
    private var expanded: Bool {
        !timer.settings.dockWidgetExpandOnHover || hovering || showTaskPicker
    }
    private var containerAlignment: Alignment {
        switch anchor {
        case .leading:  return .leading
        case .center:   return .center
        case .trailing: return .trailing
        }
    }

    var body: some View {
        // A full-preset-size transparent container (matching the window's
        // frame) with the pill anchored to the chosen Dock-hugging edge; the
        // pill itself — not this container — resizes on hover.
        pill
            .frame(width: preset.width, height: preset.height,
                   alignment: containerAlignment)
    }

    private var pill: some View {
        HStack(spacing: 12 * k) {
            ring
            if expanded {
                VStack(alignment: .leading, spacing: 2) {
                    titleRow
                    HStack(spacing: 6 * k) {
                        timeText
                        pomodoroDots
                    }
                }
                Spacer(minLength: 8 * k)
                controls
            } else {
                timeText
            }
        }
        .padding(.horizontal, 14 * k)
        // Only the width animates between the compact and expanded pill —
        // the height stays pinned to the preset so the pill never bobs.
        .frame(width: expanded ? preset.width : preset.height * 2.6,
               height: preset.height)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.78),
                   value: hovering)
        // The picker closing (pointer long gone) must collapse with the same
        // spring, not snap.
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.78),
                   value: showTaskPicker)
        // Right-click: a way back to the Dock after a manual drag (no-op
        // while already docked — reposition() just re-derives the same spot).
        .contextMenu {
            Button("Return to Dock") { FloatingWidgetWindowManager.shared.returnToDock() }
        }
    }

    private var timeText: some View {
        Text(timer.settings.timeFormat.string(max(0, timer.remainingSeconds)))
            .font(.dsTimer(17 * k))
            .foregroundStyle(.white)
            .lineLimit(1)
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.3), value: timer.remainingSeconds)
    }

    /// Mini progress ring stroked with the phase gradient; dimmed while idle.
    private var ring: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.15), lineWidth: 3.5 * k)
            Circle()
                .trim(from: 0, to: max(0.003, timer.progress))
                .stroke(AngularGradient(colors: phaseColors, center: .center),
                        style: StrokeStyle(lineWidth: 3.5 * k, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 30 * k, height: 30 * k)
        .opacity(timer.isRunning ? 1 : 0.55)
        .animation(.snappy(duration: 0.3), value: timer.progress)
    }

    /// Pomodoro dot row next to the time: the active task's estimate when it
    /// has one, else the user's finite Repeat ×N selection, else 3 — see
    /// `FloatingWidgetPomodoroDots` for the (unit-tested) priority logic.
    private var pomodoroDots: some View {
        let rc = timer.settings.repeatConfig
        let task = tasks.activeTask
        let dots = FloatingWidgetPomodoroDots.plan(
            taskEstimate: task?.effectiveEstimate,
            taskDone: task?.pomodorosDone ?? 0,
            repeatEnabled: rc.enabled, repeatEndless: rc.endless,
            repeatCount: rc.count,
            sessionsDone: rc.enabled && !rc.endless
                ? timer.repeatIndex : timer.cyclesCompletedInRound)
        return HStack(spacing: 3 * k) {
            ForEach(0..<dots.total, id: \.self) { i in
                Circle()
                    .fill(i < dots.filled
                          ? AnyShapeStyle(phaseColors.first ?? .white)
                          : AnyShapeStyle(.white.opacity(0.22)))
                    .frame(width: 5 * k, height: 5 * k)
            }
        }
        .help("\(dots.filled) of \(dots.total) pomodoros")
        .accessibilityLabel("\(dots.filled) of \(dots.total) pomodoros")
    }

    @ViewBuilder
    private var titleRow: some View {
        if let task = tasks.activeTask {
            HStack(spacing: 5) {
                Circle().fill(Color(hex: tasks.color(for: task.category)))
                    .frame(width: 6 * k, height: 6 * k)
                Text(tasks.activeShortLabel ?? task.title)
                    .font(.system(size: 12 * k, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .help(tasks.activeFocusTitle ?? "")   // full title on hover
            }
        } else {
            Text("No task selected")
                .font(.system(size: 12 * k, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    /// Pomodoro-size chooser as a single quiet button showing the current size
    /// icon; the menu carries all three (Small / Normal / Big) with durations.
    /// One button instead of three keeps the pill uncluttered.
    private var kindMenu: some View {
        Menu {
            ForEach(PomodoroKind.allCases) { kind in
                let cfg = timer.settings.config(for: kind)
                Button {
                    timer.applyKind(kind)
                } label: {
                    Label("\(kind.label) · \(cfg.focusMinutes)′ + \(cfg.breakMinutes)′",
                          systemImage: timer.settings.activeKind == kind ? "checkmark" : kind.systemImage)
                }
            }
        } label: {
            Image(systemName: timer.settings.activeKind.systemImage)
                .font(.system(size: 12 * k, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 26 * k, height: 26 * k)
                .background(Circle().fill(.white.opacity(0.12)))
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Pomodoro size: \(timer.settings.activeKind.label)")
    }

    private var controls: some View {
        HStack(spacing: 8 * k) {
            kindMenu
            control("play.fill", enabled: !timer.isRunning, help: "Start") {
                handleStart()
            }
            .popover(isPresented: $showTaskPicker, arrowEdge: .bottom) {
                FloatingWidgetTaskPickerView(timer: timer, todayTasks: todayTasks) {
                    showTaskPicker = false
                }
            }
            control("pause.fill", enabled: timer.isRunning, help: "Stop") {
                timer.pause()
            }
            control("arrow.counterclockwise", enabled: true, help: "Reset") {
                timer.stop()
            }
        }
    }

    /// ▶︎'s decision, per the design: a paused session always resumes in
    /// place (never re-routed through task selection), and an empty today
    /// list starts immediately rather than popping an empty picker. Only
    /// when there's an actual choice to make does the picker show — pure
    /// logic lives in `FloatingWidgetStartAction` so it's unit-tested without a
    /// live timer/store.
    private func handleStart() {
        switch FloatingWidgetStartAction.decide(isPaused: timer.phase == .paused,
                                            todayTaskCount: todayTasks.count) {
        case .startImmediately:
            timer.startFocusSession()
        case .showPicker:
            showTaskPicker = true
        }
    }

    private func control(_ symbol: String, enabled: Bool, help: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12 * k, weight: .bold))
                .foregroundStyle(.white.opacity(enabled ? 0.9 : 0.3))
                .frame(width: 26 * k, height: 26 * k)
                .background(Circle().fill(.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
    }
}
