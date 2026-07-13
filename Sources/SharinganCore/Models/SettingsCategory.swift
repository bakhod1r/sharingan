import Foundation

/// Groups of settings, shown as drill-down rows on the root Settings screen.
/// Lives in Core (not the view) so tier visibility and search stay testable.
public enum SettingsCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case general, timer, tasks, breaks, focus, eyeCare, sharingan, voice, shortcuts

    public var id: String { rawValue }

    /// Simple-tier categories appear in both tiers; advanced-only ones
    /// (Voice, Shortcuts) appear on the root list only in Advanced. Their
    /// one essential control — spoken instructions on/off — is surfaced in
    /// Eye Care for Simple users.
    public var tier: SettingsTier {
        switch self {
        case .voice, .shortcuts: return .advanced
        default:                 return .simple
        }
    }

    /// Whether the category's detail page hides extra rows in Simple
    /// (drives the "More settings in Advanced" footer).
    public var hasAdvancedRows: Bool { self != .general }

    /// Categories for the root list in the given tier.
    public static func visible(in tier: SettingsTier) -> [SettingsCategory] {
        tier == .advanced ? allCases : allCases.filter { $0.tier == .simple }
    }

    public var title: String {
        switch self {
        case .timer:     return "Timer"
        case .tasks:     return "Tasks & Planning"
        case .breaks:    return "Breaks"
        case .focus:     return "Focus & Blocking"
        case .eyeCare:   return "Eye Care"
        case .sharingan: return "Sharingan Eyes"
        case .general:   return "General"
        case .voice:     return "Voice Guidance"
        case .shortcuts: return "Shortcuts"
        }
    }

    public var subtitle: String {
        switch self {
        case .timer:     return "Durations, mode, repeat, floating timer"
        case .tasks:     return "Goal, estimates, weekly planning, badges"
        case .breaks:    return "Break screen, ambience, brightness"
        case .focus:     return "App blocking, reminders"
        case .eyeCare:   return "Exercises, camera tracking"
        case .sharingan: return "Iris style, desktop wallpaper, spin"
        case .general:   return "Theme, auto-start, sound, notifications"
        case .voice:     return "Spoken instructions"
        case .shortcuts: return "Global keyboard shortcuts"
        }
    }

    public var icon: String {
        switch self {
        case .timer:     return "timer"
        case .tasks:     return "checklist"
        case .breaks:    return "cup.and.saucer.fill"
        case .focus:     return "hand.raised.fill"
        case .eyeCare:   return "eye.fill"
        case .sharingan: return "eye.circle.fill"
        case .general:   return "gearshape.fill"
        case .voice:     return "waveform"
        case .shortcuts: return "keyboard.fill"
        }
    }

    /// Extra search terms so a query finds a category by the settings it holds
    /// (e.g. "float" or "opacity" → Timer).
    public var keywords: [String] {
        switch self {
        case .timer:
            return ["duration", "minutes", "pomodoro", "focus length", "mode",
                    "countdown", "count up", "repeat", "endless", "floating",
                    "float", "opacity", "always on top", "compact",
                    "size", "small", "medium", "large", "preset",
                    "dots", "cycle dots", "active task", "task pill",
                    "today panel", "panel", "desktop", "widget"]
        case .tasks:
            return ["task", "subtask", "estimate", "goal", "week", "weekly",
                    "monday", "sunday", "badge", "plan", "planner", "🍅"]
        case .breaks:
            return ["break", "message", "ambience", "rain", "forest", "white noise",
                    "brightness", "dim", "screen", "exit",
                    "night shift", "warm", "warmth"]
        case .focus:
            return ["app", "block", "blocker", "distraction", "reminder",
                    "posture", "water", "stand"]
        case .eyeCare:
            return ["eye", "exercise", "camera", "vision", "gaze",
                    "blink", "20-20-20"]
        case .sharingan:
            return ["sharingan", "iris", "style", "tomoe", "mangekyou",
                    "wallpaper", "desktop", "spin", "eyes", "follow", "mouse"]
        case .general:
            return ["theme", "appearance", "liquid", "glass",
                    "auto-start", "auto start", "sound", "alarm", "chime",
                    "notification", "launch at login", "startup"]
        case .voice:
            return ["tts", "voice", "speak", "spoken", "announcement", "rate", "pitch"]
        case .shortcuts:
            return ["keyboard", "hotkey", "shortcut", "global", "quick add"]
        }
    }

    /// Whether this category matches a lowercased search query.
    public func matches(_ query: String) -> Bool {
        let hay = ([title, subtitle] + keywords).joined(separator: " ").lowercased()
        return hay.contains(query)
    }
}
