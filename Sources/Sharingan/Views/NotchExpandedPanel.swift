import SwiftUI
import SharinganCore

/// The island opened up: the session at the top, today's tasks in the middle,
/// quick actions and a blocker/streak strip at the bottom. Deliberately dumb —
/// every button routes into a service that is already tested (PomodoroTimer /
/// TaskStore / FocusQueue / AppBlockerService), exactly as `TodayPanelView` does.
///
/// Nothing here may be a text field. The HUD's panel can never become key (it
/// must not steal focus from the frontmost app), and while AppKit still delivers
/// clicks to buttons in a non-key window, a text field would never see a
/// keystroke. Text entry goes out to Quick Add, which owns a real key window.
struct NotchExpandedPanel: View {
    @ObservedObject var model: NotchHUDModel
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var tasks = TaskStore.shared
    @ObservedObject private var queue = AppServices.focusQueue
    @ObservedObject private var blocker = AppBlockerService.shared
    /// The island's rects for the *current* state — the same ones the drawn
    /// shape and the hit-test mask are cut from. The panel sizes itself to
    /// `layout.island` rather than to a constant, so the content can never
    /// drift outside the clickable area.
    let layout: NotchLayout

    private var rows: [TaskItem] {
        NotchTaskRows.rows(today: tasks.grouped(filter: .today).flatMap(\.items),
                           queue: queue.taskIDs)
    }

    /// The camera housing sits in the cutout: the first pixel of content has to
    /// start below it. `cutout` is nil on a display with no notch — where this
    /// view is never built, since the layout collapses to `.zero` — so 0 is a
    /// formality, not a fallback.
    private var contentTop: CGFloat { (model.metrics.cutout?.height ?? 0) + 6 }

    /// The whole app formats durations through the user's `TimeDisplayFormat`
    /// (see `TodayPanelView` / `FloatingTimerView`); the island is not an
    /// exception.
    private func clock(_ seconds: TimeInterval) -> String {
        timer.settings.timeFormat.string(max(0, seconds))
    }

    var body: some View {
        VStack(spacing: 8) {
            timerRow
            Divider().overlay(Color.white.opacity(0.10))
            taskList
            Spacer(minLength: 0)
            quickActions
            statusStrip
        }
        .padding(.top, contentTop)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        // Pin to the island's own rect, like `NotchEars` does: the parent hangs
        // us off the shape with `.overlay(alignment: .top)`, and an auto-sized
        // stack would centre itself inside the island instead of filling it.
        .frame(width: layout.island.width, height: layout.island.height,
               alignment: .top)
    }

    // MARK: - Timer

    private var timerRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(clock(timer.remainingSeconds))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.3), value: timer.remainingSeconds)
                Text(timer.phase.label.uppercased())
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
            // Same start path as the menu bar and the today panel, so the
            // "require a task before focusing" guard holds here too.
            control(timer.isRunning ? "pause.fill" : "play.fill",
                    timer.isRunning ? "Pause" : "Start") {
                if let coord = AppServices.coordinator {
                    coord.toggleRespectingTaskGuard()
                } else {
                    timer.toggle()
                }
            }
            control("forward.end.fill", "Skip to the next phase") { timer.skip() }
            control("goforward.5", "Add 5 minutes") { timer.addTime(300) }
            control("arrow.counterclockwise", "Reset") { timer.stop() }
        }
    }

    private func control(_ symbol: String, _ help: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 26, height: 26)
                .background(Circle().fill(.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Tasks

    @ViewBuilder
    private var taskList: some View {
        let shown = rows
        if shown.isEmpty {
            Text("Nothing planned for today")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        } else {
            VStack(spacing: 2) {
                ForEach(shown) { task in taskRow(task) }
            }
        }
    }

    private func taskRow(_ task: TaskItem) -> some View {
        let isActive = tasks.activeTaskID == task.id

        return HStack(spacing: 8) {
            Button { tasks.toggleDone(task.id) } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(task.isDone ? Color.green : .white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .help(task.isDone ? "Mark as not done" : "Mark as done")

            Text(task.title)
                .font(.system(size: 12, design: .rounded).weight(isActive ? .semibold : .regular))
                .strikethrough(task.isDone, color: .white.opacity(0.5))
                .foregroundStyle(.white.opacity(isActive ? 1 : 0.78))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            Button {
                tasks.activeTaskID = task.id
                timer.startFocusSession(kind: task.pomodoroKind)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .buttonStyle(.plain)
            .help("Focus on “\(task.title)”")
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.09))
            }
        }
    }

    // MARK: - Actions

    private var quickActions: some View {
        HStack(spacing: 6) {
            action("plus", "Quick add a task") {
                AppServices.coordinator?.quickAddController?.showQuickAdd()
            }
            // The app has no "start a break" entry point — `skip()` from a focus
            // phase IS the break, and it is what the menu bar's Skip button and
            // the CLI's `skip` command both call.
            action("cup.and.saucer.fill", "Break now (skip to the next phase)") {
                timer.skip()
            }
            action(blocker.isActive ? "hand.raised.fill" : "hand.raised",
                   blocker.isActive ? "Stop blocking apps" : "Block distracting apps") {
                blocker.isActive ? blocker.deactivate() : blocker.activate()
            }
            // The coordinator already watches this flag and shows/hides the panel
            // itself (`settingsChanged` → `syncTodayPanel()`), so flipping it is
            // the whole action — same thing the Settings checkbox does.
            action("list.bullet", "Show or hide the Today panel") {
                timer.settings.showTodayPanel.toggle()
            }
            action("gearshape.fill", "Open Blink") { MainWindowManager.shared.show() }
        }
    }

    private func action(_ symbol: String, _ help: String,
                        _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var statusStrip: some View {
        HStack(spacing: 8) {
            if blocker.isActive {
                Label("Blocking", systemImage: "hand.raised.fill")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.orange.opacity(0.9))
            }
            Spacer(minLength: 0)
            Label("\(timer.stats.streak.currentStreak)", systemImage: "flame.fill")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .help("\(timer.stats.streak.currentStreak)-day streak")
        }
    }
}
