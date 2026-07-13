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

/// Turns a quick-add line like `ertaga 15:00 p1 #ish @sharingan ~2 hisobot yozish`
/// into structured task fields, in the world's 25 most-spoken languages at once
/// (see `LocalizedKeywords`). Pure — pass `now` for deterministic tests.
///
/// Matching runs in two passes because scripts differ:
/// 1. **CJK substring scan.** Chinese/Japanese don't put spaces between words, so
///    `明天开会` ("tomorrow meeting") is scanned character-by-character for the
///    longest keyword; matched spans are lifted out and the rest is the title.
/// 2. **Token scan.** The remaining (space-delimited) text is walked token by
///    token: multi-word phrases first, then symbol tokens (`#tag @proj ~2 p1`,
///    `15:00`, `12.08`), then compositional `every N days` / `in N hours`, then
///    single-word keywords. Anything unmatched is kept as the title.
///
/// A leading `\` escapes parsing: the rest of the line is the literal title.
public enum TaskInputParser {

    public static func parse(_ raw: String, now: Date = Date()) -> ParsedTaskInput {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("\\") {
            return ParsedTaskInput(title: String(trimmed.dropFirst())
                .trimmingCharacters(in: .whitespaces))
        }

        var result = ParsedTaskInput()
        var datePart: DateComponents?          // day-level phrase (bugun, friday, 12.08)
        var timePart: (hour: Int, minute: Int)?
        var offsetDue: Date?                    // absolute due from "in N hours/days"

        // Normalize the apostrophe forms so "aujourd'hui" etc. match, and the
        // smart quotes the timer parser also handles.
        let working0 = trimmed
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")

        // Pass 1 — pull CJK keywords out of the (space-less) text.
        var working = working0
        for concept in scanCJK(&working) {
            apply(concept, &result, &datePart, &timePart, now: now)
        }

        // Pass 2 — walk the space-delimited remainder.
        let words = working.split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        var kept: [String] = []
        var i = 0
        while i < words.count {
            let word = words[i]
            let lower = word.lowercased()

            // Multi-word keyword phrases (e.g. "next week", "har kuni",
            // "ish kunlari", "ngày mai") — longest match first.
            if let (concept, consumed) = matchPhrase(words, at: i) {
                apply(concept, &result, &datePart, &timePart, now: now)
                i += consumed; continue
            }

            if lower.hasPrefix("#"), word.count > 1 {
                result.tags.append(String(word.dropFirst()))
                i += 1; continue
            }
            if lower.hasPrefix("@"), word.count > 1 {
                if result.project == nil { result.project = String(word.dropFirst()) }
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
            if let dc = numericDayMonth(lower, now: now) {
                datePart = dc
                i += 1; continue
            }
            if let t = timePhrase(lower) {
                timePart = t
                i += 1; continue
            }

            // Month-name dates: "march 5" / "5 march" / "5-mart" (either order).
            if let m = lookups.monthName[lower], i + 1 < words.count,
               let d = dayNumber(words[i + 1]) {
                datePart = monthDay(day: d, month: m, now: now)
                i += 2; continue
            }
            if let d = dayNumber(lower), i + 1 < words.count,
               let m = lookups.monthName[words[i + 1].lowercased()] {
                datePart = monthDay(day: d, month: m, now: now)
                i += 2; continue
            }

            // Compositional: "every N days" (recurrence) and "in N hours"
            // (a due offset). Markers only fire with a valid number + unit
            // after them, so a bare "in"/"every" stays in the title.
            if lookups.every.contains(lower),
               let (rec, consumed) = matchEvery(words, at: i) {
                result.recurrence = rec
                i += consumed; continue
            }
            if lookups.within.contains(lower),
               let (date, consumed) = matchWithin(words, at: i, now: now) {
                offsetDue = date
                i += consumed; continue
            }
            // Postpositional offset: "2 soatdan keyin", "2 saat sonra",
            // "2 घंटे में" — [number] [unit] [marker].
            if let (date, consumed) = matchPostpositionalOffset(words, at: i, now: now) {
                offsetDue = date
                i += consumed; continue
            }

            // Single-word keywords.
            if let w = lookups.singleDay[lower] {
                datePart = components(for: w, now: now)
                i += 1; continue
            }
            if let t = lookups.singleTime[lower] {
                timePart = t
                i += 1; continue
            }
            if let r = lookups.singleRecur[lower] {
                result.recurrence = r
                i += 1; continue
            }
            if let p = lookups.singlePriority[lower] {
                result.priority = p
                i += 1; continue
            }

            kept.append(word)
            i += 1
        }

        result.title = kept.joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        result.dueDate = combine(datePart, timePart, now: now) ?? offsetDue
        return result
    }

    // MARK: - Concepts

    /// A day-level phrase the parser can recognize across languages.
    enum DayWord: Equatable {
        case today, tomorrow, dayAfterTomorrow, yesterday
        case nextWeek, nextMonth, nextYear, thisWeek, weekend
        case weekday(Int)   // Calendar weekday number, 1 = Sunday … 7 = Saturday
    }

    /// What a matched keyword means. `recur`/`priority` never touch the date;
    /// `time` sets only the clock, so "tomorrow evening" keeps both.
    enum Concept {
        case day(DayWord)
        case time(Int, Int)     // hour, minute — a part-of-day word
        case recur(Recurrence)
        case priority(TaskPriority)
    }

    private static func apply(_ concept: Concept,
                              _ result: inout ParsedTaskInput,
                              _ datePart: inout DateComponents?,
                              _ timePart: inout (hour: Int, minute: Int)?,
                              now: Date) {
        switch concept {
        case .day(let w):      datePart = components(for: w, now: now)
        case .time(let h, let m): timePart = (h, m)
        case .recur(let r):    result.recurrence = r
        case .priority(let p): result.priority = p
        }
    }

    // MARK: - Token helpers

    private static func priorityToken(_ w: String) -> TaskPriority? {
        switch w {
        case "p1": return .high
        case "p2": return .medium
        case "p3": return .low
        case "p4": return TaskPriority.none
        default:   return nil
        }
    }

    /// `12.08` / `12/08` — day.month, next occurrence (this year or next).
    private static func numericDayMonth(_ w: String, now: Date) -> DateComponents? {
        let cal = Calendar.current
        let parts = w.split(whereSeparator: { $0 == "." || $0 == "/" })
        guard parts.count == 2,
              let day = Int(parts[0]), let month = Int(parts[1]),
              (1...31).contains(day), (1...12).contains(month) else { return nil }
        var c = cal.dateComponents([.year], from: now)
        c.day = day; c.month = month
        if let candidate = cal.date(from: c), candidate < cal.startOfDay(for: now) {
            c.year! += 1
        }
        guard cal.date(from: c) != nil else { return nil }
        return c
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
            return ((hour % 12) + pmShift, minute)
        }
        return (hour, minute)
    }

