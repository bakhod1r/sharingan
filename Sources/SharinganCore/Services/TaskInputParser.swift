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
            apply(concept, &result, &datePart, now: now)
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
                apply(concept, &result, &datePart, now: now)
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

            // Single-word keywords.
            if let w = lookups.singleDay[lower] {
                datePart = components(for: w, now: now)
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
        case today, tomorrow, dayAfterTomorrow, yesterday, nextWeek
        case weekday(Int)   // Calendar weekday number, 1 = Sunday … 7 = Saturday
    }

    /// What a matched keyword means. `recur`/`priority` never touch the date.
    enum Concept {
        case day(DayWord)
        case recur(Recurrence)
        case priority(TaskPriority)
    }

    private static func apply(_ concept: Concept,
                              _ result: inout ParsedTaskInput,
                              _ datePart: inout DateComponents?,
                              now: Date) {
        switch concept {
        case .day(let w):      datePart = components(for: w, now: now)
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

    /// `in N <unit>` → an absolute due date `N` units from `now`.
    private static func matchWithin(_ words: [String], at i: Int, now: Date) -> (Date, Int)? {
        guard i + 2 < words.count, let n = Int(words[i + 1]), n > 0 else { return nil }
        let unit = words[i + 2].lowercased()
        let cal = Calendar.current
        let date: Date?
        if lookups.dayUnit.contains(unit)         { date = cal.date(byAdding: .day, value: n, to: now) }
        else if lookups.weekUnit.contains(unit)   { date = cal.date(byAdding: .day, value: n * 7, to: now) }
        else if lookups.hourUnit.contains(unit)   { date = cal.date(byAdding: .hour, value: n, to: now) }
        else if lookups.minuteUnit.contains(unit) { date = cal.date(byAdding: .minute, value: n, to: now) }
        else { return nil }
        return date.map { ($0, 3) }
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
        var singleRecur: [String: Recurrence] = [:]
        var singlePriority: [String: TaskPriority] = [:]
        /// Multi-token phrases, sorted with the most tokens first (greedy match).
        var phrases: [(tokens: [String], concept: Concept)] = []
        /// CJK surfaces bucketed by first character, each bucket longest-first.
        var cjkByFirst: [Character: [(surface: [Character], concept: Concept)]] = [:]
        var every: Set<String> = []
        var within: Set<String> = []
        var dayUnit: Set<String> = []
        var weekUnit: Set<String> = []
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
                case .day(let w):      L.singleDay[s] = w
                case .recur(let r):    L.singleRecur[s] = r
                case .priority(let p): L.singlePriority[s] = p
                }
            }
        }

        for lang in LocalizedKeywords.all {
            lang.today.forEach            { route($0, .day(.today)) }
            lang.tomorrow.forEach         { route($0, .day(.tomorrow)) }
            lang.dayAfterTomorrow.forEach { route($0, .day(.dayAfterTomorrow)) }
            lang.yesterday.forEach        { route($0, .day(.yesterday)) }
            lang.nextWeek.forEach         { route($0, .day(.nextWeek)) }
            for (idx, synonyms) in lang.weekdays.enumerated() {
                synonyms.forEach { route($0, .day(.weekday(idx + 1))) }
            }
            lang.daily.forEach          { route($0, .recur(.daily)) }
            lang.weekly.forEach         { route($0, .recur(.weekly)) }
            lang.monthly.forEach        { route($0, .recur(.monthly(1))) }
            lang.weekdaysRecur.forEach  { route($0, .recur(.weekdays)) }
            lang.priorityHigh.forEach   { route($0, .priority(.high)) }

            lang.every.forEach      { L.every.insert($0.lowercased()) }
            lang.within.forEach     { L.within.insert($0.lowercased()) }
            lang.dayUnit.forEach    { L.dayUnit.insert($0.lowercased()) }
            lang.weekUnit.forEach   { L.weekUnit.insert($0.lowercased()) }
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
