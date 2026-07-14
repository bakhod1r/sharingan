import SwiftUI
import SharinganCore

/// The always-on-desktop "today" glass card (the WidgetKit substitute):
/// current phase + remaining time up top, today's open tasks below.
/// Deliberately dumb — every action routes straight into the tested core
/// (PomodoroTimer / TaskStore / FocusQueue); the view only renders state.
struct TodayPanelView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var tasks = TaskStore.shared
    @ObservedObject private var queue = AppServices.focusQueue
    /// Ids whose done-toggle was just clicked: the row shows a strikethrough
    /// beat before `toggleDone` commits and the row leaves the Today set.
    @State private var justChecked: Set<UUID> = []

    static let panelWidth: CGFloat = 280
    private static let maxRows = 8

    /// The same set the Today smart view shows (planned today OR due today
    /// OR overdue), flattened out of its category grouping.
    private var todayTasks: [TaskItem] {
        tasks.grouped(filter: .today).flatMap(\.items)
    }

    var body: some View {
        let all = todayTasks
        let shown = Array(all.prefix(Self.maxRows))
        let overflow = all.count - shown.count

        VStack(alignment: .leading, spacing: 8) {
            header
            Divider().overlay(Color.white.opacity(0.12))
            if shown.isEmpty {
                Text("Nothing planned for today")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 2) {
                    ForEach(shown) { task in row(task) }
                }
                if overflow > 0 {
                    Text("+\(overflow) more")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.leading, 6)
                }
            }
        }
        .padding(14)
        .frame(width: Self.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            LinearGradient(colors: timer.settings.theme.gradient,
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(0.22)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        }
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    // MARK: - Header (phase + time + play/pause)

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                // Same start path the Dock widget / menu bar use: respect
                // the "require a task" guard when a coordinator is installed.
                if let coord = AppServices.coordinator {
                    coord.toggleRespectingTaskGuard()
                } else {
                    timer.toggle()
                }
            } label: {
                Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .help(timer.isRunning ? "Pause" : "Start")

            VStack(alignment: .leading, spacing: 0) {
                Text(timer.phase.label.uppercased())
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.65))
                Text(timer.settings.timeFormat.string(max(0, timer.remainingSeconds)))
                    .font(.dsTimer(20))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.3), value: timer.remainingSeconds)
            }
            Spacer(minLength: 4)
            Text("Today")
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(.white.opacity(0.10)))
        }
    }

    // MARK: - Task rows

    @ViewBuilder
    private func row(_ task: TaskItem) -> some View {
        let isActive = tasks.activeTaskID == task.id
        let struck = task.isDone || justChecked.contains(task.id)

        HStack(spacing: 8) {
            Button { check(task) } label: {
                Image(systemName: struck ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(struck ? Color.green : .white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .help(struck ? "Mark as not done" : "Mark as done")

            if task.priority != .none,
               let hex = timer.settings.priorityColorHex(task.priority) {
                Circle().fill(Color(hex: hex)).frame(width: 6, height: 6)
            }

            Text(task.title)
                .font(.system(.caption, design: .rounded).weight(isActive ? .semibold : .regular))
                .strikethrough(struck, color: .white.opacity(0.5))
                .foregroundStyle(struck ? Color.white.opacity(0.45) : .white.opacity(0.9))
                .lineLimit(1)

            Spacer(minLength: 4)

            // Queue-position chip, same semantics as the task list's badge.
            if !task.isDone, let pos = queuePosition(task.id) {
                Text("\(pos)")
                    .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(minWidth: 10)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
                    .help("Position \(pos) in the focus queue")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            }
        }
    }

    /// Strike the row immediately, commit `toggleDone` a beat later so the
    /// user sees the check land before the task leaves the Today set. A second
    /// click within the grace window cancels the pending completion.
    private func check(_ task: TaskItem) {
        if task.isDone {
            tasks.toggleDone(task.id)   // re-open a done task right away
            return
        }
        if justChecked.contains(task.id) {
            justChecked.remove(task.id)  // undo before it commits
            return
        }
        justChecked.insert(task.id)
        let id = task.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard justChecked.contains(id) else { return }
            justChecked.remove(id)
            tasks.toggleDone(id)
        }
    }

    /// 1-based position among the open queued tasks, nil when unqueued —
    /// mirrors TasksView so both surfaces number the queue identically.
    private func queuePosition(_ id: UUID) -> Int? {
        let open = queue.taskIDs.filter { qid in
            tasks.tasks.contains { $0.id == qid && !$0.isDone }
        }
        return open.firstIndex(of: id).map { $0 + 1 }
    }
}
