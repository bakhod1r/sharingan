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
///
/// The panel assembles rather than blinks. The island grows first
/// (`NotchMotion.contentLead`), then the four sections arrive in reading order,
/// one `NotchMotion.stagger` apart — timer row, tasks, quick actions, status
/// strip — each fading in, drifting up a few points and settling from 96%. The
/// last one lands ~400ms after the hover commits, inside the budget.
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
    let reduceMotion: Bool

    /// Flipped in `onAppear`; each section watches it through its own delayed
    /// animation. Child `.transition`s would not run here — SwiftUI animates the
    /// transition of the outermost inserted view only, and that is this panel.
    @State private var assembled = false

    /// What the island was configured to show. The same value `NotchGeometry`
    /// sized `layout.island` from — so a section rendered here has room here by
    /// construction, and one switched off took its height off the island rather
    /// than leaving a hole in it.
    private var config: NotchContentConfig { model.config }

    /// The rows this panel draws — and, to the row, the ones the island's height
    /// was computed from.
    ///
    /// The limit is `renderedTaskRows` (`min(cap, today's count)`), not the cap:
    /// that is the number `NotchGeometry` sized `layout.island` from, and asking
    /// the list for exactly it makes the two impossible to disagree. If the count
    /// in the config is ever a beat stale — the store publishes, the manager
    /// re-stamps it one runloop turn later — this panel under-draws for that one
    /// turn rather than drawing a row into black the island has not grown yet.
    ///
    /// The list itself comes from `NotchWindowManager.taskRows`, which is also
    /// what the manager counted. One list, one count, one height.
    /// (`tasks` and `queue` are observed above so that a change to either
    /// re-renders this panel — the queue reorders the rows without the store
    /// changing at all. The read itself goes through the manager's one list.)
    private var rows: [TaskItem] {
        NotchWindowManager.taskRows(limit: config.renderedTaskRows)
    }

    /// The island is a **T**, and the crossbar — `layout.body` — is everything
    /// below the menu bar, which is everywhere content is allowed to be. The stem
    /// above it is a cutout-wide strip of black over the camera housing: nothing
    /// is legible there and nothing is drawn there.
    ///
    /// The panel used to pad its top by the cutout's height, pushing its content
    /// clear of the housing inside a rectangle that started at the top of the
    /// screen. With a T that padding would be a *second* menu-bar row of dead
    /// black inside the body. The body already starts below the menu bar, so the
    /// content simply fills it, inset by `contentTopPadding` — the same 10pt the
    /// body's height was measured with.
    private var bodyRect: CGRect { layout.body }

    /// The whole app formats durations through the user's `TimeDisplayFormat`
    /// (see `TodayPanelView` / `FloatingTimerView`); the island is not an
    /// exception.
    private func clock(_ seconds: TimeInterval) -> String {
        timer.settings.timeFormat.string(max(0, seconds))
    }

    /// The panel's sections, in reading order — which is also the order they
    /// arrive in.
    private enum Section: Int, CaseIterable {
        case timer, tasks, quickActions, statusStrip
    }

    private func shows(_ section: Section) -> Bool {
        switch section {
        case .timer:        return config.showTimerControls
        case .tasks:        return config.showTasks
        case .quickActions: return config.showQuickActions
        case .statusStrip:  return config.showStatusStrip
        }
    }

    /// The stagger counts *visible* sections: with the task list switched off,
    /// the quick actions must not wait out an empty beat where it used to be.
    private func arrival(_ section: Section) -> Int {
        Section.allCases.prefix(section.rawValue).filter(shows).count
    }

    /// This stack is the one the height constants were measured from (a
    /// structural replica of it, at 340pt, with this exact top padding — see
    /// `NotchGeometry`). Changing the spacing, the padding or a section's content
    /// here without re-measuring is how the island starts clipping again.
    var body: some View {
        VStack(spacing: 8) {
            if shows(.timer) {
                VStack(spacing: 8) {
                    timerRow
                    Divider().overlay(Color.dsHairline)
                }
                .notchArrival(assembled, section: arrival(.timer), reduceMotion: reduceMotion)
            }

            if shows(.tasks) {
                taskList
                    .notchArrival(assembled, section: arrival(.tasks), reduceMotion: reduceMotion)
            }

            Spacer(minLength: 0)

            if shows(.quickActions) {
                quickActions
                    .notchArrival(assembled, section: arrival(.quickActions),
                                  reduceMotion: reduceMotion)
            }

            if shows(.statusStrip) {
                statusStrip
                    .notchArrival(assembled, section: arrival(.statusStrip),
                                  reduceMotion: reduceMotion)
            }
        }
        .padding(.top, NotchGeometry.contentTopPadding)
        .padding(.horizontal, 14)
        .padding(.bottom, NotchGeometry.contentBottomPadding)
        // Pin to the *body's* rect, and then hang the body off the island's top
        // edge. The parent attaches us with `.overlay(alignment: .top)` on the
        // whole silhouette, so without this the stack would centre itself over
        // the stem and the menu bar — an auto-sized stack fills nothing.
        .frame(width: bodyRect.width, height: bodyRect.height, alignment: .top)
        .padding(.top, bodyRect.minY - layout.island.minY)
        .frame(width: layout.island.width, height: layout.island.height,
               alignment: .top)
        .onAppear { assembled = true }
    }

    // MARK: - Timer

    private var timerRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(clock(timer.remainingSeconds))
                    // The app's one countdown face (`Font.dsTimer`), light and
                    // rounded, so the island's clock is the same element as the
                    // menu bar's and the floating pill's.
                    .font(.dsTimer(26))
                    .foregroundStyle(Color.dsPrimary)
                    .contentTransition(.numericText())
                    .animation(DS.Motion.snappy, value: timer.remainingSeconds)
                Text(timer.phase.label.uppercased())
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Color.dsSecondary)
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

    /// A 26pt round glass control — the app's glass surface (`.glass` material +
    /// hairline) rather than a symbol in a grey disc. The 26pt frame is the
    /// island's measured footprint and is applied before the material, so the
    /// glass dresses the control without resizing it; `.pressableSubtle` is the
    /// app's press interaction.
    private func control(_ symbol: String, _ help: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.dsSecondary)
                .frame(width: 26, height: 26)
                .glass(Circle(), material: .regular)
                .contentShape(Circle())
        }
        .buttonStyle(.pressableSubtle)
        .help(help)
    }

    // MARK: - Tasks

    @ViewBuilder
    private var taskList: some View {
        let shown = rows
        if shown.isEmpty {
            // Shown only when there is genuinely no open work at all: the list is
            // the active task, the focus queue, today's tasks, then a fallback to
            // the rest of the open tasks (see `NotchWindowManager.taskRows`), so
            // an empty result means every task is done or there are none.
            Text("No open tasks")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Color.dsTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        } else {
            VStack(spacing: 2) {
                ForEach(shown) { task in taskRow(task) }
            }
        }
    }

    /// The island's task row, carrying what the main window's row carries: the
    /// done box, the title, subtask progress, the pomodoro ring, and a play
    /// button that is a *pause* button when this is the task the timer is
    /// running. The two badges are the shared components (`TaskComponents`), so
    /// "2/2" and the ring mean here exactly what they mean in the Tasks window.
    ///
    /// No disclosure chevron: the island cannot expand subtasks inline (its
    /// height is computed before it draws), and a control that does nothing is
    /// worse than no control.
    ///
    /// **This row's height is a load-bearing number.** `NotchGeometry` sizes the
    /// island from `taskRowHeight` × the row count, so a row that is taller than
    /// the constant is a row cropped at the island's `.clipShape`, and one that
    /// is shorter is a strip of dead black.
    ///
    /// Which is why the content is *pinned* to `taskRowContentHeight` rather than
    /// left to its intrinsic size: the badges are conditional, and a row with no
    /// subtasks and no pomodoros measures 21pt against a badged row's 28pt (both
    /// measured). Left free, five bare tasks would draw 35pt short of the island
    /// the geometry reserved for them — and the list would jitter row to row as
    /// tasks earn their first tomato. Pinned, every row is the constant, and the
    /// island fits it by construction whatever today's tasks happen to carry.
    private func taskRow(_ task: TaskItem) -> some View {
        let isActive = tasks.activeTaskID == task.id
        // The task is the one the timer is counting down — the only case where
        // this button pauses rather than starts.
        let isRunning = isActive && timer.isRunning
        let accent = Color(hex: tasks.color(for: task.category))
        let subtasks = task.subtaskProgress

        return HStack(spacing: 8) {
            Button { tasks.toggleDone(task.id) } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(task.isDone ? Color.green : Color.dsTertiary)
            }
            .buttonStyle(.plain)
            .help(task.isDone ? "Mark as not done" : "Mark as done")

            // The title is the row's "open" affordance: it raises the main
            // window on the Tasks section, scrolled to and flashing this task
            // (`AppRouter.revealTask`). The done box and the play button keep
            // their jobs either side of it.
            Button {
                MainWindowManager.shared.show()
                AppRouter.shared.revealTask(task.id)
            } label: {
                Text(task.title)
                    .font(.system(size: 12, design: .rounded).weight(isActive ? .semibold : .regular))
                    .strikethrough(task.isDone, color: Color.dsTertiary)
                    .foregroundStyle(isActive ? Color.dsPrimary : Color.dsSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .buttonStyle(.plain)
            .help("Open “\(task.title)” in Blink")

            Spacer(minLength: 4)

            if subtasks.total > 0 {
                SubtaskProgressBadge(subtasks, size: 9)
            }

            // Gated on the same setting as every other pomodoro badge in the app:
            // a user who turned the tomatoes off does not want them in the notch
            // either. The ring is the tallest thing in the row, and the row is
            // pinned to it below — so switching the badges off (or a task simply
            // having none) changes what the row shows, never how tall it is.
            if timer.settings.showPomodoroBadges {
                TaskPomodoroBadge(done: task.pomodorosDone,
                                  estimate: task.effectiveEstimate,
                                  color: accent,
                                  diameter: NotchGeometry.taskRowContentHeight)
            }

            Button { focus(on: task) } label: {
                Image(systemName: isRunning ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 13))
                    // The running row's control takes the phase color — it is the
                    // task the timer is counting down, tied to the clock above it.
                    // Through the theme so Mono desaturates it (`notchPhaseAccent`)
                    // rather than dropping one saturated glyph onto a grey panel.
                    .foregroundStyle(isRunning
                        ? timer.settings.theme.notchPhaseAccent(model.phase)
                        : Color.dsSecondary)
            }
            .buttonStyle(.plain)
            .help(isRunning ? "Pause “\(task.title)”" : "Focus on “\(task.title)”")
        }
        // The row *is* `NotchGeometry.taskRowHeight` — not "about" it. See above.
        .frame(height: NotchGeometry.taskRowContentHeight)
        .padding(.vertical, NotchGeometry.taskRowPadding)
        .padding(.horizontal, 6)
        // The active row is the accent the app puts on a live row — a tinted fill
        // and a hairline of the same, the way the rest of Blink marks the row that
        // is running. It stays phase-colored: the active row means "the task the
        // clock is counting down", which is phase information. Mono is the one
        // exception (`notchPhaseAccent`) — a colored fill would break its
        // monochrome, so there the highlight is the near-white accent instead.
        .background {
            if isActive {
                let tint = timer.settings.theme.notchPhaseAccent(model.phase)
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .fill(tint.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                            .stroke(tint.opacity(0.4), lineWidth: 1))
            }
        }
    }

    /// Play/pause for one row — the same two calls the main window's row makes
    /// (`TasksView.startFocus`), with the pause routed through the coordinator so
    /// the "require a task before focusing" guard holds here as it does on the
    /// timer row above.
    ///
    /// Pausing is only ever the *running, active* task: for any other row the
    /// button starts a focus session on it, which is what a play button on that
    /// row has to mean.
    private func focus(on task: TaskItem) {
        if tasks.activeTaskID == task.id, timer.isRunning {
            if let coord = AppServices.coordinator {
                coord.toggleRespectingTaskGuard()
            } else {
                timer.toggle()
            }
            return
        }
        // `setActive` (not a raw write to `activeTaskID`) so a stale focused
        // subtask from another task is cleared, and `resolvedActiveKind` so a
        // task whose focused subtask asks for a short pomodoro gets one.
        tasks.setActive(task.id)
        timer.startFocusSession(kind: tasks.resolvedActiveKind)
    }

    // MARK: - Actions

    /// Two actions, on purpose. "Break now" would be `timer.skip()` — the Skip
    /// button one row up. The app-blocker toggle and the Today-panel toggle
    /// were here and got cut on user feedback ("these two buttons aren't
    /// needed"): blocking still *shows* in the status strip below, and both
    /// live one ⚙ away. The row keeps its measured `quickActionsHeight` — the
    /// chips just share the width two ways instead of four.
    private var quickActions: some View {
        HStack(spacing: 6) {
            action("plus", "Quick add a task") {
                AppServices.coordinator?.quickAddController?.showQuickAdd()
            }
            action("gearshape.fill", "Open Blink") { MainWindowManager.shared.show() }
        }
    }

    /// A glass quick-action chip — the app's glass surface at the island's
    /// measured 24pt height (applied before the material, so the glass does not
    /// change the row's footprint).
    private func action(_ symbol: String, _ help: String,
                        _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.dsSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .glass(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous),
                       material: .regular)
                // A whisper of the theme accent on the chip's edge — enough to tie
                // the quick actions to the theme, faint enough (0.22) that Mono's
                // near-white reads as a neutral rim and never shouts. A stroke, so
                // it dresses the chip without touching its measured footprint.
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .stroke(timer.settings.theme.accent.opacity(0.22), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
        }
        .buttonStyle(.pressableSubtle)
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
                // The streak is the app's own achievement, not a phase reading —
                // so the flame burns in the theme accent (warm amber on Cream,
                // magenta on Neon, near-white on Mono), one interactive color.
                .foregroundStyle(timer.settings.theme.accent)
                .help("\(timer.stats.streak.currentStreak)-day streak")
        }
    }
}
