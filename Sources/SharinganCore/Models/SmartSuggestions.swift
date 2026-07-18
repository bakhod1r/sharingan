import Foundation

/// Templated, rule-based insights from the stats + session log — pure and
/// unit-tested. Returns at most `limit` short strings, most useful first.
public enum SmartSuggestions {
    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h a"; return f
    }()

    public static func insights(stats: PomodoroStats, sessions: [SessionRecord],
                                now: Date = Date(), limit: Int = 2) -> [String] {
        var out: [String] = []
        let cal = Calendar.current

        // Best focus hour (from the aggregate stats).
        if let hour = stats.bestFocusHour,
           let date = cal.date(bySettingHour: hour, minute: 0, second: 0, of: now) {
            out.append("You usually focus best around \(hourFormatter.string(from: date)).")
        }

        // Best weekday.
        if let wd = stats.bestWeekday {
            let names = ["Monday", "Tuesday", "Wednesday", "Thursday",
                         "Friday", "Saturday", "Sunday"]
            out.append("\(names[wd]) is your most productive day.")
        }

        // Break-skipping nudge (recent sessions).
        let breaks = sessions.filter { $0.phase.isBreak }
        if breaks.count >= 4 {
            let skipped = breaks.filter { !$0.completed }.count
            if Double(skipped) / Double(breaks.count) > 0.4 {
                out.append("Try taking your breaks — you've skipped \(skipped) of your last \(breaks.count).")
            }
        }

        // Abandoned-session nudge.
        let focus = sessions.filter { $0.phase == .focus }
        if focus.count >= 5 {
            let abandoned = focus.filter { !$0.completed }.count
            if Double(abandoned) / Double(focus.count) > 0.3 {
                out.append("Several focus sessions ended early — consider a shorter pomodoro size.")
            }
        }

        return Array(out.prefix(limit))
    }
}
