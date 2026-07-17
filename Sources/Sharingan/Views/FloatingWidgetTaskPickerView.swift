import SwiftUI
import SharinganCore

/// The Floating widget's ▶︎ mini task picker — anchored off the play button as a
/// SwiftUI `.popover` (FloatingWidgetView wires it; the panel it's hosted in
/// stays non-activating, the popover itself may take key focus while open).
/// Rows are today's open tasks, the exact set `TodayPanelView` shows
/// (`TaskStore.grouped(filter: .today)`), so "today" never drifts between
/// the two surfaces. A top row starts without touching the active task.
struct FloatingWidgetTaskPickerView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var tasks = TaskStore.shared
    let todayTasks: [TaskItem]
    /// Closes the popover; called before either action fires so the pill is
    /// back to its resting state by the time the session actually starts.
    var onDismiss: () -> Void

    private static let maxRows = 8
    /// How long the pointer may stay off the popover before it auto-closes —
    /// the panel it's hosted in never becomes key, so there's no reliable
    /// "click outside to dismiss"; this hover-timeout stands in for it.
    private static let autoDismissDelay: TimeInterval = 1
    @State private var autoDismissTask: DispatchWorkItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            startWithoutTaskRow
            Divider().overlay(Color.white.opacity(0.12)).padding(.vertical, 2)
            ForEach(Array(todayTasks.prefix(Self.maxRows))) { task in
                row(task)
            }
            if todayTasks.count > Self.maxRows {
                Text("+\(todayTasks.count - Self.maxRows) more")
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.leading, 8).padding(.top, 2)
            }
        }
        .padding(8)
        .frame(width: 240)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial)
        .onHover { inside in
            autoDismissTask?.cancel()
            autoDismissTask = nil
            guard !inside else { return }
            let task = DispatchWorkItem { onDismiss() }
            autoDismissTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoDismissDelay, execute: task)
        }
        .onDisappear {
            autoDismissTask?.cancel()
            autoDismissTask = nil
        }
    }

    /// Same entry point every task-row play button uses
    /// (`TasksView`/`MenuBarView`'s `startFocus(on:)`): activate, then
    /// `startFocusSession(kind:)` with the task's resolved pomodoro size.
    private func row(_ task: TaskItem) -> some View {
        let isActive = tasks.activeTaskID == task.id
        return Button {
            onDismiss()
            tasks.selectFocusTarget(task.id)
            timer.startFocusSession(kind: tasks.resolvedActiveKind)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: tasks.color(for: task.category)))
                    .frame(width: 7, height: 7)
                Text(task.title)
                    .font(.system(.caption, design: .rounded).weight(isActive ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if timer.settings.showPomodoroBadges, task.pomodorosDone > 0 {
                    Text("🍅\(task.pomodorosDone)")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(task.title)
    }

    /// Plain `startFocusSession()` — no kind override, active task left
    /// exactly as it was, per the design's "Start without task" rule.
    private var startWithoutTaskRow: some View {
        Button {
            onDismiss()
            timer.startFocusSession()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Text("Start without task")
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Start a focus session without an active task")
    }
}
