import SwiftUI
import AppKit
import SharinganCore

struct MenuBarView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var tasks = TaskStore.shared
    @State private var tab: Tab
    /// Drives the gentle running-state pulse on the Start button.
    @State private var heartbeat = false

    /// `initialTab` lets the headless dev-preview photograph a non-default tab.
    init(timer: PomodoroTimer, initialTab: Tab = .timer) {
        self.timer = timer
        _tab = State(initialValue: initialTab)
    }

    enum Tab: Hashable, CaseIterable {
        // Pomodoro and Tasks are one tab now: the full task view with the timer
        // controls pinned below it.
        case timer, week, habits, report

        var title: String {
            switch self {
            case .timer: return "Tasks"
            case .week: return "Week"
            case .habits: return "Habits"
            case .report: return "Report"
            }
        }
        var icon: String {
            switch self {
            case .timer: return "checklist"
            case .week: return "calendar"
            case .habits: return "flame"
            case .report: return "list.bullet.rectangle"
            }
        }
    }
    @Namespace private var tabPillNS

    /// Fixed height for the switchable tab area so the popover keeps one height
    /// across tabs. Sized to fit the timer tab's controls (the stats strip is
    /// pinned separately below); a very long task list scrolls within.
    private let tabContentHeight: CGFloat = 560

    /// Outer popover padding — also part of the Week-tab width math below, so
    /// tweaking one can't silently clip the board.
    private static let outerPadding: CGFloat = 18

    /// Popover width for every tab except Week. The task rows carry a dense
    /// trailing cluster (estimate badge, chevron, hover actions, Focus button)
    /// plus the composer's filter row; 360 pt clipped both edges, so the
    /// content sets the floor here.
    private static let standardWidth: CGFloat = 420

    /// Week-tab popover width: the full 8-column board plus padding, capped to
    /// the current screen so narrow displays keep every column reachable via
    /// the board's own horizontal scroll.
    private static var weekPopoverWidth: CGFloat {
        let ideal = MenuBarWeekView.boardWidth + outerPadding * 2
        let screen = (NSScreen.main?.visibleFrame.width ?? 1440) - 40
        return min(ideal, screen)
    }

    var body: some View {
        VStack(spacing: 14) {
            // Capped so the Week tab's wider popover doesn't stretch the tab
            // bar edge-to-edge — it stays a compact, centered control like
            // the rest of the chrome, while the board below manages its own
            // full-bleed horizontal scroll.
            liquidGlassTabBar
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)

            // Fixed-height area so switching Timer ↔ Tasks never resizes the
            // popover. Content is top-aligned; an over-long list scrolls within.
            // On the Timer tab the controls are pinned BELOW the scroll — only
            // the plan (goal bar + tasks) scrolls — so Start / Skip / +5m can
            // never be pushed out of sight by a long list. (The old phase +
            // countdown header is gone: the menu bar and Floating widget already
            // show the time; tasks get the space instead.)
            VStack(spacing: 14) {
                ScrollView(.vertical, showsIndicators: false) {
                    Group {
                        switch tab {
                        case .timer:  TasksView(timer: timer)
                        case .week:   MenuBarWeekView(timer: timer)
                        case .habits: MenuBarHabitsView(timer: timer)
                        case .report: ReportView(timer: timer)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                // Overflowing content dissolves at the bottom edge instead of
                // being sliced mid-row — and the fade hints there's more to
                // scroll. No-op when the content fits.
                .mask(
                    VStack(spacing: 0) {
                        Rectangle()
                        LinearGradient(colors: [.black, .clear],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 26)
                    }
                )
                if tab == .timer {
                    // Same width envelope as the tab bar and stats strip so the
                    // controls line up with the rest of the popover chrome.
                    controls
                        .frame(maxWidth: 640)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: tabContentHeight)

            // Today / Cycle / Streak + Sync / Settings / Quit — one row, pinned
            // below the scroll so it's always fully visible on both tabs,
            // never clipped by the fixed height.
            Divider().overlay(Color.dsHairline).frame(maxWidth: 640).frame(maxWidth: .infinity)
            footer
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
        }
        .onAppear { heartbeat = true }
        .padding(Self.outerPadding)
        // The Week tab widens the popover to fit the full board (backlog +
        // 7 day columns); NSHostingController tracks preferredContentSize, so
        // the popover follows this frame automatically. Capped to the screen —
        // when it can't fit, the board's horizontal scroll takes over.
        .frame(width: tab == .week ? Self.weekPopoverWidth : Self.standardWidth)
        .animation(DS.Motion.standard, value: tab)
        // One app accent: controls follow the chosen theme, not system blue.
        .tint(timer.settings.theme.accent)
        // App-wide reading-text scale (Settings › Appearance › Text size).
        .dynamicTypeSize(timer.settings.textSize.dynamicTypeSize)
    }

    /// Liquid-glass tab bar — a translucent capsule track with a floating
    /// glass pill that glides to the selected tab, replacing the flat
    /// `.segmented` picker with the same material language as the rest of
    /// the popover's glass surfaces.
    private var liquidGlassTabBar: some View {
        let segment = RoundedRectangle(cornerRadius: 9, style: .continuous)
        let tabs = Tab.allCases
        return HStack(spacing: 2) {
            ForEach(Array(tabs.enumerated()), id: \.element) { idx, t in
                let selected = tab == t
                // Hairline separator between two *unselected* neighbours — the
                // macOS segmented look in the reference. It vanishes next to the
                // accent pill so the pill never butts against a line.
                if idx > 0 {
                    let prevSelected = tab == tabs[idx - 1]
                    Rectangle()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: 1, height: 16)
                        .opacity(selected || prevSelected ? 0 : 1)
                        .animation(DS.Motion.standard, value: tab)
                }
                Button {
                    withAnimation(DS.Motion.standard) { tab = t }
                } label: {
                    Label(t.title, systemImage: t.icon)
                        .font(.system(.callout, design: .rounded).weight(selected ? .semibold : .medium))
                        .foregroundStyle(selected ? .white : .white.opacity(0.6))
                        .labelStyle(.titleOnly)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if selected {
                                let accent = timer.settings.theme.accent
                                // Flat, clean accent pill — matches the reference:
                                // no glossy white sheen, no coloured glow. A barely
                                // there top-to-bottom gradient keeps it from reading
                                // dull, a hairline border defines the edge, and a
                                // soft neutral drop shadow gives just enough lift.
                                segment
                                    .fill(LinearGradient(colors: [accent, accent.opacity(0.92)],
                                                          startPoint: .top, endPoint: .bottom))
                                    .overlay(segment.stroke(Color.white.opacity(0.12), lineWidth: 1))
                                    .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
                                    .matchedGeometryEffect(id: "tabPill", in: tabPillNS)
                            }
                        }
                        .contentShape(segment)
                }
                .buttonStyle(.pressableSubtle)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1))
        )
    }

    // MARK: - Tabs
    // MARK: - Inline task list

    /// All open tasks, active-on-top then manual order, IGNORING the search /
    /// Today filters — used by Start so a filter that hides every row doesn't
    /// disable a perfectly startable timer or change which task Start launches.
    private var allOpenTasks: [TaskItem] {
        tasks.tasks.filter { !$0.isDone && $0.trashedAt == nil }.sorted { a, b in
            if (tasks.activeTaskID == a.id) != (tasks.activeTaskID == b.id) {
                return tasks.activeTaskID == a.id
            }
            return TaskStore.inListOrder(a, b)
        }
    }

    private func startFocus(on task: TaskItem) {
        if tasks.activeTaskID == task.id, timer.isRunning {
            timer.toggle()
            return
        }
        tasks.selectFocusTarget(task.id)
        timer.startFocusSession(kind: tasks.resolvedActiveKind)
    }

    // MARK: - Pieces

    /// One row, every control the same 36×36 circle so the whole strip reads as
    /// one family: Small · Normal · Big (pomodoro size) — a divider — Skip ·
    /// Start · Reset · −5m · +5m · Auto. Labels live in tooltips; the row would
    /// never fit the popover's fixed width if every button also carried text.
    private var controls: some View {
        let accent = timer.settings.theme.accent
        return HStack(spacing: 6) {
            ForEach(PomodoroKind.allCases) { kind in
                let selected = timer.settings.activeKind == kind
                let cfg = timer.settings.config(for: kind)
                circleButton(kind.systemImage, selected: selected, accent: accent,
                            help: "\(kind.label): \(cfg.focusMinutes) min focus, \(cfg.breakMinutes) min break") {
                    timer.applyKind(kind)
                }
            }
            Divider().frame(height: 22)
            circleButton("forward.end.fill", accent: accent, help: "Skip") { timer.skip() }
            startPauseCircle
            circleButton("arrow.counterclockwise", tint: .red.opacity(0.9), accent: accent,
                        help: "Reset") { timer.stop() }
            circleButton("minus", tint: .orange.opacity(0.9), accent: accent,
                        help: "-5 minutes") { timer.removeTime(300) }
            circleButton("plus", tint: .green.opacity(0.9), accent: accent,
                        help: "+5 minutes") { timer.addTime(300) }
            circleButton("infinity", selected: timer.settings.autoCycle,
                        tint: timer.settings.autoCycle ? .green : .primary.opacity(0.85),
                        accent: .green,
                        help: "Auto mode: focus → break → focus runs continuously, no manual Start") {
                timer.settings.autoCycle.toggle()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var startPauseCircle: some View {
        circleButton(timer.isRunning ? "pause.fill" : "play.fill",
                    prominent: true, accent: timer.settings.theme.accent,
                    help: startBlocked ? "Add or pick a task to start a focus session"
                                       : (timer.isRunning ? "Pause" : "Start"),
                    action: startTapped)
            // No breathing pulse: a repeatForever animation kept the retained popover host re-laying out every frame (~20% CPU).
            // When a task is required but none exists, Start would silently do
            // nothing — dim + disable it so the dead tap is visible.
            .opacity(startBlocked ? 0.45 : 1)
            .disabled(startBlocked)
    }

    /// One uniform 36×36 circle used for every control in `controls` — same
    /// shape and size whether it's a pomodoro-size pick, Start, or a nudge, so
    /// the strip reads as one consistent family instead of mismatched pills.
    private func circleButton(_ systemImage: String, selected: Bool = false,
                              prominent: Bool = false, tint: Color = .primary,
                              accent: Color, help: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .contentTransition(.opacity)
                .foregroundStyle(prominent ? Color.white
                                  : (selected ? accent : tint.opacity(0.85)))
                .frame(width: 36, height: 36)
                .background(circleBackground(selected: selected, prominent: prominent, accent: accent))
                .overlay(
                    Circle().stroke(
                        prominent ? Color.white.opacity(0.25)
                        : (selected ? accent.opacity(0.6) : Color.clear),
                        lineWidth: 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.pressableSubtle)
        .help(help)
    }

    @ViewBuilder
    private func circleBackground(selected: Bool, prominent: Bool, accent: Color) -> some View {
        if prominent {
            Circle().fill(LinearGradient(colors: [accent, accent.opacity(0.82)],
                                         startPoint: .top, endPoint: .bottom))
                .shadow(color: accent.opacity(0.5), radius: 6, y: 2)
        } else if selected {
            Circle().fill(accent.opacity(0.24))
        } else {
            Circle().fill(Color.white.opacity(0.06))
        }
    }

    /// True when Start can do nothing: the "require a task" rule is on, no task
    /// is active, and there are no open tasks to fall back to.
    private var startBlocked: Bool {
        !timer.isRunning && tasks.activeTask == nil
            && allOpenTasks.isEmpty && timer.settings.requireTaskForFocus
    }

    /// Start requires a task: toggle the running timer if one is active,
    /// otherwise kick off a focus session on the top task in the inline list.
    private func startTapped() {
        if timer.isRunning || tasks.activeTask != nil {
            timer.toggle()
        } else if let first = allOpenTasks.first {
            startFocus(on: first)
        } else if !timer.settings.requireTaskForFocus {
            timer.toggle()
        }
        // Otherwise: no task + rule on → nothing runs.
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
            Text(label).font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    /// Today / Cycle / Streak stats and the Sync / Settings / Quit actions,
    /// combined into a single row so the footer no longer takes two.
    private var footer: some View {
        HStack(spacing: 14) {
            stat(value: "\(timer.combinedStats.completedTodayCount())", label: "Today")
            stat(value: "\(timer.cyclesCompletedInRound)/\(timer.settings.longBreakEvery)",
                 label: "Cycle")
            if timer.settings.repeatConfig.enabled {
                stat(value: "\(timer.repeatIndex + 1)/\(timer.settings.repeatConfig.count)",
                     label: "Repeat")
            }
            stat(value: "\(timer.combinedStats.streak.currentStreak)", label: "Streak")

            Spacer(minLength: 12)

            if let engine = AppServices.syncEngine {
                SyncFooterButton(engine: engine)
            }

            Button { openAppSettings() } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressableSubtle)
            .foregroundStyle(.secondary)
            .help("Settings")

            Button { NSApp.terminate(nil) } label: {
                Label("Quit", systemImage: "power")
                    .font(.system(.callout, design: .rounded).weight(.medium))
            }
            .buttonStyle(.pressableSubtle)
            .foregroundStyle(.secondary)
        }
    }

    /// Opens the SwiftUI `Settings` scene. An `.accessory` app has no menu bar,
    /// so ⌘, is unreachable — drive it programmatically on macOS 13 & 14+.
    /// Opens the main window on its Settings section. This is far more reliable
    /// than the `showSettingsWindow:` selector, which silently no-ops for an
    /// `.accessory` menu-bar app on recent macOS.
    private func openAppSettings() {
        AppRouter.shared.openSettings()
        MainWindowManager.shared.show()
    }
}

/// Footer "Sync" button — triggers `CloudSyncEngine.syncNow()` and spins its
/// icon while a round trip is in flight. Disabled unless the user has turned
/// iCloud sync on and no sync is already running.
private struct SyncFooterButton: View {
    @ObservedObject var engine: CloudSyncEngine
    @AppStorage(CloudSyncEngine.syncEnabledKey) private var syncEnabled = false

    var body: some View {
        Button { engine.syncNow() } label: {
            Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(.callout, design: .rounded).weight(.medium))
                .rotationEffect(.degrees(engine.status.isActive ? 360 : 0))
                .animation(
                    engine.status.isActive
                        ? .linear(duration: 1).repeatForever(autoreverses: false)
                        : .default,
                    value: engine.status.isActive)
        }
        .buttonStyle(.pressableSubtle)
        .foregroundStyle(.secondary)
        .disabled(!canSyncNow)
        .opacity(canSyncNow ? 1 : 0.4)
        .help(syncEnabled ? "Sync Now" : "Turn on iCloud sync in Settings first")
    }

    private var canSyncNow: Bool {
        if case .idle = engine.status { return syncEnabled }
        return false
    }
}
