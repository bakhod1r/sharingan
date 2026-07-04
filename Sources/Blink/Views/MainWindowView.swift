import SwiftUI
import BlinkCore

/// Full "desktop app" window with a CleanMyMac-style sidebar. Coexists with the
/// menu bar extra — opened from the menu bar's "Open window" button.
struct MainWindowView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var tasks = TaskStore.shared
    @ObservedObject private var router = AppRouter.shared

    typealias Section = AppSection
    private var section: Section {
        get { router.section }
        nonmutating set { router.section = newValue }
    }

    // The sidebar overhangs the main content card's left edge by this much,
    // sticking "out of the window" over the transparent gutter (desktop shows
    // through) — the floating look from the CleanMyMac reference.
    private let sidebarWidth: CGFloat = 232
    private let cardLeftInset: CGFloat = 58   // main card starts this far from the window edge
    private let sidebarLeftInset: CGFloat = 18 // sidebar's own distance from the window edge

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Transparent base — the window itself is clear (see WindowConfigurator),
            // so the corners and left gutter reveal the desktop behind.
            Color.clear

            // Main content card: the gradient + detail, inset from the window
            // edges so it reads as a floating rounded panel.
            windowBackground
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 30, x: 0, y: 16)
                .padding(EdgeInsets(top: 14, leading: cardLeftInset,
                                    bottom: 14, trailing: 14))

            // Detail content lives inside the card, pushed right so it clears the
            // overhanging sidebar.
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.leading, sidebarLeftInset + sidebarWidth + 18)
                .padding(.trailing, 14)
                .padding(.vertical, 14)
                .id(section)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 8)),
                    removal: .opacity))

            // Floating sidebar, overhanging the card's left edge and sticking out
            // over the transparent gutter. It reaches to the very top so the
            // traffic-light buttons sit ON it (attached), not floating above.
            sidebar
                .frame(width: sidebarWidth)
                .padding(.leading, sidebarLeftInset)
                .padding(.top, 0)
                .padding(.bottom, 24)
        }
        .frame(minWidth: 920, minHeight: 620)
        // Extend content under the (hidden) title bar so the window buttons
        // rest on the sidebar instead of hovering in an empty top strip.
        .ignoresSafeArea()
        .background(WindowConfigurator())
        .animation(.easeInOut(duration: 0.24), value: section)
    }

    // MARK: - Sidebar (custom glass panel, CleanMyMac-style)

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            brand
            sectionHeader("Main")
            navRow(.timer)
            navRow(.tasks)
            navRow(.stats)
            sectionHeader("App")
            navRow(.settings)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
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
            Image(systemName: "eye.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.tint)
            Text("Blink")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
            Spacer()
        }
        // Leave room for the traffic-light buttons over the hidden title bar.
        .padding(.horizontal, 14).padding(.top, 30).padding(.bottom, 10)
    }

    private func sectionHeader(_ title: String) -> some View {
        // Muted, title-case group label — CleanMyMac uses soft gray captions
        // ("Cleanup", "Protection") rather than heavy all-caps.
        Text(title)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(.white.opacity(0.45))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 4)
    }

    private func navRow(_ s: Section) -> some View {
        let selected = section == s
        let openCount = tasks.tasks.filter { !$0.isDone }.count
        return Button {
            section = s
        } label: {
            HStack(spacing: 11) {
                // Plain monochrome line glyph — CleanMyMac's rows use simple
                // gray icons, brighter when the row is selected.
                Image(systemName: s.icon)
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 20, alignment: .center)
                Text(s.title)
                    .font(.system(.body, design: .rounded).weight(selected ? .semibold : .regular))
                Spacer()
                if s == .tasks, openCount > 0 {
                    Text("\(openCount)")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.white.opacity(0.2), in: Capsule())
                }
            }
            .foregroundStyle(selected ? Color.white : .white.opacity(0.62))
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.16) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableSubtle)
        .padding(.horizontal, 8)
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
        case .stats:
            detailScaffold(title: "Progress") {
                VStack(spacing: 20) {
                    StreakBadgeView(streak: timer.stats.streak)
                    StatsChartView(stats: timer.stats)
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

    /// Deep, colored gradient for the main content card (CleanMyMac-style),
    /// tinted by the current theme and darkened for text contrast.
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
    }
}

/// Makes the host `NSWindow` transparent so the content card and the
/// overhanging sidebar float over the desktop, with the window's own square
/// shadow removed (our SwiftUI cards cast their own).
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
        }
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
                        .font(.system(size: 76, weight: .light, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                    Label(timer.phase.label, systemImage: timer.phase.systemImage)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }

            // Tappable task selector — pick a task before focusing.
            Button {
                showTaskPicker = true
            } label: {
                if let active = tasks.activeTask {
                    Label(active.title, systemImage: "target")
                        .font(.system(.callout, design: .rounded).weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .glassCapsule(material: .thin)
                } else {
                    Label("Choose a task", systemImage: "plus.circle")
                        .font(.system(.callout, design: .rounded).weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .glassCapsule(material: .thin)
                }
            }
            .buttonStyle(.plain)

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
        if timer.isRunning || tasks.activeTask != nil {
            timer.toggle()
        } else {
            showTaskPicker = true
        }
    }
}
