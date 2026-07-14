import SwiftUI
import SharinganCore

/// Day-paged per-task focus report: every task that logged focus on the
/// chosen day, with pomodoro count and real minutes, subtask rows expandable
/// underneath. Data comes straight from TaskStore.focusLog (see FocusLog.swift
/// for the task-row-includes-subtasks rule).
struct ReportView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var store = TaskStore.shared
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var expanded: Set<String> = []

    private var accent: Color { timer.settings.theme.accent }
    private var cal: Calendar { Calendar.current }
    private var isToday: Bool { cal.isDateInToday(day) }
    private var rows: [FocusReportRow] {
        FocusReport.rows(entries: store.focusEntries(on: day), tasks: store.tasks)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            pager
            if rows.isEmpty {
                emptyState
            } else {
                VStack(spacing: 2) {
                    ForEach(rows) { row in reportRow(row) }
                }
                totalsFooter
            }
        }
    }

    // MARK: - Day pager

    private var pager: some View {
        HStack(spacing: 10) {
            pagerButton("chevron.left", enabled: true) {
                day = cal.date(byAdding: .day, value: -1, to: day) ?? day
            }
            Text(dayLabel)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .frame(minWidth: 180)
            pagerButton("chevron.right", enabled: !isToday) {
                day = min(cal.startOfDay(for: Date()),
                          cal.date(byAdding: .day, value: 1, to: day) ?? day)
            }
            Spacer()
            if !isToday {
                Button("Today") { day = cal.startOfDay(for: Date()) }
                    .buttonStyle(.pressableSubtle)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(accent)
            }
        }
    }

    private func pagerButton(_ symbol: String, enabled: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(enabled ? .white : .white.opacity(0.25))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var dayLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEE, MMM d"
        return isToday ? "\(f.string(from: day)) · Today" : f.string(from: day)
    }

    // MARK: - Rows

    private func reportRow(_ row: FocusReportRow) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 10) {
                if row.subrows.isEmpty {
                    Color.clear.frame(width: 16, height: 16)
                } else {
                    Button {
                        if expanded.contains(row.id) { expanded.remove(row.id) }
                        else { expanded.insert(row.id) }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                            .rotationEffect(.degrees(expanded.contains(row.id) ? 90 : 0))
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                }
                Image(systemName: row.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(row.isDone ? accent : .white.opacity(0.35))
                Text(row.entry.title)
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .strikethrough(row.isDone, color: .white.opacity(0.4))
                    .foregroundStyle(row.isDeleted ? .white.opacity(0.4) : .white)
                    .lineLimit(1)
                if row.isDeleted {
                    Text("deleted")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                } else if let cat = row.category {
                    Text(cat.uppercased())
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(Color(hex: store.color(for: cat)))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color(hex: store.color(for: cat)).opacity(0.14)))
                }
                Spacer(minLength: 8)
                metric(count: row.entry.count, seconds: row.entry.seconds)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(Color.white.opacity(0.04)))

            if expanded.contains(row.id) {
                ForEach(row.subrows) { sub in
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.3))
                        Text(sub.title)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        metric(count: sub.count, seconds: sub.seconds)
                    }
                    .padding(.leading, 38).padding(.trailing, 12).padding(.vertical, 6)
                }
            }
        }
    }

    private func metric(count: Int, seconds: TimeInterval) -> some View {
        HStack(spacing: 10) {
            Text("🍅 ×\(count)")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(FocusReport.durationLabel(seconds))
                .font(.system(.caption, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(accent)
                .frame(minWidth: 46, alignment: .trailing)
        }
    }

    private var totalsFooter: some View {
        let totals = store.focusDayTotals(on: day)
        return HStack {
            Text("Total")
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            metric(count: totals.count, seconds: totals.seconds)
        }
        .padding(.horizontal, 12).padding(.top, 8)
        .overlay(Divider().overlay(Color.dsHairline), alignment: .top)
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.white.opacity(0.25))
                Text("No focus logged this day.")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
        }
        .padding(.vertical, 60)
    }
}
