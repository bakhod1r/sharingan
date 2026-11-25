import SwiftUI
import SharinganCore

/// Sharingan red used across the habit UI (done cells, rings, bars).
extension Color {
    static let habitRed = Color(red: 0.90, green: 0.14, blue: 0.17)
    static let habitRedDeep = Color(red: 0.55, green: 0.04, blue: 0.08)
}

enum HabitFormat {
    static func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    static func weekdayShort(_ weekday: Int, calendar: Calendar = .current) -> String {
        calendar.shortWeekdaySymbols[(weekday - 1) % 7]
    }

    /// Weekday numbers in the calendar's display order (Mon..Sun for most locales).
    static func weekdayOrder(calendar: Calendar = .current) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    static func unit(_ habit: TaskHabit, _ n: Int) -> String {
        if case .timesPerWeek = habit.schedule { return n == 1 ? "week" : "weeks" }
        return n == 1 ? "day" : "days"
    }

    /// "Mangekyō · 14 days to Eternal Mangekyō"
    static func stageLine(eye: HabitEyeStage, streak: Int, habit: TaskHabit) -> String {
        guard let next = HabitEyeStage.nextStage(after: max(streak, eye.threshold)) else { return eye.awakened }
        let n = next.unitsToGo
        return "\(eye.awakened) · \(n) \(unit(habit, n)) to \(next.stage.awakened)"
    }

    static func modeLabel(_ habit: TaskHabit) -> String {
        switch habit.mode {
        case .pomodoro(let t): return "\(t) 🍅 a day"
        case .manual: return "manual"
        }
    }
}

/// A habit's eye: bare red iris while dormant, otherwise its awakened style.
struct HabitEyeView: View {
    var stage: HabitEyeStage
    var diameter: CGFloat
    var body: some View {
        MoveIrisView(diameter: diameter, style: stage.style ?? .classic,
                     emergence: stage == .dormant ? 0 : 1)
            .frame(width: diameter, height: diameter)
            .opacity(stage == .dormant ? 0.55 : 1)
            .accessibilityLabel(stage.awakened)
    }
}

/// Progress ring around arbitrary content.
struct HabitRing<Content: View>: View {
    var progress: Double
    var size: CGFloat
    var lineWidth: CGFloat = 3
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack {
            Circle().stroke(Color.dsFillStrong, lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(0, min(1, progress)))
                .stroke(Color.habitRed, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(DS.Motion.standard, value: progress)
            content()
                .padding(lineWidth + 2)
        }
        .frame(width: size, height: size)
    }
}

/// A done cell: red disc with a dark tomoe-dot core. Not done = hollow.
struct HabitDayDot: View {
    enum Look { case done, missed, pending, dim, hidden }
    var look: Look
    var isToday = false
    var size: CGFloat = 20
    var body: some View {
        ZStack {
            switch look {
            case .done:
                Circle().fill(Color.habitRed)
                Circle().fill(Color.habitRedDeep).frame(width: size * 0.32, height: size * 0.32)
            case .missed:
                Circle().fill(Color.dsFillStrong)
            case .pending:
                Circle().fill(Color.dsFill)
            case .dim:
                Circle().fill(Color.dsFill.opacity(0.5))
            case .hidden:
                Circle().fill(Color.clear)
            }
            if isToday {
                Circle().stroke(Color.dsPrimary.opacity(0.85), lineWidth: 1.5).padding(-2)
            }
        }
        .frame(width: size, height: size)
    }
}

struct HabitBarItem: Identifiable {
    var id: String
    var label: String
    var value: Double?       // nil = no data
    var highlight = false
}

/// Compact % bar chart (0...100).
struct HabitBarChart: View {
    var items: [HabitBarItem]
    var height: CGFloat = 96
    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(items) { item in
                VStack(spacing: 4) {
                    Text(item.value.map(HabitFormat.percent) ?? "–")
                        .font(.system(size: 9, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.dsTertiary)
                        .minimumScaleFactor(0.6).lineLimit(1)
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.dsFill)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(LinearGradient(colors: [Color.habitRed, Color.habitRedDeep],
                                                 startPoint: .top, endPoint: .bottom))
                            .opacity(item.highlight ? 1 : 0.8)
                            .frame(height: max(item.value == nil ? 0 : 2, (height - 34) * CGFloat(item.value ?? 0)))
                    }
                    .frame(height: height - 34)
                    Text(item.label)
                        .font(.system(size: 9, design: .rounded).weight(.medium))
                        .foregroundStyle(Color.dsSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height)
        .animation(DS.Motion.standard, value: items.map { $0.value ?? -1 })
    }
}

/// Card chrome shared by the habit charts.
struct HabitCard<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text(title).dsSectionLabel()
            content()
        }
        .padding(DS.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).fill(Color.dsFill))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .stroke(Color.dsHairline, lineWidth: 1))
    }
}

