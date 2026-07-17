import SwiftUI
import SharinganCore

/// Analytics → Timeline: a day's sessions laid out across the clock, plus a
/// session list. The day pager is the "time machine" — page back to replay any
/// past day.
struct AnalyticsTimelineView: View {
    @ObservedObject var timer: PomodoroTimer
    var completedOnly: Bool = false
    var allowedTaskIDs: Set<UUID>? = nil
    @ObservedObject private var log = FocusSessionLog.shared
    @State private var day = Calendar.current.startOfDay(for: Date())

    private var accent: Color { timer.settings.theme.accent }
    private let breakColor = Color.green

    private var sessions: [SessionRecord] {
        AnalyticsEngine.filter(sessions: log.sessions(on: day),
                               completedOnly: completedOnly,
                               allowedTaskIDs: allowedTaskIDs)
            .sorted { $0.start < $1.start }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            pager
            if sessions.isEmpty {
                Text("No sessions on this day.")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                track
                axis
                Divider().overlay(Color.white.opacity(0.1))
                ForEach(sessions) { row($0) }
                legend
            }
        }
        .padding(16)
        .glassRounded(DS.Radius.xl, material: .regular)
        .liquidShadow(radius: 12, y: 6)
    }

    // MARK: - Track

    private func fraction(_ date: Date) -> CGFloat {
        let cal = Calendar.current
        let secs = date.timeIntervalSince(cal.startOfDay(for: day))
        return CGFloat(min(max(secs / 86_400, 0), 1))
    }

    private var track: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05))
                ForEach(sessions) { s in
                    let x = fraction(s.start) * geo.size.width
                    let w = max(2, (fraction(s.end) - fraction(s.start)) * geo.size.width)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color(for: s).opacity(s.completed ? 0.9 : 0.4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(s.completed ? .clear : color(for: s),
                                              style: StrokeStyle(lineWidth: 1, dash: [2, 2])))
                        .frame(width: w)
                        .offset(x: x)
                }
            }
        }
        .frame(height: 36)
    }

    private var axis: some View {
        GeometryReader { geo in
            ForEach([0, 6, 12, 18, 24], id: \.self) { h in
                Text("\(h):00")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .offset(x: CGFloat(h) / 24 * geo.size.width - (h == 24 ? 26 : 0))
            }
        }
        .frame(height: 12)
    }

    private func color(for s: SessionRecord) -> Color {
        s.phase == .focus ? accent : breakColor
    }

    // MARK: - Rows

    private func row(_ s: SessionRecord) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color(for: s).opacity(s.completed ? 0.9 : 0.4))
                .frame(width: 8, height: 8)
            Text(timeRange(s))
                .font(.system(.caption, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 110, alignment: .leading)
            Text(s.phase == .focus ? (s.taskTitle ?? "Focus") : s.phase.label)
                .font(.system(.callout, design: .rounded).weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            if !s.completed {
                Text("abandoned")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Text("\(Int(s.seconds / 60))m")
                .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.vertical, 2)
    }

    private func timeRange(_ s: SessionRecord) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return "\(f.string(from: s.start))–\(f.string(from: s.end))"
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendDot(accent, "Focus")
            legendDot(breakColor, "Break")
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(accent, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .frame(width: 10, height: 10)
                Text("Abandoned").foregroundStyle(.white.opacity(0.5))
            }
        }
        .font(.system(.caption2, design: .rounded))
    }

    private func legendDot(_ c: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Pager (time machine)

    private var pager: some View {
        HStack {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.pressableSubtle)
            Spacer()
            Text(Calendar.current.isDateInToday(day)
                 ? "Today"
                 : day.formatted(date: .abbreviated, time: .omitted))
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Spacer()
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.pressableSubtle)
                .disabled(Calendar.current.isDateInToday(day))
                .opacity(Calendar.current.isDateInToday(day) ? 0.3 : 1)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white.opacity(0.8))
    }

    private func step(_ delta: Int) {
        if let d = Calendar.current.date(byAdding: .day, value: delta, to: day) {
            withAnimation(DS.Motion.standard) {
                day = min(d, Calendar.current.startOfDay(for: Date()))
            }
        }
    }
}
