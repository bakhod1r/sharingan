import Foundation

/// Result of parsing one composer line into task fields.
public struct ParsedTaskInput: Equatable, Sendable {
    public var title: String
    public var tags: [String]
    public var project: String?
    public var priority: TaskPriority
    public var dueDate: Date?
    public var estimatedPomodoros: Int?
    public var recurrence: Recurrence

    public init(title: String = "",
                tags: [String] = [],
                project: String? = nil,
                priority: TaskPriority = .none,
                dueDate: Date? = nil,
                estimatedPomodoros: Int? = nil,
                recurrence: Recurrence = .none) {
        self.title = title
        self.tags = tags
        self.project = project
        self.priority = priority
        self.dueDate = dueDate
        self.estimatedPomodoros = estimatedPomodoros
        self.recurrence = recurrence
    }
}

/// Turns a quick-add line like `ertaga 15:00 p1 #ish @blink ~2 hisobot yozish`
/// into structured task fields. Pure — pass `now` for deterministic tests.
/// A leading `\` escapes parsing: the rest of the line is the literal title.
public enum TaskInputParser {

    public static func parse(_ raw: String, now: Date = Date()) -> ParsedTaskInput {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("\\") {
            return ParsedTaskInput(title: String(trimmed.dropFirst())
                .trimmingCharacters(in: .whitespaces))
        }

        var result = ParsedTaskInput()
        let words = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        var kept: [String] = []

        var datePart: DateComponents?   // day-level phrase (today, friday, 12.08)
        var timePart: (hour: Int, minute: Int)?

        var i = 0
        while i < words.count {
            let word = words[i]
            let lower = word.lowercased()

            // Multi-word recurrence phrases first (they'd otherwise be eaten
            // word-by-word): "every N days", "har N kunda", "har kuni",
            // "ish kunlari", "har hafta", "har oy", "every day/week/month".
            if let (rec, consumed) = matchRecurrence(words, at: i) {
                result.recurrence = rec
                i += consumed
                continue
            }

            if lower.hasPrefix("#"), word.count > 1 {
                result.tags.append(String(word.dropFirst()))
                i += 1; continue
            }
            if lower.hasPrefix("@"), word.count > 1 {
                // First @project wins; later ones are treated as consumed
                // tokens (never leak into the title).
                if result.project == nil {
                    result.project = String(word.dropFirst())
                }
                i += 1; continue
            }
            if lower.hasPrefix("~"), let n = Int(word.dropFirst()), n > 0 {
                result.estimatedPomodoros = n
                i += 1; continue
            }
            if let p = priorityToken(lower) {
                result.priority = p
                i += 1; continue
            }
            if let dc = dayPhrase(lower, now: now) {
                datePart = dc
                i += 1; continue
            }
            if let t = timePhrase(lower) {
                timePart = t
                i += 1; continue
            }
            kept.append(word)
            i += 1
        }
        result.title = kept.joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        result.dueDate = combine(datePart, timePart, now: now)
        return result
    }

    // MARK: - Tokens

    private static func priorityToken(_ w: String) -> TaskPriority? {
        switch w {
        case "p1": return .high
        case "p2": return .medium
        case "p3": return .low
        case "p4": return TaskPriority.none
        default:   return nil
        }
    }

    private static let weekdayNames: [String: Int] = [
        // Calendar weekday numbers: 1 = Sunday … 7 = Saturday.
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
        "thursday": 5, "friday": 6, "saturday": 7,
        "yakshanba": 1, "dushanba": 2, "seshanba": 3, "chorshanba": 4,
        "payshanba": 5, "juma": 6, "shanba": 7,
    ]