struct HabitRangePicker: View {
    @Binding var days: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach([7, 30, 90], id: \.self) { d in
                Button { withAnimation(DS.Motion.standard) { days = d } } label: {
                    Text("\(d) days")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(days == d ? .white : Color.dsSecondary)
                        .padding(.horizontal, 12).frame(height: 26)
                        .background(Capsule().fill(days == d ? Color.habitRed.opacity(0.85) : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.dsFill))
    }
}

/// Four KPI tiles: completion, best current streak (with its eye), total done, strongest weekday.
struct HabitKPIRow: View {
    var report: HabitReport
    var calendar: Calendar = .current

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Space.md) { tiles }
            VStack(spacing: DS.Space.md) {
                HStack(spacing: DS.Space.md) { tile1; tile2 }
                HStack(spacing: DS.Space.md) { tile3; tile4 }
            }
        }
    }

    @ViewBuilder private var tiles: some View { tile1; tile2; tile3; tile4 }

    private var tile1: some View {
        tile("Completion") { Text(HabitFormat.percent(report.overallRate)).kpiValue() }
    }
    private var tile2: some View {
        tile("Best streak") {
            HStack(spacing: 8) {
                HabitEyeView(stage: report.bestStreakEye, diameter: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(report.bestCurrentStreak)").kpiValue()
                    Text(report.bestStreakEye.awakened)
                        .font(.system(size: 10, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.dsSecondary).lineLimit(1)
                }
            }
        }
    }
    private var tile3: some View { tile("Total done") { Text("\(report.totalDone)").kpiValue() } }
    private var tile4: some View {
        tile("Strongest day") {
            Text(report.strongestWeekday.map { HabitFormat.weekdayShort($0, calendar: calendar) } ?? "–").kpiValue()
        }
    }

    private func tile<V: View>(_ title: String, @ViewBuilder _ value: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).dsSectionLabel()
            value()
        }
        .padding(DS.Space.md)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(Color.dsFill))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .stroke(Color.dsHairline, lineWidth: 1))
    }
}

private extension Text {
    func kpiValue() -> some View {
        self.font(.system(size: 24, design: .rounded).weight(.bold))
            .foregroundStyle(Color.dsPrimary)
            .contentTransition(.numericText())
    }
}

/// "Monthly completion %" + "Weekday completion %" side by side (wraps when narrow).
struct HabitChartsRow: View {
    var report: HabitReport
    var calendar: Calendar = .current

    private var monthly: [HabitBarItem] {
        let f = DateFormatter(); f.dateFormat = "MMM"; f.calendar = calendar; f.timeZone = calendar.timeZone
        return report.monthlyRates.map {
            HabitBarItem(id: "\($0.monthStart.timeIntervalSince1970)", label: f.string(from: $0.monthStart),
                         value: $0.tally.scheduled == 0 ? nil : $0.rate)
        }
    }
    private var weekday: [HabitBarItem] {
        HabitFormat.weekdayOrder(calendar: calendar).map { wd in
            HabitBarItem(id: "\(wd)", label: HabitFormat.weekdayShort(wd, calendar: calendar),
                         value: report.weekdayRates[wd], highlight: wd == report.strongestWeekday)
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DS.Space.md) { cards }
                .frame(minWidth: 560)
            VStack(spacing: DS.Space.md) { cards }
        }
    }

    @ViewBuilder private var cards: some View {
        HabitCard(title: "Monthly completion %") { HabitBarChart(items: monthly) }
        HabitCard(title: "Weekday completion %") { HabitBarChart(items: weekday) }
    }
}

/// GitHub-style heatmap: 7 rows (weekdays) x `weeks` columns, red intensity.
struct HabitHeatmap: View {
    var input: HabitInput
    var focusLog: [FocusLogEntry]
    var checks: [HabitCheck]
    var today: Date
    var weeks = 12
    var calendar: Calendar = .current

    private var columns: [[Date]] {
        let t = calendar.startOfDay(for: today)
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: t)?.start else { return [] }
        return (0..<weeks).reversed().map { back in
            let ws = calendar.date(byAdding: .day, value: -7 * back, to: thisWeek) ?? thisWeek
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: ws) }
        }
    }

    var body: some View {
        let t = calendar.startOfDay(for: today)
        HStack(alignment: .top, spacing: 3) {
            VStack(spacing: 3) {
                ForEach(Array(HabitFormat.weekdayOrder(calendar: calendar).enumerated()), id: \.offset) { i, wd in
                    Text(i % 2 == 0 ? String(HabitFormat.weekdayShort(wd, calendar: calendar).prefix(1)) : "")
                        .font(.system(size: 8, design: .rounded)).foregroundStyle(Color.dsTertiary)
                        .frame(width: 10, height: 14)
                }
            }
            ForEach(Array(columns.enumerated()), id: \.offset) { _, col in
                VStack(spacing: 3) {
                    ForEach(col, id: \.self) { d in cell(d, t) }
                }
            }
        }
    }

    @ViewBuilder private func cell(_ d: Date, _ t: Date) -> some View {
        let status = HabitEngine.status(for: d, habit: input.habit, taskID: input.taskID,
                                        focusLog: focusLog, checks: checks, today: t, calendar: calendar)
        let p = HabitEngine.progress(on: d, habit: input.habit, taskID: input.taskID,
                                     focusLog: focusLog, checks: checks, calendar: calendar)
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(fill(status, p))
            .frame(width: 14, height: 14)
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(d == t ? Color.dsPrimary.opacity(0.8) : .clear, lineWidth: 1))
            .help(d.formatted(date: .abbreviated, time: .omitted))
    }

    private func fill(_ s: HabitDayStatus, _ p: Double) -> Color {
        switch s {
        case .done: return Color.habitRed.opacity(0.95)
        case .missed, .pending: return p > 0 ? Color.habitRed.opacity(0.25 + 0.4 * p) : Color.dsFillStrong
        case .notScheduled: return p > 0 ? Color.habitRed.opacity(0.3) : Color.dsFill.opacity(0.6)
        case .beforeStart: return Color.dsFill.opacity(0.3)
        case .future: return Color.clear
        }
    }
}

/// Shared helper: one habit's own report (monthly + weekday), for mini charts.
@MainActor
enum HabitStats {
    static func report(for input: HabitInput, store: TaskStore, days: Int = 90,
                       today: Date = Date(), calendar: Calendar = .current) -> HabitReport {
        HabitReport.make(habits: [input], focusLog: store.focusLog, checks: store.habitChecks,
                         days: days, today: today, calendar: calendar)
    }
}
