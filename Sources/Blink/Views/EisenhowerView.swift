import SwiftUI
import BlinkCore

/// Eisenhower matrix smart view — the open task list re-read as four glass
/// cards (urgency × importance). Purely presentational: classification lives
/// in `EisenhowerQuadrant.classify` (BlinkCore); tapping a row hands the task
/// back to TasksView, which opens the same editor sheet the list rows use.
struct EisenhowerView: View {
    @ObservedObject var timer: PomodoroTimer
    /// Opens the full task editor (TasksView sets its `editorTask`).
    var openEditor: (TaskItem) -> Void
    @ObservedObject private var store = TaskStore.shared

    init(timer: PomodoroTimer, openEditor: @escaping (TaskItem) -> Void) {
        self.timer = timer
        self.openEditor = openEditor
    }

    /// Open tasks bucketed by quadrant, in the enum's canonical card order.
    private var buckets: [(quadrant: EisenhowerQuadrant, items: [TaskItem])] {
        let now = Date()
        let open = store.tasks.filter { !$0.isDone }
        var byQuadrant: [EisenhowerQuadrant: [TaskItem]] = [:]
        for task in open {
            byQuadrant[EisenhowerQuadrant.classify(task, now: now), default: []].append(task)
        }
        return EisenhowerQuadrant.allCases.map { ($0, byQuadrant[$0] ?? []) }
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)],
                  spacing: 10) {
            ForEach(buckets, id: \.quadrant) { bucket in
                card(bucket.quadrant, bucket.items)
            }
        }
    }

    // MARK: - Quadrant card

    private func card(_ quadrant: EisenhowerQuadrant, _ items: [TaskItem]) -> some View {
        let tint = Color(hex: quadrant.tintHex)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: quadrant.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                Text(quadrant.label).dsSectionLabel()
                Spacer()
                Text("\(items.count)")
                    .font(.system(.caption2, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.dsSecondary)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(tint.opacity(0.14)))
            }
            .help(quadrant.subtitle)

            if items.isEmpty {
                Text("—")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.dsTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(items) { task in taskRow(task) }
                    }
                }
            }
        }
        .padding(10)
        .frame(height: 150)
        .glassRounded(DS.Radius.md, material: .thin)
        .overlay(alignment: .top) {
            // Quiet tint wash along the top edge so each quadrant reads at a glance.
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.10), .clear],
                                     startPoint: .top, endPoint: .center))
                .allowsHitTesting(false)
        }
    }

    // MARK: - Compact task row

    private func taskRow(_ task: TaskItem) -> some View {
        Button { openEditor(task) } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(priorityTint(task) ?? Color.dsFillStrong)
                    .frame(width: 6, height: 6)
                Text(task.title)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.dsPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if let due = task.dueDate { dueChip(due) }
            }
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(Color.dsFill))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
        }
        .buttonStyle(.pressableSubtle)
        .help("Edit \(task.title)…")
        .accessibilityLabel("Edit \(task.title)")
    }

    /// Priority flag color, nil when the task carries no flag.
    private func priorityTint(_ task: TaskItem) -> Color? {
        timer.settings.priorityColorHex(task.priority).map { Color(hex: $0) }
    }

    /// Tiny "today HH:mm" / "MMM d" pill — red when the deadline has passed.
    private func dueChip(_ due: Date) -> some View {
        let overdue = due < Date()
        return Text(dueText(due))
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(overdue ? Color.red : Color.dsSecondary)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(overdue ? Color.red.opacity(0.14) : Color.dsFillStrong))
    }

    private func dueText(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = Calendar.current.isDateInToday(d) ? "'today' HH:mm" : "MMM d"
        return f.string(from: d)
    }
}
