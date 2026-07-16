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
}
