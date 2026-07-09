import SwiftUI
import BlinkCore

/// Full "desktop app" window with a CleanMyMac-style sidebar. Coexists with the
/// menu bar extra — opened from the menu bar's "Open window" button.
struct MainWindowView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var tasks = TaskStore.shared
    @ObservedObject private var router = AppRouter.shared
    /// Sidebar row the pointer is hovering, for a subtle highlight.
    @State private var hoveredNav: AppSection?

    private var accent: Color { timer.settings.theme.accent }

    typealias Section = AppSection
    private var section: Section {
        get { router.section }
        nonmutating set { router.section = newValue }
    }

    var body: some View {
        ZStack {
            windowBackground
            HStack(spacing: 0) {
                // Normal in-window glass sidebar with margins.
                sidebar
                    .frame(width: 232)
                    .padding(.leading, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 18)
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(section)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 8)),
                        removal: .opacity))
            }
            .animation(.easeInOut(duration: 0.24), value: section)
        }
        .frame(minWidth: 920, minHeight: 620)
        // One app accent: controls (pickers, toggles, sliders, menus) follow the
        // chosen theme instead of the stock system blue.
        .tint(timer.settings.theme.accent)
    }

    // MARK: - Sidebar (custom glass panel, CleanMyMac-style)

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            brand
            sectionHeader("Main")
            navRow(.timer)
            navRow(.tasks)
            navRow(.week)
            navRow(.stats)
            sectionHeader("App")
            navRow(.settings)
            Spacer(minLength: 12)
            sidebarFooter
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    // Faint theme tint so the panel reads as colored glass —
                    // the window color glows through, CleanMyMac-style.
                    RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                        .fill(timer.settings.theme.accent.opacity(0.14))
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .stroke(
                    LinearGradient(colors: [Color.white.opacity(0.35),
                                            Color.white.opacity(0.08)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.38), radius: 28, x: 0, y: 14)
    }

    private var brand: some View {
        HStack(spacing: 10) {
            appIcon
                .resizable()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            Text("Blink")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
            Spacer()
        }
        // Leave room for the traffic-light buttons over the hidden title bar.
        .padding(.horizontal, 14).padding(.top, 30).padding(.bottom, 10)
    }

    /// The real app icon, bundled at `Sources/Blink/Resources/AppIcon.png`,
    /// falling back to an SF Symbol if it can't be loaded.
    private var appIcon: Image {
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let ns = NSImage(contentsOf: url) {
            return Image(nsImage: ns)
        }
        return Image(systemName: "eye.fill")
    }

    /// A small glass status card pinned to the bottom of the sidebar — today's
    /// focus count and the current streak, so the panel closes on a live signal
    /// instead of empty space (the way Todoist parks account/karma at the foot).
    private var sidebarFooter: some View {
        let today = timer.stats.completedTodayCount()
        let streak = timer.stats.streak.currentStreak
        return HStack(spacing: 0) {
            footerStat(icon: "target", tint: accent, value: today, label: "Today")
            Divider().frame(height: 28).overlay(Color.white.opacity(0.12))
            footerStat(icon: "flame.fill", tint: .orange, value: streak, label: "Streak")
        }
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1))
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
    }

    private func footerStat(icon: String, tint: Color, value: Int, label: String) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text("\(value)")
                    .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            Text(label)
                .font(.system(.caption2, design: .rounded).weight(.medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionHeader(_ title: String) -> some View {
        // The one canonical group-label style — same as the task-list and
        // Settings headers, instead of a hand-inlined copy at a dimmer opacity.
        Text(title)
            .dsSectionLabel()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 5)
    }

    private func navRow(_ s: Section) -> some View {
        let selected = section == s
        let hovered = hoveredNav == s
        let openCount = tasks.tasks.filter { !$0.isDone }.count
        return Button {
            section = s
        } label: {
            HStack(spacing: 11) {
                // Icon glows in the theme accent when the row is selected, so the
                // active section reads instantly (Todoist-style accent selection).
                Image(systemName: s.icon)
                    .font(.system(size: 15, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? accent
                                     : (hovered ? Color.white.opacity(0.85) : .white.opacity(0.55)))
                    .frame(width: 20, alignment: .center)
                Text(s.title)
                    .font(.system(.body, design: .rounded).weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.white : .white.opacity(0.7))
                Spacer()
                if s == .tasks, openCount > 0 {
                    Text("\(openCount)")
                        .font(.system(.caption2, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(selected ? accent : .white.opacity(0.5))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(selected ? accent.opacity(0.18)
                                                   : Color.white.opacity(0.08)))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .fill(selected ? accent.opacity(0.20)
                          : (hovered ? Color.white.opacity(0.06) : .clear))
            )
            // A slim accent bar marks the selected row, like a sidebar cursor.
            .overlay(alignment: .leading) {
                if selected {
                    Capsule().fill(accent)
                        .frame(width: 3, height: 16)
                        .padding(.leading, 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableSubtle)
        .padding(.horizontal, 8)
        .onHover { inside in
            if inside { hoveredNav = s }
            else if hoveredNav == s { hoveredNav = nil }
        }
        .animation(.easeOut(duration: 0.15), value: selected)
        .animation(.easeOut(duration: 0.15), value: hovered)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch section {
        case .timer:
            TimerDetailView(timer: timer)
        case .tasks:
            detailScaffold(title: "Tasks") {
                TasksView(timer: timer, embeddedInScroll: true)
            }
        case .week:
            // Full-width — the 7-day board manages its own horizontal layout
            // rather than the width-capped scaffold used by the other sections.
            WeeklyBoardView(timer: timer)
                .padding(.horizontal, 28)
                .padding(.top, 32)
                .padding(.bottom, 24)
        case .stats:
            detailScaffold(title: "Progress") {
                VStack(spacing: 20) {
                    StatsSummaryView(stats: timer.stats,
                                     focusMinutes: timer.settings.focusMinutes,
                                     accent: timer.settings.theme.accent)
                    StreakBadgeView(streak: timer.stats.streak)
                    StatsChartView(stats: timer.stats, accent: timer.settings.theme.accent)
                    StatsExtrasView(stats: timer.stats,
                                    accent: timer.settings.theme.accent)
                }
            }
        case .settings:
            SettingsView(timer: timer, settings: $timer.settings)
        }
    }

    /// Shared detail chrome: a section title and a centered, width-capped body
    /// so content never stretches edge-to-edge on wide windows.
    private func detailScaffold<C: View>(title: String,
                                         @ViewBuilder content: () -> C) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(title)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                content()
            }
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 40)
            .padding(.top, 40)
            .padding(.bottom, 32)
        }
    }

    /// Deep, colored gradient that fills the whole window, tinted by the theme
    /// and darkened for text contrast.
    private var windowBackground: some View {
        let colors = timer.settings.theme.gradient
        return ZStack {
            LinearGradient(colors: colors,
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            LinearGradient(colors: [Color.black.opacity(0.30), Color.black.opacity(0.62)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [(colors.first ?? .blue).opacity(0.45), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 620)
                .blendMode(.screen)
        }
        .ignoresSafeArea()
    }
}

/// Large, centered timer view for the main window.
private struct TimerDetailView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var tasks = TaskStore.shared
    @State private var showTaskPicker = false

    var body: some View {
        let remaining = max(0, timer.remainingSeconds)
        let total = timer.totalSeconds
        let progress = total > 0 ? 1 - remaining / total : 0

        VStack(spacing: 32) {
            Spacer(minLength: 12)

            ZStack {
                CountdownRing(progress: progress,
                              colors: timer.phase.gradient,
                              lineWidth: 20)
                    .frame(width: 300, height: 300)
                VStack(spacing: 8) {
                    Text(timer.settings.timeFormat.string(remaining))
                        .font(.dsTimer(76))
                        .foregroundStyle(.white)
                    Label(timer.phase.label, systemImage: timer.phase.systemImage)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }

            // Tappable task selector — pick a task before focusing. Sized to
            // read as a primary control that matches the timer's scale.
            Button {
                showTaskPicker = true
            } label: {
                let active = tasks.activeTask
                Label(active?.title ?? "Choose a task",
                      systemImage: active != nil ? "target" : "plus.circle.fill")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(active != nil ? .white : .white.opacity(0.85))
                    .lineLimit(1)
                    .padding(.horizontal, 26).padding(.vertical, 14)
                    .frame(minWidth: 240)
                    .glassCapsule(material: .regular)
            }
            .buttonStyle(.pressableSubtle)

            Spacer(minLength: 12)

            // Primary CleanMyMac-style glowing run button, flanked by
            // subtle secondary controls.
            HStack(alignment: .center, spacing: 40) {
                GlassIconButton(systemImage: "forward.end.fill", label: "Skip",
                                action: { timer.skip() })

                CircularRunButton(isRunning: timer.isRunning,
                                  colors: timer.phase.gradient,
                                  action: runTapped)

                GlassIconButton(systemImage: "arrow.counterclockwise", label: "Reset",
                                tint: .red.opacity(0.95),
                                action: { timer.stop() })
            }
        }
        .padding(EdgeInsets(top: 40, leading: 40, bottom: 50, trailing: 40))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showTaskPicker) {
            TaskPickerSheet(timer: timer)
        }
    }

    /// Big run button: if a task is already active, just toggle the timer.
    /// Otherwise, prompt the user to pick a task first.
    private func runTapped() {
        if timer.isRunning || tasks.activeTask != nil || !timer.settings.requireTaskForFocus {
            timer.toggle()
        } else {
            // No task and the rule is on — make the user pick one first.
            showTaskPicker = true
        }
    }
}