    /// Longest multi-word phrase starting at `i` (lower-cased comparison).
    private static func matchPhrase(_ words: [String], at i: Int) -> (Concept, Int)? {
        for entry in lookups.phrases {   // pre-sorted: most tokens first
            let n = entry.tokens.count
            guard i + n <= words.count else { continue }
            var ok = true
            for k in 0..<n where words[i + k].lowercased() != entry.tokens[k] {
                ok = false; break
            }
            if ok { return (entry.concept, n) }
        }
        return nil
    }

    /// `every [N] <unit>` → recurrence. `every day/week` and `every N days`.
    private static func matchEvery(_ words: [String], at i: Int) -> (Recurrence, Int)? {
        guard i + 1 < words.count else { return nil }
        let next = words[i + 1].lowercased()
        if lookups.dayUnit.contains(next)  { return (.daily, 2) }
        if lookups.weekUnit.contains(next) { return (.weekly, 2) }
        // "every 3 days" — number then a day unit.
        if let n = Int(next), n > 0, i + 2 < words.count,
           lookups.dayUnit.contains(words[i + 2].lowercased()) {
            return (.everyNDays(n), 3)
        }
        return nil
    }

    /// `in N <unit>` → an absolute due date `N` units from `now` (marker-led).
    private static func matchWithin(_ words: [String], at i: Int, now: Date) -> (Date, Int)? {
        guard i + 2 < words.count, let n = Int(words[i + 1]), n > 0 else { return nil }
        return offsetDate(n: n, unit: words[i + 2].lowercased(), now: now).map { ($0, 3) }
    }

    /// `N <unit> <marker>` → an absolute due date (postpositional languages:
    /// Uzbek "2 soatdan keyin", Turkish "2 saat sonra", Hindi "2 घंटे में").
    private static func matchPostpositionalOffset(_ words: [String], at i: Int, now: Date) -> (Date, Int)? {
        guard let n = Int(words[i]), n > 0, i + 2 < words.count,
              lookups.after.contains(words[i + 2].lowercased()) else { return nil }
        return offsetDate(n: n, unit: words[i + 1].lowercased(), now: now).map { ($0, 3) }
    }

    /// `now` shifted by `n` of the given unit word, or nil if the word is not a
    /// known time unit in any language.
    private static func offsetDate(n: Int, unit: String, now: Date) -> Date? {
        let cal = Calendar.current
        if lookups.minuteUnit.contains(unit) { return cal.date(byAdding: .minute, value: n, to: now) }
        if lookups.hourUnit.contains(unit)   { return cal.date(byAdding: .hour, value: n, to: now) }
        if lookups.dayUnit.contains(unit)    { return cal.date(byAdding: .day, value: n, to: now) }
        if lookups.weekUnit.contains(unit)   { return cal.date(byAdding: .day, value: n * 7, to: now) }
        if lookups.monthUnit.contains(unit)  { return cal.date(byAdding: .month, value: n, to: now) }
        if lookups.yearUnit.contains(unit)   { return cal.date(byAdding: .year, value: n, to: now) }
        return nil
    }

