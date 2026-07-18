import SwiftUI
import SharinganCore

/// Analytics → Timeline: an Apple-Calendar-style view of your focus sessions —
/// Day / Week / Month, with an hour grid and sessions drawn as time blocks.
/// The pager + calendar picker are the "time machine" for replaying any past
/// period.
struct AnalyticsTimelineView: View {
    @ObservedObject var timer: PomodoroTimer
    var completedOnly: Bool = false
    var allowedTaskIDs: Set<UUID>? = nil
    @ObservedObject private var log = FocusSessionLog.shared
    @State private var anchor = Calendar.current.startOfDay(for: Date())
    @State private var scale: Scale = .week
    @State private var showDatePicker = false

    enum Scale: String, CaseIterable, Identifiable {
        case day = "Day", week = "Week", month = "Month"
        var id: String { rawValue }
    }

    private var accent: Color { timer.settings.theme.accent }
    private let breakColor = Color.green
    private let rowHeight: CGFloat = 44
    private var cal: Calendar { Calendar.current }

    private func sessions(on day: Date) -> [SessionRecord] {
        AnalyticsEngine.filter(sessions: log.sessions(on: day),
                               completedOnly: completedOnly,
                               allowedTaskIDs: allowedTaskIDs)
            .sorted { $0.start < $1.start }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            switch scale {
            case .day:   dayView
            case .week:  weekView
            case .month: monthView
            }
        }
        .padding(16)
        .glassRounded(DS.Radius.xl, material: .regular)
        .liquidShadow(radius: 12, y: 6)
    }

    // MARK: - Header (scale picker + pager + calendar jump)

    @Namespace private var scaleNS
    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(Scale.allCases) { s in
                    let selected = s == scale
                    Button { withAnimation(DS.Motion.standard) { scale = s } } label: {
                        Text(s.rawValue)
                            .font(.system(.caption2, design: .rounded).weight(.bold))
                            .foregroundStyle(selected ? .white : .white.opacity(0.55))
                            .padding(.horizontal, 11).frame(height: 24)
                            .background {
                                if selected {
                                    Capsule().fill(accent.opacity(0.85))
                                        .matchedGeometryEffect(id: "tlScale", in: scaleNS)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.pressableSubtle)
                }
            }
            .padding(3).background(Capsule().fill(Color.white.opacity(0.05)))

            Spacer()

            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.pressableSubtle)
            Button { showDatePicker.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                    Text(periodLabel).contentTransition(.numericText())
                }
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
            }
            .buttonStyle(.pressableSubtle)
            .popover(isPresented: $showDatePicker, arrowEdge: .bottom) {
                DatePicker("Jump to date", selection: Binding(
                    get: { anchor },
                    set: { anchor = min(cal.startOfDay(for: $0),
                                        cal.startOfDay(for: Date())) }),
                    in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical).labelsHidden()
                    .frame(width: 260).padding(12)
            }
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.pressableSubtle)
                .disabled(isAtPresent).opacity(isAtPresent ? 0.3 : 1)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white.opacity(0.85))
    }

    private var isAtPresent: Bool {
        switch scale {
        case .day:   return cal.isDateInToday(anchor)
        case .week:  return cal.isDate(anchor, equalTo: Date(), toGranularity: .weekOfYear)
        case .month: return cal.isDate(anchor, equalTo: Date(), toGranularity: .month)
        }
    }

    private var periodLabel: String {
        let f = DateFormatter()
        switch scale {
        case .day:
            if cal.isDateInToday(anchor) { return "Today" }
            f.dateFormat = "EEE, MMM d"; return f.string(from: anchor)
        case .week:
            let days = weekDays
            f.dateFormat = "MMM d"
            let end = DateFormatter(); end.dateFormat = "d"
            return "\(f.string(from: days.first!)) – \(end.string(from: days.last!))"
        case .month:
            f.dateFormat = "MMMM yyyy"; return f.string(from: anchor)
        }
    }

    private func step(_ delta: Int) {
        let comp: Calendar.Component = scale == .day ? .day
            : (scale == .week ? .weekOfYear : .month)
        if let d = cal.date(byAdding: comp, value: delta, to: anchor) {
            withAnimation(DS.Motion.standard) {
                anchor = min(d, cal.startOfDay(for: Date()))
            }
        }
    }

    // MARK: - Hour range shared by Day/Week

    /// The [firstHour, lastHour) window to draw, derived from the visible days'
    /// sessions (clamped, with a sane default when empty).
    private func hourRange(for days: [Date]) -> (Int, Int) {
        let all = days.flatMap { sessions(on: $0) }
        guard !all.isEmpty else { return (8, 20) }
        let startHours = all.map { cal.component(.hour, from: $0.start) }
        let endHours = all.map { s -> Int in
            let h = cal.component(.hour, from: s.end)
            let m = cal.component(.minute, from: s.end)
            return m > 0 ? h + 1 : h
        }
        let lo = max(0, (startHours.min() ?? 8) - 1)
        let hi = min(24, (endHours.max() ?? 20) + 1)
        return (lo, max(lo + 4, hi))
    }

    // MARK: - Day view

    private var dayView: some View {
        let range = hourRange(for: [anchor])
        return ScrollView {
            HStack(alignment: .top, spacing: 6) {
                hoursColumn(range)
                dayColumn(anchor, range: range)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxHeight: 460)
    }

    // MARK: - Week view

    private var weekDays: [Date] {
        let startsMonday = timer.settings.weekStartsOnMonday
        let wd = cal.component(.weekday, from: anchor)            // 1=Sun…7=Sat
        let offset = startsMonday ? (wd + 5) % 7 : (wd - 1)
        guard let weekStart = cal.date(byAdding: .day, value: -offset, to: anchor)
        else { return [anchor] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var weekView: some View {
        let days = weekDays
        let range = hourRange(for: days)
        return VStack(spacing: 6) {
            // Day headers.
            HStack(spacing: 4) {
                Color.clear.frame(width: 34)
                ForEach(days, id: \.self) { d in
                    dayHeader(d).frame(maxWidth: .infinity)
                }
            }
            ScrollView {
                HStack(alignment: .top, spacing: 4) {
                    hoursColumn(range)
                    ForEach(days, id: \.self) { d in
                        dayColumn(d, range: range).frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(maxHeight: 440)
        }
    }

    private func dayHeader(_ d: Date) -> some View {
        let f = DateFormatter(); f.dateFormat = "EEE"
        let isToday = cal.isDateInToday(d)
        return VStack(spacing: 2) {
            Text(f.string(from: d))
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
            Text("\(cal.component(.day, from: d))")
                .font(.system(.callout, design: .rounded).weight(.bold))
                .foregroundStyle(isToday ? .white : .white.opacity(0.8))
                .frame(width: 24, height: 24)
                .background(Circle().fill(isToday ? accent : .clear))
        }
    }

    // MARK: - Shared grid pieces

    private func hoursColumn(_ range: (Int, Int)) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(range.0..<range.1, id: \.self) { h in
                Text(hourLabel(h))
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 30, height: rowHeight, alignment: .topTrailing)
            }
        }
    }

    private func hourLabel(_ h: Int) -> String {
        if h == 0 || h == 24 { return "12A" }
        if h == 12 { return "12P" }
        return h < 12 ? "\(h)A" : "\(h - 12)P"
    }

    private func dayColumn(_ day: Date, range: (Int, Int)) -> some View {
        let hours = range.1 - range.0
        return ZStack(alignment: .top) {
            // Hour grid lines.
            VStack(spacing: 0) {
                ForEach(0..<hours, id: \.self) { _ in
                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                    Spacer().frame(height: rowHeight - 1)
                }
            }
            // Session blocks.
            GeometryReader { geo in
                ForEach(sessions(on: day)) { s in
                    block(s, range: range, width: geo.size.width)
                }
            }
        }
        .frame(height: CGFloat(hours) * rowHeight)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.02)))
    }

    private func yOffset(_ date: Date, day: Date, range: (Int, Int)) -> CGFloat {
        let secs = date.timeIntervalSince(cal.startOfDay(for: day))
        let hoursFromTop = secs / 3600 - Double(range.0)
        return CGFloat(hoursFromTop) * rowHeight
    }

    private func block(_ s: SessionRecord, range: (Int, Int), width: CGFloat) -> some View {
        let day = cal.startOfDay(for: s.start)
        let top = max(0, yOffset(s.start, day: day, range: range))
        let bottom = yOffset(s.end, day: day, range: range)
        let height = max(14, bottom - top)
        let c = s.phase == .focus ? accent : breakColor
        return RoundedRectangle(cornerRadius: 4)
            .fill(c.opacity(s.completed ? 0.85 : 0.35))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(s.completed ? .clear : c,
                                  style: StrokeStyle(lineWidth: 1, dash: [2, 2])))
            .overlay(alignment: .topLeading) {
                if height > 20 {
                    Text(s.phase == .focus ? (s.taskTitle ?? "Focus") : s.phase.label)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(.horizontal, 3).padding(.top, 2)
                }
            }
            .frame(width: max(0, width - 3), height: height)
            .offset(x: 1, y: top)
    }

    // MARK: - Month view

    private var monthView: some View {
        let days = monthGridDays
        let counts = Dictionary(
            AnalyticsEngine.dailyCounts(from: monthSessions).map { ($0.day, $0.count) },
            uniquingKeysWith: +)
        let peak = counts.values.max() ?? 0
        let weekdaySymbols = timer.settings.weekStartsOnMonday
            ? ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(weekdaySymbols, id: \.self) { s in
                    Text(s).font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                }
            }
            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(days, id: \.self) { d in
                    monthCell(d, count: counts[d] ?? 0, peak: peak)
                }
            }
        }
    }

    private var monthSessions: [SessionRecord] {
        monthGridDays.flatMap { sessions(on: $0) }
    }

    private func monthCell(_ d: Date, count: Int, peak: Int) -> some View {
        let inMonth = cal.isDate(d, equalTo: anchor, toGranularity: .month)
        let isToday = cal.isDateInToday(d)
        let level = count > 0 && peak > 0 ? 0.25 + 0.55 * Double(count) / Double(peak) : 0
        return Button {
            withAnimation(DS.Motion.standard) { anchor = d; scale = .day }
        } label: {
            VStack(spacing: 3) {
                Text("\(cal.component(.day, from: d))")
                    .font(.system(.caption, design: .rounded).weight(isToday ? .bold : .regular))
                    .foregroundStyle(inMonth ? (isToday ? accent : .white) : .white.opacity(0.25))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    Text(" ").font(.system(size: 9))
                }
            }
            .frame(maxWidth: .infinity).frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(count > 0 ? accent.opacity(level) : Color.white.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isToday ? accent.opacity(0.6) : .clear, lineWidth: 1))
        }
        .buttonStyle(.pressableSubtle)
        .disabled(d > Date())
    }

    /// 6×7 grid of days covering `anchor`'s month, padded to whole weeks.
    private var monthGridDays: [Date] {
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: anchor)),
              let range = cal.range(of: .day, in: .month, for: monthStart)
        else { return [] }
        let startsMonday = timer.settings.weekStartsOnMonday
        let firstWd = cal.component(.weekday, from: monthStart)
        let lead = startsMonday ? (firstWd + 5) % 7 : (firstWd - 1)
        guard let gridStart = cal.date(byAdding: .day, value: -lead, to: monthStart)
        else { return [] }
        let total = Int(ceil(Double(lead + range.count) / 7)) * 7
        return (0..<total).compactMap { cal.date(byAdding: .day, value: $0, to: gridStart) }
    }
}
