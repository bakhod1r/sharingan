import Foundation

public enum HabitDayStatus: Equatable, Sendable {
    case done, missed, pending, notScheduled, beforeStart, future
}

/// done / scheduled counts over a range.
public struct HabitTally: Equatable, Sendable {
    public var done: Int
    public var scheduled: Int
    public init(done: Int = 0, scheduled: Int = 0) { self.done = done; self.scheduled = scheduled }
    public var rate: Double { scheduled == 0 ? 0 : Double(done) / Double(scheduled) }
    public static func + (a: HabitTally, b: HabitTally) -> HabitTally {
        HabitTally(done: a.done + b.done, scheduled: a.scheduled + b.scheduled)
    }
}

public struct HabitInput: Equatable, Sendable, Identifiable {
    public var id: UUID { taskID }
    public var taskID: UUID
    public var title: String
    public var habit: TaskHabit
    public init(taskID: UUID, title: String, habit: TaskHabit) {
        self.taskID = taskID; self.title = title; self.habit = habit
    }
}

public struct HabitReportRow: Equatable, Sendable, Identifiable {
    public var taskID: UUID
    public var title: String
    public var rate: Double
    public var currentStreak: Int
    public var longestStreak: Int
    public var doneDays: Int
    public var eye: HabitEyeStage
    public var id: UUID { taskID }
}

public struct HabitMonthRate: Equatable, Sendable, Identifiable {
    public var monthStart: Date
    public var tally: HabitTally
    public var rate: Double { tally.rate }
    public var id: Date { monthStart }
}

public struct HabitReport: Equatable, Sendable {
    public var days: Int
    public var overallRate: Double
    public var bestCurrentStreak: Int
    public var bestStreakEye: HabitEyeStage
    public var totalDone: Int
    /// Calendar weekday number (1...7) with the best done rate, nil if no data.
    public var strongestWeekday: Int?
    public var weekdayRates: [Int: Double]
    public var rows: [HabitReportRow]
    /// Last `months` calendar months, oldest first (aggregate over all habits).
    public var monthlyRates: [HabitMonthRate]

    public static func make(habits: [HabitInput], focusLog: [FocusLogEntry], checks: [HabitCheck],
                            days: Int, months: Int = 6, today: Date, calendar: Calendar) -> HabitReport {
        let t = calendar.startOfDay(for: today)
        let from = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: t) ?? t
        var total = HabitTally()
        var wd: [Int: HabitTally] = [:]
        var rows: [HabitReportRow] = []
        var totalDone = 0
        for h in habits {
            let tally = HabitEngine.tally(habit: h.habit, taskID: h.taskID, focusLog: focusLog, checks: checks,
                                          from: from, to: t, today: t, calendar: calendar)
            total = total + tally
            for (k, v) in HabitEngine.weekdayTallies(habit: h.habit, taskID: h.taskID, focusLog: focusLog,
                                                    checks: checks, from: from, to: t, today: t, calendar: calendar) {
                wd[k] = (wd[k] ?? HabitTally()) + v
            }
            let doneDays = HabitEngine.doneDayCount(habit: h.habit, taskID: h.taskID, focusLog: focusLog,
                                                    checks: checks, from: from, to: t, today: t, calendar: calendar)
            totalDone += doneDays
            rows.append(HabitReportRow(
                taskID: h.taskID, title: h.title, rate: tally.rate,
                currentStreak: HabitEngine.currentStreak(habit: h.habit, taskID: h.taskID, focusLog: focusLog,
                                                         checks: checks, today: t, calendar: calendar),
                longestStreak: HabitEngine.longestStreak(habit: h.habit, taskID: h.taskID, focusLog: focusLog,
                                                         checks: checks, today: t, calendar: calendar),
                doneDays: doneDays,
                eye: HabitEngine.eyeStage(habit: h.habit, taskID: h.taskID, focusLog: focusLog,
                                          checks: checks, today: t, calendar: calendar)))
        }
        let rates = wd.filter { $0.value.scheduled > 0 }
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        var strongest: Int?
        for d in order {
            guard let v = rates[d] else { continue }
            if strongest == nil || v.rate > rates[strongest!]!.rate { strongest = d }
        }
        let best = rows.max { $0.currentStreak < $1.currentStreak }
        return HabitReport(days: days, overallRate: total.rate,
                           bestCurrentStreak: best?.currentStreak ?? 0,
                           bestStreakEye: best?.eye ?? .dormant,
                           totalDone: totalDone, strongestWeekday: strongest,
                           weekdayRates: rates.mapValues(\.rate), rows: rows,
                           monthlyRates: HabitEngine.monthlyRates(
                               habits: habits, focusLog: focusLog, checks: checks,
                               months: months, today: t, calendar: calendar))
    }
}