    /// A plausible day-of-month number, tolerating an English ordinal suffix
    /// ("5th", "3rd", "1st", "22nd").
    private static func dayNumber(_ token: String) -> Int? {
        var s = token.lowercased()
        for suffix in ["st", "nd", "rd", "th"] where s.hasSuffix(suffix) && s.count > 2 {
            s = String(s.dropLast(2)); break
        }
        guard let n = Int(s), (1...31).contains(n) else { return nil }
        return n
    }

    /// A day + month → the next such date (this year, or next if already past).
    private static func monthDay(day: Int, month: Int, now: Date) -> DateComponents {
        let cal = Calendar.current
        var c = cal.dateComponents([.year], from: now)
        c.day = day; c.month = month
        if let candidate = cal.date(from: c), candidate < cal.startOfDay(for: now) {
            c.year! += 1
        }
        return c
    }

    // MARK: - CJK substring scan

    /// Whether a scalar belongs to a script that is written without spaces
    /// between words (so it must be matched by substring, not by token).
    /// Hiragana, Katakana, and CJK ideographs — deliberately NOT Hangul, which
    /// spaces its words and so goes through the normal token path.
    static func isSpacelessScript(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF,   // Hiragana + Katakana
             0x3400...0x4DBF,   // CJK Extension A
             0x4E00...0x9FFF,   // CJK Unified Ideographs
             0xF900...0xFAFF:   // CJK Compatibility Ideographs
            return true
        default:
            return false
        }
    }

    private static func containsSpacelessScript(_ s: String) -> Bool {
        s.unicodeScalars.contains(where: isSpacelessScript)
    }

    /// Lift every CJK keyword out of `text` (longest match wins), replacing each
    /// with a space so neighbours don't fuse and the leftover becomes the title.
    private static func scanCJK(_ text: inout String) -> [Concept] {
        guard containsSpacelessScript(text) else { return [] }
        let chars = Array(text)
        var out: [Character] = []
        var concepts: [Concept] = []
        var idx = 0
        while idx < chars.count {
            var matched = false
            if let bucket = lookups.cjkByFirst[chars[idx]] {
                for entry in bucket {   // pre-sorted: longest surface first
                    let n = entry.surface.count
                    if idx + n <= chars.count,
                       Array(chars[idx..<idx + n]) == entry.surface {
                        concepts.append(entry.concept)
                        out.append(" ")
                        idx += n
                        matched = true
                        break
                    }
                }
            }
            if !matched {
                out.append(chars[idx])
                idx += 1
            }
        }
        text = String(out)
        return concepts
    }

    // MARK: - Date assembly

    private static func components(for w: DayWord, now: Date) -> DateComponents {
        let cal = Calendar.current
        func day(_ offset: Int) -> DateComponents {
            let d = cal.date(byAdding: .day, value: offset, to: now)!
            return cal.dateComponents([.year, .month, .day], from: d)
        }
        switch w {
        case .today:             return day(0)
        case .tomorrow:          return day(1)
        case .dayAfterTomorrow:  return day(2)
        case .yesterday:         return day(-1)
        case .nextWeek:          return day(7)
        case .nextMonth:
            let d = cal.date(byAdding: .month, value: 1, to: now)!
            return cal.dateComponents([.year, .month, .day], from: d)
        case .nextYear:
            let d = cal.date(byAdding: .year, value: 1, to: now)!
            return cal.dateComponents([.year, .month, .day], from: d)
        case .thisWeek:          return components(for: .weekday(6), now: now) // this/coming Friday
        case .weekend:           return components(for: .weekday(7), now: now) // coming Saturday
        case .weekday(let target):
            var d = cal.date(byAdding: .day, value: 1, to: now)!
            while cal.component(.weekday, from: d) != target {
                d = cal.date(byAdding: .day, value: 1, to: d)!
            }
            return cal.dateComponents([.year, .month, .day], from: d)
        }
    }

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
            var c = cal.dateComponents([.year, .month, .day], from: now)
            c.hour = t.hour; c.minute = t.minute
            guard let candidate = cal.date(from: c) else { return nil }
            return candidate > now ? candidate
                : cal.date(byAdding: .day, value: 1, to: candidate)
        }
    }

    // MARK: - Lookups (built once from LocalizedKeywords)

    struct Lookups {
        var singleDay: [String: DayWord] = [:]
        var singleTime: [String: (hour: Int, minute: Int)] = [:]
        var singleRecur: [String: Recurrence] = [:]
        var singlePriority: [String: TaskPriority] = [:]
        var monthName: [String: Int] = [:]          // month word → 1…12
        /// Multi-token phrases, sorted with the most tokens first (greedy match).
        var phrases: [(tokens: [String], concept: Concept)] = []
        /// CJK surfaces bucketed by first character, each bucket longest-first.
        var cjkByFirst: [Character: [(surface: [Character], concept: Concept)]] = [:]
        var every: Set<String> = []
        var within: Set<String> = []   // prepositional marker: "in 2 days"
        var after: Set<String> = []    // postpositional marker: "2 soatdan keyin"
        var dayUnit: Set<String> = []
        var weekUnit: Set<String> = []
        var monthUnit: Set<String> = []
        var yearUnit: Set<String> = []
        var hourUnit: Set<String> = []
        var minuteUnit: Set<String> = []
    }

    static let lookups: Lookups = buildLookups()

    private static func buildLookups() -> Lookups {
        var L = Lookups()

        func route(_ surface: String, _ concept: Concept) {
            let s = surface.lowercased()
            guard !s.isEmpty else { return }
            if containsSpacelessScript(s) {
                let chars = Array(s)
                L.cjkByFirst[chars[0], default: []].append((chars, concept))
            } else if s.contains(" ") {
                L.phrases.append((s.split(separator: " ").map(String.init), concept))
            } else {
                switch concept {
                case .day(let w):         L.singleDay[s] = w
                case .time(let h, let m): L.singleTime[s] = (h, m)
                case .recur(let r):       L.singleRecur[s] = r
                case .priority(let p):    L.singlePriority[s] = p
                }
            }
        }

        for lang in LocalizedKeywords.all {
            lang.today.forEach            { route($0, .day(.today)) }
            lang.tomorrow.forEach         { route($0, .day(.tomorrow)) }
            lang.dayAfterTomorrow.forEach { route($0, .day(.dayAfterTomorrow)) }
            lang.yesterday.forEach        { route($0, .day(.yesterday)) }
            lang.nextWeek.forEach         { route($0, .day(.nextWeek)) }
            lang.nextMonth.forEach        { route($0, .day(.nextMonth)) }
            lang.nextYear.forEach         { route($0, .day(.nextYear)) }
            lang.thisWeek.forEach         { route($0, .day(.thisWeek)) }
            lang.weekend.forEach          { route($0, .day(.weekend)) }
            for (idx, synonyms) in lang.weekdays.enumerated() {
                synonyms.forEach { route($0, .day(.weekday(idx + 1))) }
            }
            // Parts of day → a default clock time.
            lang.morning.forEach    { route($0, .time(9, 0)) }
            lang.noon.forEach       { route($0, .time(12, 0)) }
            lang.afternoon.forEach  { route($0, .time(15, 0)) }
            lang.evening.forEach    { route($0, .time(18, 0)) }
            lang.nightTime.forEach  { route($0, .time(20, 0)) }
            lang.midnight.forEach   { route($0, .time(0, 0)) }

            lang.daily.forEach          { route($0, .recur(.daily)) }
            lang.weekly.forEach         { route($0, .recur(.weekly)) }
            lang.monthly.forEach        { route($0, .recur(.monthly(1))) }
            lang.weekdaysRecur.forEach  { route($0, .recur(.weekdays)) }
            lang.priorityHigh.forEach   { route($0, .priority(.high)) }

            // Month names → 1…12 (single-token, non-CJK only; used with an
            // adjacent day number so bare "may"/"march" stay as title words).
            for (idx, synonyms) in lang.months.enumerated() {
                for name in synonyms {
                    let s = name.lowercased()
                    if !s.isEmpty, !s.contains(" "), !containsSpacelessScript(s) {
                        L.monthName[s] = idx + 1
                    }
                }
            }

            lang.every.forEach      { L.every.insert($0.lowercased()) }
            lang.within.forEach     { L.within.insert($0.lowercased()) }
            lang.after.forEach      { L.after.insert($0.lowercased()) }
            lang.dayUnit.forEach    { L.dayUnit.insert($0.lowercased()) }
            lang.weekUnit.forEach   { L.weekUnit.insert($0.lowercased()) }
            lang.monthUnit.forEach  { L.monthUnit.insert($0.lowercased()) }
            lang.yearUnit.forEach   { L.yearUnit.insert($0.lowercased()) }
            lang.hourUnit.forEach   { L.hourUnit.insert($0.lowercased()) }
            lang.minuteUnit.forEach { L.minuteUnit.insert($0.lowercased()) }
        }

        L.phrases.sort { $0.tokens.count > $1.tokens.count }
        for key in L.cjkByFirst.keys {
            L.cjkByFirst[key]?.sort { $0.surface.count > $1.surface.count }
        }
        return L
    }
}
