import SwiftUI
import AppKit
import BlinkCore

struct MenuBarView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var tasks = TaskStore.shared
    @Environment(\.openWindow) private var openWindow
    @State private var tab: Tab = .timer
    @State private var quickTitle = ""

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
            // Task list is the primary plan here — an inline mini list to add,
            // pick, and run tasks without leaving the Timer tab. The pomodoro
            // controls sit below as a secondary layer.
            taskList
            controls
            Divider().overlay(Color.white.opacity(0.15))
            statsStrip
        }
    }

    // MARK: - Inline task list

    /// Open (unfinished) tasks, the active one floated to the top.
    private var openTasks: [TaskItem] {
        tasks.tasks
            .filter { !$0.isDone }
            .sorted { a, b in
                if (tasks.activeTaskID == a.id) != (tasks.activeTaskID == b.id) {
                    return tasks.activeTaskID == a.id
                }
                return a.createdAt < b.createdAt
            }
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Quick add
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.tint)
                TextField("Add a task…", text: $quickTitle, onCommit: quickAdd)
                    .textFieldStyle(.plain)
                    .font(.system(.callout, design: .rounded))
                    .onSubmit(quickAdd)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .glassCapsule(material: .thin)

            if openTasks.isEmpty {
                HStack {
                    Spacer()
                    Text("No tasks yet — add one above")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 10)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(openTasks) { task in miniRow(task) }
                    }
                    .padding(.vertical, 1)
                }
                .frame(maxHeight: min(CGFloat(openTasks.count) * 44, 176))
            }
        }
    }

    private func miniRow(_ task: TaskItem) -> some View {
        let isActive = tasks.activeTaskID == task.id
        let accent = Color(hex: tasks.color(for: task.category))
        return HStack(spacing: 10) {
            Button {
                tasks.toggleDone(task.id)
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Circle().fill(accent).frame(width: 7, height: 7)

            Text(task.title)
                .font(.system(.callout, design: .rounded).weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 6)

            if task.pomodorosDone > 0 {
                Text("🍅\(task.pomodorosDone)")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Button {
                startFocus(on: task)
            } label: {
                Image(systemName: isActive && timer.isRunning
                      ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help("Run a focus pomodoro on this task")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isActive ? accent.opacity(0.16) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isActive ? accent.opacity(0.5) : .clear, lineWidth: 1)
        )
        .contextMenu {
            Button(role: .destructive) { tasks.delete(task.id) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func quickAdd() {
        let trimmed = quickTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        tasks.add(title: trimmed)
        quickTitle = ""
    }

    private func startFocus(on task: TaskItem) {
        if tasks.activeTaskID == task.id, timer.isRunning {
            timer.toggle()
            return
        }
        tasks.setActive(task.id)
        if timer.phase != .focus { timer.stop() }
        timer.start()
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

    /// Start requires a task: toggle the running timer if one is active,
    /// otherwise kick off a focus session on the top task in the inline list.
    private func startTapped() {
        if timer.isRunning || tasks.activeTask != nil {
            timer.toggle()
        } else if let first = openTasks.first {
            startFocus(on: first)
        } else if !timer.settings.requireTaskForFocus {
            timer.toggle()
        }
        // Otherwise: no task + rule on → nothing runs.
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
