import SwiftUI
import SharinganCore

/// Sharingan's own date picker — replaces the stock `.graphical` DatePicker in
/// every "Pick a date…" popover. Beyond the usual month grid it shows the
/// existing workload: days that already have open tasks due carry small
/// tomato dots, so picking a deadline doubles as a glance at the week's load.
struct SharinganCalendar: View {
    @Binding var date: Date
    var showsTime: Bool = true
    var accent: Color = .paletteFocusStart
    var weekStartsOnMonday: Bool = true

    @ObservedObject private var store = TaskStore.shared
    /// First day of the month the grid currently shows.
    @State private var visibleMonth: Date

    private let cal = Calendar.current

    init(date: Binding<Date>, showsTime: Bool = true,
         accent: Color = .paletteFocusStart, weekStartsOnMonday: Bool = true) {
        _date = date
        self.showsTime = showsTime
        self.accent = accent
        self.weekStartsOnMonday = weekStartsOnMonday
        let start = Calendar.current.dateInterval(of: .month, for: date.wrappedValue)?.start
        _visibleMonth = State(initialValue: start ?? date.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            weekdayRow
            dayGrid
            quickChips
            if showsTime { timeRow }
        }
        .frame(width: 252)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Text(monthTitle)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            if !cal.isDate(visibleMonth, equalTo: Date(), toGranularity: .month) {
                // Jump back to the current month.
                Button {
                    withAnimation(DS.Motion.snappy) {
                        visibleMonth = cal.dateInterval(of: .month, for: Date())?.start ?? Date()
                    }
                } label: {
                    Image(systemName: "smallcircle.filled.circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .buttonStyle(.pressableSubtle)
                .help("Back to this month")
            }
            Spacer()
            monthArrow("chevron.left", by: -1)
            monthArrow("chevron.right", by: 1)
        }
    }

    private func monthArrow(_ icon: String, by months: Int) -> some View {
        Button {
            withAnimation(DS.Motion.snappy) {
                visibleMonth = cal.date(byAdding: .month, value: months, to: visibleMonth)
                    ?? visibleMonth
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.pressableSubtle)
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMMM yyyy"
        return f.string(from: visibleMonth)
    }

    // MARK: - Weekdays

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { s in
                Text(s)
                    .font(.system(size: 9, design: .rounded).weight(.bold))
                    .foregroundStyle(Color.dsTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var weekdaySymbols: [String] {
        // veryShortWeekdaySymbols starts on Sunday; rotate for Monday starts.
        let base = ["S", "M", "T", "W", "T", "F", "S"]
        return weekStartsOnMonday ? Array(base[1...]) + [base[0]] : base
    }

    // MARK: - Grid

    private var dayGrid: some View {
        let days = gridDays
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0),
                                        count: 7),
                         spacing: 2) {
            ForEach(days, id: \.self) { day in
                dayCell(day)
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Date) -> some View {
        let inMonth = cal.isDate(day, equalTo: visibleMonth, toGranularity: .month)
        let selected = cal.isDate(day, inSameDayAs: date)
        let today = cal.isDateInToday(day)
        let load = min(dueCounts[cal.startOfDay(for: day)] ?? 0, 3)

        Button {
            withAnimation(DS.Motion.snappy) { select(day) }
        } label: {
            VStack(spacing: 2) {
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: 12, design: .rounded)
                        .weight(selected || today ? .bold : .medium))
                    .foregroundStyle(selected ? Color.white
                                     : today ? accent
                                     : inMonth ? Color.dsPrimary : Color.dsTertiary.opacity(0.5))
                // Workload dots: one per open task due that day (capped at 3).
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(i < load
                                  ? (selected ? Color.white.opacity(0.9) : accent.opacity(0.85))
                                  : Color.clear)
                            .frame(width: 3, height: 3)
                    }
                }
            }
            .frame(width: 30, height: 30)
            .background(
                ZStack {
                    if selected {
                        Circle()
                            .fill(LinearGradient(colors: [accent, accent.opacity(0.65)],
                                                 startPoint: .topLeading,
                                                 endPoint: .bottomTrailing))
                            .shadow(color: accent.opacity(0.55), radius: 6)
                    } else if today {
                        Circle().stroke(accent.opacity(0.7), lineWidth: 1.2)
                    }
                }
            )
            .contentShape(Circle())
        }
        .buttonStyle(.pressableSubtle)
    }

    /// 42 cells (6 weeks) starting from the week that holds the 1st.
    private var gridDays: [Date] {
        guard let monthStart = cal.dateInterval(of: .month, for: visibleMonth)?.start
        else { return [] }
        let weekday = cal.component(.weekday, from: monthStart)   // 1=Sun … 7=Sat
        let target = weekStartsOnMonday ? 2 : 1
        let lead = (weekday - target + 7) % 7
        guard let gridStart = cal.date(byAdding: .day, value: -lead, to: monthStart)
        else { return [] }
        return (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: gridStart) }
    }

    /// Open tasks per due-day — powers the workload dots.
    private var dueCounts: [Date: Int] {
        var counts: [Date: Int] = [:]
        for t in store.tasks where !t.isDone && t.trashedAt == nil {
            guard let due = t.dueDate else { continue }
            counts[cal.startOfDay(for: due), default: 0] += 1
        }
        return counts
    }

    /// Moves the selection to `day`, keeping the current time of day.
    private func select(_ day: Date) {
        let time = cal.dateComponents([.hour, .minute], from: date)
        date = cal.date(bySettingHour: time.hour ?? 9,
                        minute: time.minute ?? 0,
                        second: 0, of: day) ?? day
        visibleMonth = cal.dateInterval(of: .month, for: day)?.start ?? day
    }

    // MARK: - Quick picks

    private var quickChips: some View {
        HStack(spacing: 6) {
            quickChip("Today", "star") { select(Date()) }
            quickChip("Tomorrow", "sun.max") {
                select(cal.date(byAdding: .day, value: 1, to: Date()) ?? Date())
            }
            quickChip("+1 week", "calendar") {
                select(cal.date(byAdding: .day, value: 7, to: Date()) ?? Date())
            }
            Spacer(minLength: 0)
        }
    }

    private func quickChip(_ title: String, _ icon: String,
                           action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(DS.Motion.snappy) { action() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9, weight: .semibold))
                Text(title).font(.system(size: 10, design: .rounded).weight(.semibold))
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.pressableSubtle)
    }

    // MARK: - Time

    private var timeRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
            Text(timeLabel)
                .font(.dsTimer(14))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Spacer()
            timeStep("minus", -30)
            timeStep("plus", 30)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    /// Nudges the due TIME in half-hour steps without touching the day.
    private func timeStep(_ icon: String, _ minutes: Int) -> some View {
        Button {
            withAnimation(DS.Motion.snappy) {
                let day = cal.startOfDay(for: date)
                let shifted = cal.date(byAdding: .minute, value: minutes, to: date) ?? date
                // Clamp inside the selected day so stepping never flips the date.
                if cal.isDate(shifted, inSameDayAs: day) { date = shifted }
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.pressableSubtle)
        .help(minutes > 0 ? "Half an hour later" : "Half an hour earlier")
    }

    private var timeLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
