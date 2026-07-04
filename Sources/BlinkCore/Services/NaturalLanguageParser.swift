import Foundation

public struct ParsedTimerInput: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case setDuration(TimeInterval)
        case setTargetTime(Date)
        case addTime(TimeInterval)
        case removeTime(TimeInterval)
    }

    public let kind: Kind

    public init(kind: Kind) { self.kind = kind }
}

public enum NaturalLanguageParser {
    public static func parse(_ raw: String,
                             now: Date = Date()) -> ParsedTimerInput? {
        let text = raw.lowercased()
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if text == "reset" || text == "stop" {
            return ParsedTimerInput(kind: .setDuration(0))
        }

        // Clock targets (e.g. "5pm", "2:15am") take precedence over bare
        // duration parsing, since the duration parser would otherwise
        // greedily eat the leading number.
        if looksLikeClockTarget(text),
           let target = parseClockTarget(text, now: now) {
            return ParsedTimerInput(kind: .setTargetTime(target))
        }

        let (sign, rest) = parseOffset(text, now: now)
        let trimmedLow = rest.lowercased()
        let isOffset = sign != 0
            || trimmedLow.hasPrefix("add ")
            || trimmedLow.hasPrefix("remove ")
            || trimmedLow.hasPrefix("+")
            || trimmedLow.hasPrefix("-")
        if isOffset {
            if let r = parseDeltaDirective(rest), r > 0 {
                return sign < 0
                    ? ParsedTimerInput(kind: .removeTime(r))
                    : ParsedTimerInput(kind: .addTime(r))
            }
        }

        if let dur = parseDuration(text), dur > 0 {
            return ParsedTimerInput(kind: .setDuration(dur))
        }
        if let dur = parseDuration(rest), dur > 0 {
            return ParsedTimerInput(kind: .setDuration(dur))
        }
        return nil
    }

    private static func parseDuration(_ s: String) -> TimeInterval? {
        if s.isEmpty { return nil }
        var hours: Double = 0
        var minutes: Double = 0
        var seconds: Double = 0

        let pattern = #"(\d+(?:\.\d+)?)\s*(h|hr|hour|hours|m|min|mins|minute|minutes|s|sec|secs|second|seconds)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                   options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(s.startIndex..., in: s)
        let matches = regex.matches(in: s, options: [], range: range)
        guard !matches.isEmpty else { return nil }

        var matched = true
        for m in matches {
            let nRange = m.range(at: 1)
            let uRange = m.range(at: 2)
            guard let nr = Range(nRange, in: s), let number = Double(s[nr]) else {
                matched = false; break
            }
            let unitStr = (Range(uRange, in: s).map { String(s[$0]) } ?? "min").lowercased()
            switch unitStr.prefix(1) {
            case "h": hours += number
            case "m": minutes += number
            case "s": seconds += number
            default: minutes += number
            }
        }
        guard matched else { return nil }

        let total = hours * 3600 + minutes * 60 + seconds
        return total > 0 ? total : nil
    }

    private static func parseClockTarget(_ s: String, now: Date) -> Date? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current

        for format in ["h:mma", "h:mm a", "ha", "h a", "H:mm", "HH:mm"] {
            f.dateFormat = format
            if let d = f.date(from: trimmed) {
                let cal = Calendar.current
                let comps = cal.dateComponents([.hour, .minute, .second], from: d)
                var targetComps = cal.dateComponents([.year, .month, .day], from: now)
                targetComps.hour = comps.hour
                targetComps.minute = comps.minute
                targetComps.second = comps.second ?? 0
                if let target = cal.date(from: targetComps) {
                    if target <= now {
                        return target.addingTimeInterval(86400)
                    }
                    return target
                }
            }
        }
        return nil
    }

    private static func looksLikeClockTarget(_ text: String) -> Bool {
        let trimmed = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("am") || trimmed.hasSuffix("pm") { return true }
        // "h:mm" / "hh:mm" without am/pm could also be a target, but ambiguous
        // with durations like "2:30" — only treat as clock if it ends in am/pm.
        return false
    }

    private static func parseOffset(_ text: String, now: Date) -> (Int, String) {
        var working = text
        let lower = working.lowercased()
        if lower.hasPrefix("add ") {
            working = String(working.dropFirst(4))
            return (1, working)
        }
        if lower.hasPrefix("remove ") {
            working = String(working.dropFirst(7))
            return (-1, working)
        }
        if lower.hasPrefix("+") {
            working = String(working.dropFirst()).trimmingCharacters(in: .whitespaces)
            return (1, working)
        }
        if lower.hasPrefix("-") {
            working = String(working.dropFirst()).trimmingCharacters(in: .whitespaces)
            return (-1, working)
        }
        return (0, working)
    }

    private static func parseDeltaDirective(_ s: String) -> TimeInterval? {
        let cleaned = s
            .replacingOccurrences(of: "minutes", with: "min",
                                  options: .caseInsensitive)
            .replacingOccurrences(of: "minute", with: "min",
                                  options: .caseInsensitive)
            .replacingOccurrences(of: "hours", with: "h",
                                  options: .caseInsensitive)
            .replacingOccurrences(of: "hour", with: "h",
                                  options: .caseInsensitive)
            .replacingOccurrences(of: "seconds", with: "s",
                                  options: .caseInsensitive)
            .replacingOccurrences(of: "second", with: "s",
                                  options: .caseInsensitive)
            .replacingOccurrences(of: " ", with: "")
        return parseDuration(cleaned)
    }
}