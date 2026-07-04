import SwiftUI
import AppKit
import BlinkCore

struct MenuBarView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var tasks = TaskStore.shared
    @Environment(\.openWindow) private var openWindow
    @State private var tab: Tab = .timer

    private enum Tab: Hashable { case timer, tasks, stats }

    var body: some View {
        VStack(spacing: 14) {
            Picker("", selection: $tab) {
                Image(systemName: "timer").tag(Tab.timer)
                Image(systemName: "checklist").tag(Tab.tasks)
                Image(systemName: "chart.bar.fill").tag(Tab.stats)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch tab {
                case .timer: timerTab
                case .tasks: TasksView(timer: timer)
                case .stats: statsTab
                }
            }

            Divider().overlay(Color.white.opacity(0.15))
            footer
        }
        .padding(18)
        .frame(width: 360)
    }

    // MARK: - Tabs

    private var timerTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            StreakRewardBanner(center: StreakRewardCenter.shared)
            statusHeader
            if let active = tasks.activeTask {
                activeTaskChip(active)
            } else {
                chooseTaskButton
            }
            controls
            Divider().overlay(Color.white.opacity(0.15))
            statsStrip
        }
    }

    private var statsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                StreakBadgeView(streak: timer.stats.streak)
                StatsChartView(stats: timer.stats)
            }
            .padding(.vertical, 2)
        }
        .frame(height: 360)
    }

    // MARK: - Pieces

    private func activeTaskChip(_ task: TaskItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "target")
                .foregroundStyle(.tint)
            Text(task.title)
                .font(.system(.callout, design: .rounded).weight(.medium))
                .lineLimit(1)
            Spacer()
            Text("🍅 \(task.pomodorosDone)")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
            Button {
                tasks.setActive(nil)
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .glassCapsule(material: .thin)
    }

    private var statusHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.white.opacity(0.1))
                Image(systemName: timer.phase.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(timer.phase.glow)
            }
            .frame(width: 46, height: 46)
            .glassCapsule()

            VStack(alignment: .leading, spacing: 2) {
                Text(timer.phase.label)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                Text(timer.settings.timeFormat.string(timer.remainingSeconds))
                    .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    /// Prompt shown on the timer tab when no task is active: jumps to the
    /// Tasks tab so the user picks one before starting a focus session.
    private var chooseTaskButton: some View {
        Button {
            tab = .tasks
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.tint)
                Text("Choose a task")
                    .font(.system(.callout, design: .rounded).weight(.medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .glassCapsule(material: .thin)
        }
        .buttonStyle(.plain)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            GlassButton(label: timer.isRunning ? "Pause" : "Start",
                        systemImage: timer.isRunning ? "pause.fill" : "play.fill",
                        action: startTapped)
            HStack(spacing: 8) {
                GlassButton(label: "Skip",
                            systemImage: "forward.end.fill",
                            action: { timer.skip() })
                GlassButton(label: "Reset",
                            systemImage: "arrow.counterclockwise",
                            tint: .red.opacity(0.95),
                            action: { timer.stop() })
            }
            HStack(spacing: 8) {
                GlassButton(label: "+5m",
                            systemImage: "plus",
                            tint: .green.opacity(0.95),
                            action: { timer.addTime(300) })
                GlassButton(label: "-5m",
                            systemImage: "minus",
                            tint: .orange.opacity(0.95),
                            action: { timer.removeTime(300) })
            }
        }
    }

    /// Start requires a task: if none is active, switch to the Tasks tab so the
    /// user selects one first; otherwise just toggle the running timer.
    private func startTapped() {
        if timer.isRunning || tasks.activeTask != nil {
            timer.toggle()
        } else {
            tab = .tasks
        }
    }

    private var statsStrip: some View {
        HStack(spacing: 14) {
            stat(value: "\(timer.stats.completedToday)", label: "Today")
            stat(value: "\(timer.cyclesCompletedInRound)/\(timer.settings.longBreakEvery)",
                 label: "Cycle")
            if timer.settings.repeatConfig.enabled {
                stat(value: "\(timer.repeatIndex + 1)/\(timer.settings.repeatConfig.count)",
                     label: "Repeat")
            }
            stat(value: "\(timer.stats.streak.currentStreak)", label: "Streak")
        }
        .frame(maxWidth: .infinity)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
            Text(label).font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            } label: {
                Label("Open window", systemImage: "macwindow")
                    .font(.system(.callout, design: .rounded).weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button { openAppSettings() } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressableSubtle)
            .foregroundStyle(.secondary)
            .help("Settings")

            Spacer()

            Button { NSApp.terminate(nil) } label: {
                Label("Quit", systemImage: "power")
                    .font(.system(.callout, design: .rounded).weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    /// Opens the SwiftUI `Settings` scene. An `.accessory` app has no menu bar,
    /// so ⌘, is unreachable — drive it programmatically on macOS 13 & 14+.
    /// Opens the main window on its Settings section. This is far more reliable
    /// than the `showSettingsWindow:` selector, which silently no-ops for an
    /// `.accessory` menu-bar app on recent macOS.
    private func openAppSettings() {
        AppRouter.shared.section = .settings
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }
}
