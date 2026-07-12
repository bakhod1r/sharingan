import Foundation

/// A parsed `sharingan://` URL — the automation surface for Shortcuts,
/// Raycast, browsers and scripts (`open "sharingan://start?minutes=25"`).
/// App Intents aren't available in a pure-SwiftPM app, so the URL scheme is
/// the substitute.
public enum URLCommand: Equatable, Sendable {
    /// `sharingan://start` (default duration), `?minutes=25`, or `?input=5pm`
    /// (natural language — durations or clock targets). The associated value
    /// is the session length in seconds; nil keeps the configured duration.
    case start(TimeInterval?)
    case pause
    case resume
    case skip
    case reset
    /// `sharingan://add-task?text=ertaga%20p1%20hisobot` — the text goes
    /// through TaskInputParser downstream, exactly like CLI/quick-add.
    case addTask(String)
    /// `sharingan://toggle-floating`
    case toggleFloating
    /// `sharingan://show` — open the main window.
    case show
}

/// Pure URL → URLCommand mapper. Host names the command; query items carry
/// the arguments. Anything unrecognized parses to nil so callers can ignore
/// malformed/hostile URLs wholesale.
public enum URLCommandRouter {
    public static func parse(_ url: URL, now: Date = Date()) -> URLCommand? {
        guard url.scheme?.lowercased() == "sharingan",
              let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        let query = queryItems(of: url)

        switch host {
        case "start":          return parseStart(query, now: now)
        case "pause":          return .pause
        case "resume":         return .resume
        case "skip":           return .skip
        case "reset":          return .reset
        case "show":           return .show
        case "toggle-floating": return .toggleFloating
        case "add-task":
            guard let text = query["text"]?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            return .addTask(text)
        default:
            return nil
        }
    }

    /// `minutes` (positive number → seconds) wins over `input` (natural
    /// language via NaturalLanguageParser); a present-but-invalid argument
    /// rejects the whole URL rather than silently starting a default session.
    private static func parseStart(_ query: [String: String],
                                   now: Date) -> URLCommand? {
        if let raw = query["minutes"] {
            guard let mins = Double(raw), mins > 0 else { return nil }
            return .start(mins * 60)
        }
        if let input = query["input"] {
            guard let parsed = NaturalLanguageParser.parse(input, now: now) else {
                return nil
            }
            switch parsed.kind {
            case .setDuration(let d) where d > 0:
                return .start(d)
            case .setTargetTime(let target):
                let interval = target.timeIntervalSince(now)
                return interval > 0 ? .start(interval) : nil
            default:
                return nil
            }
        }
        return .start(nil)
    }

    /// Percent-decoded query items, first occurrence wins.
    private static func queryItems(of url: URL) -> [String: String] {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems else { return [:] }
        var out: [String: String] = [:]
        for item in items where out[item.name] == nil {
            out[item.name] = item.value ?? ""
        }
        return out
    }
}