    /// Day-level phrases: today/bugun, tomorrow/ertaga, weekday names,
    /// `12.08` / `12/08` (day.month).
    private static func dayPhrase(_ w: String, now: Date) -> DateComponents? {
        let cal = Calendar.current
        switch w {
        case "today", "bugun":
            return cal.dateComponents([.year, .month, .day], from: now)
        case "tomorrow", "ertaga":
            let d = cal.date(byAdding: .day, value: 1, to: now)!
            return cal.dateComponents([.year, .month, .day], from: d)
        default:
            break
        }
        if let target = weekdayNames[w] {
            var d = cal.date(byAdding: .day, value: 1, to: now)!
            while cal.component(.weekday, from: d) != target {
                d = cal.date(byAdding: .day, value: 1, to: d)!
            }
            return cal.dateComponents([.year, .month, .day], from: d)
        }
        // 12.08 or 12/08 — day.month, next occurrence (this year or next).
        let parts = w.split(whereSeparator: { $0 == "." || $0 == "/" })
        if parts.count == 2,
           let day = Int(parts[0]), let month = Int(parts[1]),
           (1...31).contains(day), (1...12).contains(month) {
            var c = cal.dateComponents([.year], from: now)
            c.day = day; c.month = month
            if let candidate = cal.date(from: c), candidate < cal.startOfDay(for: now) {
                c.year! += 1
            }
            guard cal.date(from: c) != nil else { return nil }
            return c
        }
        return nil
    }

    /// `15:00`, `9:30`, `5pm`, `11am`.
    private static func timePhrase(_ w: String) -> (hour: Int, minute: Int)? {
        var s = w
        var pmShift = 0
        var isTwelveHour = false
        if s.hasSuffix("pm") { pmShift = 12; isTwelveHour = true; s = String(s.dropLast(2)) }
        else if s.hasSuffix("am") { isTwelveHour = true; s = String(s.dropLast(2)) }

        let parts = s.split(separator: ":")
        let hour: Int, minute: Int
        if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) {
            hour = h; minute = m
        } else if parts.count == 1, isTwelveHour, let h = Int(parts[0]) {
            hour = h; minute = 0
        } else {
            return nil
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        if isTwelveHour {
            guard (1...12).contains(hour) else { return nil }
            let h24 = (hour % 12) + pmShift
            return (h24, minute)
        }
        return (hour, minute)
    }

    private static func matchRecurrence(_ words: [String], at i: Int) -> (Recurrence, Int)? {
        let lower = words[i].lowercased()
        let next = i + 1 < words.count ? words[i + 1].lowercased() : nil
        let third = i + 2 < words.count ? words[i + 2].lowercased() : nil

        switch lower {
        case "daily":    return (.daily, 1)
        case "weekdays": return (.weekdays, 1)
        case "weekly":   return (.weekly, 1)
        case "monthly":  return (.monthly(1), 1)
        case "every":
            guard let next else { return nil }
            switch next {
            case "day":   return (.daily, 2)
            case "week":  return (.weekly, 2)
            case "month": return (.monthly(1), 2)
            default:
                if let n = Int(next), n > 0,
                   let third, third == "days" || third == "day" {
                    return (.everyNDays(n), 3)
                }
                return nil
            }
        case "har":
            guard let next else { return nil }
            switch next {
            case "kuni":  return (.daily, 2)
            case "hafta": return (.weekly, 2)
            case "oy":    return (.monthly(1), 2)
            default:
                if let n = Int(next), n > 0, third == "kunda" {
                    return (.everyNDays(n), 3)
                }
                return nil
            }
        case "ish":
            if next == "kunlari" { return (.weekdays, 2) }
            return nil
        default:
            return nil
        }
    }

    // MARK: - Date assembly

    private static func combine(_ day: DateComponents?,
                                _ time: (hour: Int, minute: Int)?,
                                now: Date) -> Date? {
        let cal = Calendar.current
        switch (day, time) {
        case (nil, nil):
            return nil
        case (let d?, nil):
            var c = d
            c.hour = 9; c.minute = 0
            return cal.date(from: c)
        case (var d?, let t?):
            d.hour = t.hour; d.minute = t.minute
            return cal.date(from: d)
        case (nil, let t?):
            // Bare time: today if still ahead, otherwise tomorrow.
            var c = cal.dateComponents([.year, .month, .day], from: now)
            c.hour = t.hour; c.minute = t.minute
            guard let candidate = cal.date(from: c) else { return nil }
            return candidate > now ? candidate
                : cal.date(byAdding: .day, value: 1, to: candidate)
        }
    }
}
