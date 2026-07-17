import Foundation

/// Due dates carry an *optional* time of day. The time is not a separate stored
/// flag — a due parked at exactly midnight (00:00:00) is the date-only form,
/// "this day, no particular time". Date pickers store this form when the user
/// picks a day without choosing a time; quick-add ("5pm") stores a real time.
///
/// Every place that displays or reasons about a due funnels through here so the
/// convention stays in one spot: date-only dues hide the clock and only count
/// as overdue once their whole day has passed.
public enum DueDate {
    /// True when `date` has no time of day (midnight) — a date-only deadline.
    public static func isDateOnly(_ date: Date, calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return (c.hour ?? 0) == 0 && (c.minute ?? 0) == 0 && (c.second ?? 0) == 0
    }

    /// The date-only (midnight) form of `date` — drops the time of day.
    public static func dateOnly(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    /// The moment a deadline actually expires. A date-only due expires at the
    /// *end* of its day, which is what `TaskItem.isOverdue()` already assumes —
    /// so a deadline set for today doesn't read as late from midnight on.
    public static func expiry(_ date: Date, calendar: Calendar = .current) -> Date {
        guard isDateOnly(date, calendar: calendar) else { return date }
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
    }

    /// Time left until a deadline, worded for a chip: "3d 4h left", "2h 15m
    /// left", "8m left" — coarse-to-fine, never more than two units. Once the
    /// deadline has passed it counts up instead: "2d late".
    public static func countdown(to date: Date, now: Date = Date(),
                                 calendar: Calendar = .current) -> String {
        let seconds = Int(expiry(date, calendar: calendar).timeIntervalSince(now))
        let late = seconds < 0
        let total = abs(seconds)

        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60

        let amount: String
        if days > 0 { amount = hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        else if hours > 0 { amount = minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        else if minutes > 0 { amount = "\(minutes)m" }
        else { return late ? "just late" : "due now" }

        return late ? "\(amount) late" : "\(amount) left"
    }
}
