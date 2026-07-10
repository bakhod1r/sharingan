import Foundation

/// The Sharingan iris artwork shown during break eye exercises. Every style is
/// drawn in code as vector art (see MoveIrisView) — no PNG assets.
public enum SharinganStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case tomoe1
    case tomoe2
    case classic
    case mangekyou
    case mangekyouKamui
    case mangekyouEternal
    case itachi
    case sixStar
    case blade
    case orbit
    case crescent
    case fourBlade
    case madara
    case shuriken
    case swirl
    case triangleTomoe
    case ringCrescents
    case rinnegan

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .tomoe1:          return "Classic (1 tomoe)"
        case .tomoe2:          return "Classic (2 tomoe)"
        case .classic:         return "Classic (3 tomoe)"
        case .mangekyou:       return "Mangekyō"
        case .mangekyouKamui:  return "Mangekyō — Kamui"
        case .mangekyouEternal:return "Mangekyō — Eternal"
        case .itachi:          return "Itachi"
        case .sixStar:         return "Six-point star"
        case .blade:           return "Three-blade"
        case .orbit:           return "Orbit rings"
        case .crescent:        return "Triple crescent"
        case .fourBlade:       return "Four-blade"
        case .madara:          return "Madara — fan blades"
        case .shuriken:        return "Shuriken"
        case .swirl:           return "Single swirl"
        case .triangleTomoe:   return "Triangle tomoe"
        case .ringCrescents:   return "Ring + crescents"
        case .rinnegan:        return "Rinnegan"
        }
    }
}

/// Break-screen backdrop: one flat color across the entire screen — no
/// panels or seams. Graphite matches the reference video's card gray.
/// Colors are linear RGB 0…1.
public enum BreakBackgroundStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case pureBlack
    case graphite
    case slate

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .pureBlack: return "Pure black"
        case .graphite:  return "Graphite"
        case .slate:     return "Slate"
        }
    }

    public var color: (r: Double, g: Double, b: Double) {
        switch self {
        case .pureBlack: return (0, 0, 0)
        case .graphite:  return (0.067, 0.075, 0.078)   // #111314 — video gray
        case .slate:     return (0.098, 0.106, 0.118)   // #191B1E
        }
    }
}

/// When the desktop-wallpaper Sharingan spins. The eyes always follow the
/// mouse; the spin is an extra flourish.
public enum WallpaperSpinTrigger: String, CaseIterable, Codable, Sendable, Identifiable {
    case off
    case idle
    case click
    case both
    case always

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .off:    return "Off"
        case .idle:   return "When idle"
        case .click:  return "On click"
        case .both:   return "Idle + click"
        case .always: return "Always"
        }
    }

    public var spinsOnIdle: Bool { self == .idle || self == .both }
    public var spinsOnClick: Bool { self == .click || self == .both }
    /// Continuous spin regardless of mouse activity.
    public var spinsAlways: Bool { self == .always }
}

/// Break-screen pattern transition: the iris pattern whirls open out of the
/// pupil at break start, collapses+reopens as the next pattern on each
/// exercise step, and collapses shut as the break ends. Off = static pattern.
public enum PatternTransitionSpeed: String, CaseIterable, Codable, Sendable, Identifiable {
    case off
    case fast
    case normal
    case slow

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .off:    return "Off"
        case .fast:   return "Fast"
        case .normal: return "Normal"
        case .slow:   return "Slow"
        }
    }

    /// Pattern collapse (closing) duration, seconds.
    public var closeSeconds: Double {
        switch self {
        case .off:    return 0
        case .fast:   return 0.30
        case .normal: return 0.50
        case .slow:   return 0.85
        }
    }

    /// Pattern emergence (opening) duration, seconds.
    public var openSeconds: Double {
        switch self {
        case .off:    return 0
        case .fast:   return 0.50
        case .normal: return 0.80
        case .slow:   return 1.30
        }
    }
}