/// Pure habit rules. Everything takes `today` and `calendar` explicitly.
public enum HabitEngine {

    // MARK: Day status

    private struct Lookup {
        let pomodoro: [Date: Int]
        let checked: Set<Date>
        let target: Int?
        let calendar: Calendar

        init(habit: TaskHabit, taskID: UUID, focusLog: [FocusLogEntry], checks: [HabitCheck], calendar: Calendar) {
            self.calendar = calendar
            switch habit.mode {
            case .pomodoro(let target):
                self.target = target
                var m: [Date: Int] = [:]
                for e in focusLog where e.taskID == taskID && e.subtaskID == nil {
                    m[calendar.startOfDay(for: e.day), default: 0] += e.count
                }
                pomodoro = m; checked = []
            case .manual:
                target = nil; pomodoro = [:]
                checked = Set(checks.filter { $0.taskID == taskID }.map { calendar.startOfDay(for: $0.day) })
            }
        }

        func isDone(_ day: Date) -> Bool {
            if let target { return (pomodoro[day] ?? 0) >= target }
            return checked.contains(day)
        }
    }

    private static func isScheduled(_ day: Date, _ schedule: HabitSchedule, _ cal: Calendar) -> Bool {
        switch schedule {
        case .daily, .timesPerWeek: return true
        case .weekdays(let set): return set.contains(cal.component(.weekday, from: day))
        }
    }

    private static func status(_ day: Date, _ habit: TaskHabit, _ lookup: Lookup, _ today: Date, _ cal: Calendar) -> HabitDayStatus {
        if day > today { return .future }
        if day < cal.startOfDay(for: habit.startDay) { return .beforeStart }
        guard isScheduled(day, habit.schedule, cal) else { return .notScheduled }
        if lookup.isDone(day) { return .done }
        if day == today { return .pending }
        if case .timesPerWeek = habit.schedule { return .notScheduled }
        return .missed
    }

    public static func status(for day: Date, habit: TaskHabit, taskID: UUID,
                              focusLog: [FocusLogEntry], checks: [HabitCheck],
                              today: Date, calendar: Calendar) -> HabitDayStatus {
        let l = Lookup(habit: habit, taskID: taskID, focusLog: focusLog, checks: checks, calendar: calendar)
        return status(calendar.startOfDay(for: day), habit, l, calendar.startOfDay(for: today), calendar)
    }

    // MARK: Unit results (days, or weeks for timesPerWeek), oldest first

