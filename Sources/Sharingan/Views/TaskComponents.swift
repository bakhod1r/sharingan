import SwiftUI
import SharinganCore

/// The one tag pill used across the Tasks feature — composer, row meta, and the
/// editor. Deliberately **neutral** (no accent/category tint) so tags stop
/// competing with the category bar and the priority flag for color attention;
/// color in a row now means exactly one thing per channel. Pass `onRemove` to
/// get the editable variant (with an ✕); omit it for a read-only chip.
struct TaskTag: View {
    let tag: String
    var onRemove: (() -> Void)? = nil
    /// Custom label color (from the sidebar tag editor); nil keeps the chip
    /// neutral as designed.
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 4) {
            Text("#\(tag)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(tint ?? (onRemove == nil ? Color.dsSecondary : Color.dsPrimary))
                .lineLimit(1)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.dsTertiary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressableSubtle)
                .accessibilityLabel("Remove tag \(tag)")
            }
        }
        .foregroundStyle(onRemove == nil ? Color.dsSecondary : Color.dsPrimary)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.dsFillStrong))
    }
}

/// A muted "+N" pill shown after a truncated tag list so a busy task reads as
/// "two tags and more" instead of silently dropping the rest.
struct TaskTagOverflow: View {
    let count: Int
    var body: some View {
        Text("+\(count)")
            .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(Color.dsTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.dsFill))
    }
}

/// Subtask progress — "2/2", green once every item is ticked off.
///
/// One definition for the three rows that show it: the main window's task rows,
/// the menu-bar popover's, and the notch island's expanded panel. The popover
/// used to spell it "☑2/2" in a *different* font; that copy is gone. The size
/// defaults to the 10pt semibold rounded the main window's meta row already
/// sets, so the main window renders exactly what it rendered before.
struct SubtaskProgressBadge: View {
    let done: Int
    let total: Int
    var size: CGFloat = 10

    init(_ progress: (done: Int, total: Int), size: CGFloat = 10) {
        self.done = progress.done
        self.total = progress.total
        self.size = size
    }

    var body: some View {
        Label("\(done)/\(total)", systemImage: "checklist")
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(done == total ? Color.green : Color.dsSecondary)
            .help("\(done) of \(total) subtasks done")
            .accessibilityLabel("\(done) of \(total) subtasks done")
    }
}

/// The pomodoro badge on a task row: a progress ring when the task has an
/// estimate to fill against, a plain 🍅 count when it has none, and nothing at
/// all when it has neither.
///
/// Lifted out of `TasksView.estimateRing` — with its no-estimate sibling, which
/// is half the behavior and was written next to it — so the notch island can
/// draw the *same* badge instead of a third variant of one. The estimate is
/// `task.effectiveEstimate` (the subtask sum wins over the task's own), which is
/// the caller's business; this view only draws what it is handed.
///
/// Call sites gate on `settings.showPomodoroBadges`, as they always did.
struct TaskPomodoroBadge: View {
    let done: Int
    /// `nil` = no estimate anywhere on the task, so there is no ring to fill.
    let estimate: Int?
    /// The task's category tint. Green replaces it once the estimate is met.
    var color: Color = .accentColor
    /// 26pt is the main window's row. The notch island's rows are tighter and
    /// pass a smaller one — stroke and digit scale off this, so a small badge is
    /// a small badge and not a fat one.
    var diameter: CGFloat = 26

    private var stroke: CGFloat { diameter * 3 / 26 }
    private var digit: CGFloat { diameter * 10 / 26 }

    @ViewBuilder
    var body: some View {
        if let estimate {
            let frac = min(1, Double(done) / Double(max(1, estimate)))
            let complete = done >= estimate
            ZStack {
                Circle().stroke(Color.dsFillStrong, lineWidth: stroke)
                Circle()
                    .trim(from: 0, to: frac)
                    .stroke(complete ? Color.green : color,
                            style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(done)")
                    .font(.system(size: digit, design: .rounded).weight(.bold))
                    .foregroundStyle(complete ? Color.green : Color.dsPrimary)
            }
            .frame(width: diameter, height: diameter)
            .help("\(done) of \(estimate) pomodoros")
            .accessibilityLabel("\(done) of \(estimate) pomodoros")
        } else if done > 0 {
            Text("🍅\(done)")
                .font(.system(size: digit, design: .rounded).weight(.medium))
                .foregroundStyle(Color.dsSecondary)
                .help("\(done) pomodoros")
                .accessibilityLabel("\(done) pomodoros")
        }
    }
}

/// Priority flag menu (P1–P4) — one component shared by the task composer and the
/// editor, which previously carried near-identical copies that had already drifted.
struct PriorityMenu: View {
    @Binding var priority: SharinganCore.TaskPriority
    /// Priority names/colors/custom levels — the menu lists `levels(custom:)`
    /// and shows each level's user-facing name, rank chip, and flag color.
    let settings: PomodoroSettings
    var body: some View {
        Menu {
            ForEach(SharinganCore.TaskPriority.levels(custom: settings.customPriorityLevels)) { p in
                Button { priority = p } label: {
                    Label(settings.priorityName(p),
                          systemImage: priority == p ? "checkmark"
                                       : (p == .none ? "flag.slash" : "flag.fill"))
                }
            }
        } label: {
            let hex = settings.priorityColorHex(priority)
            HStack(spacing: 5) {
                Image(systemName: priority == .none ? "flag" : "flag.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(priority == .none ? "Priority" : settings.priorityShortLabel(priority))
                    .font(.system(.caption, design: .rounded).weight(.medium))
            }
            .foregroundStyle(hex.map { Color(hex: $0) } ?? Color.dsSecondary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(Color.dsFill))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }
}
