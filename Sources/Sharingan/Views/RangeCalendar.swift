import SwiftUI

/// A two-month graphical date-range picker with a continuous "pill" highlight,
/// like the reference calendar. SwiftUI's `DatePicker` can't select a range, so
/// this is hand-rolled: tap a day to set the start, tap again to set the end
/// (an earlier second tap moves the start). Future days past `maximum` are
/// disabled. Each week row's in-range segment renders as one rounded capsule,
/// and the two endpoints get a solid accent disc.
struct RangeCalendar: View {
    @Binding var start: Date?
    @Binding var end: Date?
    var accent: Color
    var startsMonday: Bool = false
    var maximum: Date = Date()

    @State private var leftMonth: Date = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()

    private var cal: Calendar {
        var c = Calendar.current
        c.firstWeekday = startsMonday ? 2 : 1
        return c
    }
    private let cellSize: CGFloat = 34

    var body: some View {
        VStack(spacing: 14) {
            header
            HStack(alignment: .top, spacing: 24) {
                monthGrid(leftMonth)
                monthGrid(cal.date(byAdding: .month, value: 1, to: leftMonth) ?? leftMonth)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button { step(-1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold))
            }.buttonStyle(.pressableSubtle)
            Spacer()
            Text(monthTitle(leftMonth)).frame(maxWidth: .infinity)
            Text(monthTitle(cal.date(byAdding: .month, value: 1, to: leftMonth) ?? leftMonth))
                .frame(maxWidth: .infinity)
            Spacer()
            Button { step(1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
            }
            .buttonStyle(.pressableSubtle)
            .disabled(showsCurrentMonth)
            .opacity(showsCurrentMonth ? 0.3 : 1)
        }
        .font(.system(.headline, design: .rounded).weight(.bold))
        .foregroundStyle(.white)
    }

    private var showsCurrentMonth: Bool {
        cal.isDate(cal.date(byAdding: .month, value: 1, to: leftMonth) ?? leftMonth,
                   equalTo: maximum, toGranularity: .month)
    }

    private func step(_ delta: Int) {
        if let m = cal.date(byAdding: .month, value: delta, to: leftMonth) {
            withAnimation(DS.Motion.standard) { leftMonth = m }
        }
    }

    // MARK: One month

    private func monthGrid(_ month: Date) -> some View {
        let weeks = weeksOf(month)
        return VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { s in
                    Text(s)
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: cellSize, height: 22)
                }
            }
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        dayCell(day, month: month)
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Date?, month: Date) -> some View {
        Group {
            if let day, cal.isDate(day, equalTo: month, toGranularity: .month) {
                let inRange = isInRange(day)
                let endpoint = isEndpoint(day)
                let disabled = cal.startOfDay(for: day) > cal.startOfDay(for: maximum)
                Button {
                    select(day)
                } label: {
                    ZStack {
                        if inRange {
                            rangeShape(day)
                                .fill(accent.opacity(0.28))
                        }
                        if endpoint {
                            Circle().fill(accent).frame(width: cellSize - 4, height: cellSize - 4)
                        }
                        Text("\(cal.component(.day, from: day))")
                            .font(.system(.callout, design: .rounded)
                                .weight(endpoint ? .bold : .medium))
                            .foregroundStyle(endpoint ? .white
                                             : (disabled ? .white.opacity(0.2) : .white.opacity(0.85)))
                    }
                    .frame(width: cellSize, height: cellSize)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(disabled)
            } else {
                Color.clear.frame(width: cellSize, height: cellSize)
            }
        }
    }

    /// The week-row capsule: rounded on the left when this cell opens the row's
    /// in-range segment (row start or previous day out of range), rounded on the
    /// right when it closes it.
    private func rangeShape(_ day: Date) -> UnevenRoundedRectangle {
        let r = cellSize / 2
        let col = weekdayIndex(day)
        let prev = cal.date(byAdding: .day, value: -1, to: day)
        let next = cal.date(byAdding: .day, value: 1, to: day)
        let roundLeft = col == 0 || !(prev.map(isInRange) ?? false)
        let roundRight = col == 6 || !(next.map(isInRange) ?? false)
        return UnevenRoundedRectangle(
            topLeadingRadius: roundLeft ? r : 0,
            bottomLeadingRadius: roundLeft ? r : 0,
            bottomTrailingRadius: roundRight ? r : 0,
            topTrailingRadius: roundRight ? r : 0)
    }

    // MARK: Selection

    private func select(_ day: Date) {
        let d = cal.startOfDay(for: day)
        withAnimation(DS.Motion.standard) {
            if start == nil || end != nil {
                start = d; end = nil                    // begin a fresh range
            } else if let s = start {
                if d < cal.startOfDay(for: s) { start = d }   // earlier tap moves start
                else { end = d }
            }
        }
    }

    private func isInRange(_ day: Date) -> Bool {
        let d = cal.startOfDay(for: day)
        guard let s = start.map({ cal.startOfDay(for: $0) }) else { return false }
        let e = end.map { cal.startOfDay(for: $0) } ?? s
        return d >= min(s, e) && d <= max(s, e)
    }

    private func isEndpoint(_ day: Date) -> Bool {
        let d = cal.startOfDay(for: day)
        if let s = start, cal.isDate(d, inSameDayAs: s) { return true }
        if let e = end, cal.isDate(d, inSameDayAs: e) { return true }
        return false
    }

    // MARK: Calendar math

    private var weekdaySymbols: [String] {
        let base = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].map { String($0.prefix(1)) }
        return startsMonday ? Array(base[1...] + base[..<1]) : base
    }

    private func weekdayIndex(_ day: Date) -> Int {
        let wd = cal.component(.weekday, from: day)   // 1=Sun…7=Sat
        return startsMonday ? (wd + 5) % 7 : (wd - 1)
    }

    /// Weeks of `month`, each a 7-slot row (nil outside the month).
    private func weeksOf(_ month: Date) -> [[Date?]] {
        guard let first = cal.date(from: cal.dateComponents([.year, .month], from: month)),
              let count = cal.range(of: .day, in: .month, for: first)?.count
        else { return [] }
        let lead = weekdayIndex(first)
        var slots = [Date?](repeating: nil, count: lead)
        for d in 0..<count {
            slots.append(cal.date(byAdding: .day, value: d, to: first))
        }
        while slots.count % 7 != 0 { slots.append(nil) }
        return stride(from: 0, to: slots.count, by: 7).map { Array(slots[$0..<$0 + 7]) }
    }

    private func monthTitle(_ m: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: m)
    }
}