    /// true = unit met, false = unit missed. A pending today / a week that can
    /// still be met is omitted (neither breaks nor extends a streak).
    private static func unitResults(_ habit: TaskHabit, _ lookup: Lookup, _ today: Date, _ cal: Calendar) -> [Bool] {
        let start = cal.startOfDay(for: habit.startDay)
        guard start <= today else { return [] }
        switch habit.schedule {
        case .daily, .weekdays:
            var out: [Bool] = []
            var d = start
            var guardN = 0
            while d <= today, guardN < 20_000 {
                switch status(d, habit, lookup, today, cal) {
                case .done: out.append(true)
                case .missed: out.append(false)
                default: break
                }
                d = cal.date(byAdding: .day, value: 1, to: d) ?? today.addingTimeInterval(86_400)
                guardN += 1
            }
            return out
        case .timesPerWeek(let n):
            var out: [Bool] = []
            guard let firstWeek = cal.dateInterval(of: .weekOfYear, for: start) else { return [] }
            var weekStart = firstWeek.start
            var guardN = 0
            while weekStart <= today, guardN < 3_000 {
                let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) ?? today
                let lastDay = min(cal.date(byAdding: .day, value: -1, to: weekEnd) ?? today, today)
                let firstDay = max(weekStart, start)
                var doneCount = 0, available = 0
                var d = firstDay
                while d <= lastDay {
                    available += 1
                    if lookup.isDone(d) { doneCount += 1 }
                    d = cal.date(byAdding: .day, value: 1, to: d) ?? lastDay.addingTimeInterval(86_400)
                }
                let isCurrent = weekEnd > today
                let after = isCurrent ? daysAfter(today, weekEnd, cal) : 0
                let required = min(n, available + after)
                if doneCount >= required {
                    out.append(true)
                } else if !isCurrent {
                    out.append(false)
                } else {
                    let possible = doneCount + after + (lookup.isDone(today) ? 0 : 1)
                    if possible < required { out.append(false) }
                }
                weekStart = weekEnd
                guardN += 1
            }
            return out
        }
    }

    /// Days strictly after `day` and before `end`.
    private static func daysAfter(_ day: Date, _ end: Date, _ cal: Calendar) -> Int {
        max(0, (cal.dateComponents([.day], from: day, to: end).day ?? 1) - 1)
    }

    // MARK: Streaks

    public static func currentStreak(habit: TaskHabit, taskID: UUID, focusLog: [FocusLogEntry],
                                     checks: [HabitCheck], today: Date, calendar: Calendar) -> Int {
        let l = Lookup(habit: habit, taskID: taskID, focusLog: focusLog, checks: checks, calendar: calendar)
        let r = unitResults(habit, l, calendar.startOfDay(for: today), calendar)
        return r.reversed().prefix { $0 }.count
    }

    public static func longestStreak(habit: TaskHabit, taskID: UUID, focusLog: [FocusLogEntry],
                                     checks: [HabitCheck], today: Date, calendar: Calendar) -> Int {
        let l = Lookup(habit: habit, taskID: taskID, focusLog: focusLog, checks: checks, calendar: calendar)
        var best = 0, run = 0
        for ok in unitResults(habit, l, calendar.startOfDay(for: today), calendar) {
            run = ok ? run + 1 : 0
            best = max(best, run)
        }
        return best
    }

    // MARK: Forgiving eye

    /// Pure eye-stage fold over unit results (oldest first). One miss drops
    /// exactly one stage; two consecutive misses reset to dormant. Honest
    /// streak numbers are unaffected — only the eye is forgiving.
    public static func eyeStage(results: [Bool]) -> HabitEyeStage {
        var streak = 0, floor = HabitEyeStage.dormant, consecutiveMisses = 0
        for ok in results {
            if ok {
                streak += 1; consecutiveMisses = 0
            } else {
                let current = max(HabitEyeStage.stage(forStreak: streak), floor)
                consecutiveMisses += 1
                floor = consecutiveMisses >= 2 ? .dormant : current.lowered
                streak = 0
            }
        }
        return max(HabitEyeStage.stage(forStreak: streak), floor)
    }

    public static func eyeStage(habit: TaskHabit, taskID: UUID, focusLog: [FocusLogEntry],
                                checks: [HabitCheck], today: Date, calendar: Calendar) -> HabitEyeStage {
        let l = Lookup(habit: habit, taskID: taskID, focusLog: focusLog, checks: checks, calendar: calendar)
        return eyeStage(results: unitResults(habit, l, calendar.startOfDay(for: today), calendar))
    }

    // MARK: Rates

    private static func days(from: Date, to: Date, _ cal: Calendar) -> [Date] {
        var out: [Date] = []
        var d = cal.startOfDay(for: from)
        let end = cal.startOfDay(for: to)
        while d <= end, out.count < 20_000 {
            out.append(d)
            d = cal.date(byAdding: .day, value: 1, to: d) ?? end.addingTimeInterval(86_400)
        }
        return out
    }

    /// done / scheduled units in `from...to`. Excludes future, before-start and
    /// a still-pending today. timesPerWeek counts weeks (current week only once
    /// met or no longer reachable).
    public static func tally(habit: TaskHabit, taskID: UUID, focusLog: [FocusLogEntry], checks: [HabitCheck],
                             from: Date, to: Date, today: Date, calendar: Calendar) -> HabitTally {
        let l = Lookup(habit: habit, taskID: taskID, focusLog: focusLog, checks: checks, calendar: calendar)
        let t = calendar.startOfDay(for: today)
        let all = days(from: from, to: min(to, t), calendar)
        switch habit.schedule {
        case .daily, .weekdays:
            var tally = HabitTally()
            for d in all {
                switch status(d, habit, l, t, calendar) {
                case .done: tally.done += 1; tally.scheduled += 1
                case .missed: tally.scheduled += 1
                default: break
                }
            }
            return tally
        case .timesPerWeek(let n):
            let start = calendar.startOfDay(for: habit.startDay)
            var byWeek: [Date: (done: Int, avail: Int)] = [:]
            for d in all where d >= start {
                guard let w = calendar.dateInterval(of: .weekOfYear, for: d)?.start else { continue }
                var e = byWeek[w] ?? (0, 0)
                e.avail += 1
                if l.isDone(d) { e.done += 1 }
                byWeek[w] = e
            }
            var tally = HabitTally()
            let currentWeek = calendar.dateInterval(of: .weekOfYear, for: t)?.start
            for (w, e) in byWeek {
                let req = min(n, e.avail)
                if w == currentWeek && e.done < req { continue }
                tally.scheduled += req
                tally.done += min(e.done, req)
            }
            return tally
        }
    }

    public static func completionRate(habit: TaskHabit, taskID: UUID, focusLog: [FocusLogEntry], checks: [HabitCheck],
                                      from: Date, to: Date, today: Date, calendar: Calendar) -> Double {
        tally(habit: habit, taskID: taskID, focusLog: focusLog, checks: checks,
              from: from, to: to, today: today, calendar: calendar).rate
    }

    /// Per calendar weekday (1...7): done days / scheduled days.
    public static func weekdayTallies(habit: TaskHabit, taskID: UUID, focusLog: [FocusLogEntry], checks: [HabitCheck],
                                      from: Date, to: Date, today: Date, calendar: Calendar) -> [Int: HabitTally] {
        let l = Lookup(habit: habit, taskID: taskID, focusLog: focusLog, checks: checks, calendar: calendar)
        let t = calendar.startOfDay(for: today)
        var out: [Int: HabitTally] = [:]
        for d in days(from: from, to: min(to, t), calendar) {
            let wd = calendar.component(.weekday, from: d)
            var timesPerWeekMiss = false
            if case .timesPerWeek = habit.schedule, d != t, d >= calendar.startOfDay(for: habit.startDay), !l.isDone(d) {
                timesPerWeekMiss = true
            }
            switch status(d, habit, l, t, calendar) {
            case .done: out[wd, default: HabitTally()] = (out[wd] ?? HabitTally()) + HabitTally(done: 1, scheduled: 1)
            case .missed: out[wd, default: HabitTally()] = (out[wd] ?? HabitTally()) + HabitTally(done: 0, scheduled: 1)
            default:
                if timesPerWeekMiss { out[wd] = (out[wd] ?? HabitTally()) + HabitTally(done: 0, scheduled: 1) }
            }
        }
        return out
    }

    public static func weekdayRates(habit: TaskHabit, taskID: UUID, focusLog: [FocusLogEntry], checks: [HabitCheck],
                                    from: Date, to: Date, today: Date, calendar: Calendar) -> [Int: Double] {
        weekdayTallies(habit: habit, taskID: taskID, focusLog: focusLog, checks: checks,
                       from: from, to: to, today: today, calendar: calendar)
            .filter { $0.value.scheduled > 0 }.mapValues(\.rate)
    }

    /// Number of days counted done in the range (scheduled or, for perWeek, any).
    public static func doneDayCount(habit: TaskHabit, taskID: UUID, focusLog: [FocusLogEntry], checks: [HabitCheck],
                                    from: Date, to: Date, today: Date, calendar: Calendar) -> Int {
        let l = Lookup(habit: habit, taskID: taskID, focusLog: focusLog, checks: checks, calendar: calendar)
        let t = calendar.startOfDay(for: today)
        let start = calendar.startOfDay(for: habit.startDay)
        return days(from: from, to: min(to, t), calendar)
            .filter { $0 >= start && isScheduled($0, habit.schedule, calendar) && l.isDone($0) }.count
    }

    /// Aggregate done/scheduled per calendar month for the last `months`
    /// months (current month included, up to today), oldest first.
    public static func monthlyRates(habits: [HabitInput], focusLog: [FocusLogEntry], checks: [HabitCheck],
                                    months: Int, today: Date, calendar: Calendar) -> [HabitMonthRate] {
        let t = calendar.startOfDay(for: today)
        guard months > 0, let thisMonth = calendar.dateInterval(of: .month, for: t)?.start else { return [] }
        return (0..<months).reversed().compactMap { back in
            guard let start = calendar.date(byAdding: .month, value: -back, to: thisMonth),
                  let next = calendar.date(byAdding: .month, value: 1, to: start),
                  let last = calendar.date(byAdding: .day, value: -1, to: next) else { return nil }
            var total = HabitTally()
            for h in habits {
                total = total + tally(habit: h.habit, taskID: h.taskID, focusLog: focusLog, checks: checks,
                                      from: start, to: last, today: t, calendar: calendar)
            }
            return HabitMonthRate(monthStart: start, tally: total)
        }
    }

    /// Task-level focus count credited on `day` (pomodoro habits).
    public static func pomodoroCount(taskID: UUID, on day: Date, focusLog: [FocusLogEntry], calendar: Calendar) -> Int {
        let d = calendar.startOfDay(for: day)
        return focusLog.filter { $0.taskID == taskID && $0.subtaskID == nil && calendar.startOfDay(for: $0.day) == d }
            .reduce(0) { $0 + $1.count }
    }

    /// 0...1 progress of one day: pomodoro count / target, or manual tick.
    public static func progress(on day: Date, habit: TaskHabit, taskID: UUID, focusLog: [FocusLogEntry],
                                checks: [HabitCheck], calendar: Calendar) -> Double {
        let d = calendar.startOfDay(for: day)
        switch habit.mode {
        case .pomodoro(let target):
            return min(1, Double(pomodoroCount(taskID: taskID, on: d, focusLog: focusLog, calendar: calendar)) / Double(max(target, 1)))
        case .manual:
            return checks.contains { $0.taskID == taskID && calendar.startOfDay(for: $0.day) == d } ? 1 : 0
        }
    }

    // MARK: Today

    /// True when the habit still needs doing today (badge count).
    public static func isPendingToday(habit: TaskHabit, taskID: UUID, focusLog: [FocusLogEntry],
                                      checks: [HabitCheck], today: Date, calendar: Calendar) -> Bool {
        let t = calendar.startOfDay(for: today)
        guard status(for: t, habit: habit, taskID: taskID, focusLog: focusLog, checks: checks,
                     today: t, calendar: calendar) == .pending else { return false }
        if case .timesPerWeek(let n) = habit.schedule {
            let l = Lookup(habit: habit, taskID: taskID, focusLog: focusLog, checks: checks, calendar: calendar)
            guard let w = calendar.dateInterval(of: .weekOfYear, for: t) else { return true }
            let done = days(from: max(w.start, calendar.startOfDay(for: habit.startDay)), to: t, calendar)
                .filter(l.isDone).count
            return done < n
        }
        return true
    }
}
