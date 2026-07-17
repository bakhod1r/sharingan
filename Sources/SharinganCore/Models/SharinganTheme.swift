import Foundation
import SwiftUI

public enum SharinganTheme: String, Codable, CaseIterable, Sendable {
    case liquidGlass
    case frosted
    case midnight
    case cream
    case neon
    case mono
    case forest
    // Premium themes.
    case sunset
    case ocean
    case aurora
    case rose
    case graphite
    case amethyst
    case ember
    case sky
    case sand
    case obsidian
    case darkside
    case hacker
    case gold

    public var label: String {
        switch self {
        case .liquidGlass: return "Liquid Glass"
        case .frosted:     return "Frosted"
        case .midnight:    return "Midnight"
        case .cream:       return "Cream"
        case .neon:        return "Neon"
        case .mono:        return "Mono"
        case .forest:      return "Forest"
        case .sunset:      return "Sunset"
        case .ocean:       return "Ocean"
        case .aurora:      return "Aurora"
        case .rose:        return "Rose Gold"
        case .graphite:    return "Graphite"
        case .amethyst:    return "Amethyst"
        case .ember:       return "Ember"
        case .sky:         return "Sky"
        case .sand:        return "Sand"
        case .obsidian:    return "Obsidian"
        case .darkside:    return "Darkside"
        case .hacker:      return "Hacker"
        case .gold:        return "Gold"
        }
    }

    /// Themes that paint an animated matrix "digital rain" behind the UI instead
    /// of a plain wash. Read by `ThemeWindowWash` to layer the effect in.
    public var hasMatrixRain: Bool { self == .hacker }

    /// The ten curated "premium" palettes, tagged so the picker can badge them
    /// PRO. The seven originals stay untagged. (There is no purchase gate wired
    /// up yet — this is the identity the UI reads; enforcement can hook in later.)
    public var isPremium: Bool {
        switch self {
        case .liquidGlass, .frosted, .midnight, .cream, .neon, .mono, .forest:
            return false
        case .sunset, .ocean, .aurora, .rose, .graphite, .amethyst, .ember,
             .sky, .sand, .obsidian, .darkside, .hacker, .gold:
            return true
        }
    }

    /// The theme's *identity* colors — the vivid swatch shown in the picker and
    /// the little preview dot. Deliberately allowed to be light or saturated so
    /// each theme reads as itself at a glance. This is **not** what the window is
    /// painted with; see `surface` for that.
    public var gradient: [Color] {
        switch self {
        case .liquidGlass: return [.paletteFocusStart, .paletteFocusEnd]
        case .frosted:     return [.white.opacity(0.85), .white.opacity(0.6)]
        case .midnight:    return [.black, Color(white: 0.12)]
        case .cream:       return [Color(red: 0.98, green: 0.94, blue: 0.84),
                                   Color(red: 0.92, green: 0.84, blue: 0.68)]
        case .neon:        return [Color(red: 0.95, green: 0.20, blue: 0.80),
                                   Color(red: 0.10, green: 0.95, blue: 0.65)]
        case .mono:        return [.black, Color(white: 0.22)]
        case .forest:      return [Color(red: 0.20, green: 0.78, blue: 0.45),
                                   Color(red: 0.05, green: 0.42, blue: 0.30)]
        case .sunset:      return [Color(red: 1.00, green: 0.42, blue: 0.31),
                                   Color(red: 0.98, green: 0.24, blue: 0.55)]
        case .ocean:       return [Color(red: 0.16, green: 0.72, blue: 0.86),
                                   Color(red: 0.09, green: 0.36, blue: 0.72)]
        case .aurora:      return [Color(red: 0.24, green: 0.90, blue: 0.66),
                                   Color(red: 0.52, green: 0.36, blue: 0.96)]
        case .rose:        return [Color(red: 0.98, green: 0.72, blue: 0.68),
                                   Color(red: 0.85, green: 0.44, blue: 0.52)]
        case .graphite:    return [Color(red: 0.42, green: 0.46, blue: 0.52),
                                   Color(red: 0.20, green: 0.22, blue: 0.26)]
        case .amethyst:    return [Color(red: 0.72, green: 0.44, blue: 0.98),
                                   Color(red: 0.42, green: 0.26, blue: 0.78)]
        case .ember:       return [Color(red: 1.00, green: 0.58, blue: 0.20),
                                   Color(red: 0.82, green: 0.16, blue: 0.16)]
        case .sky:         return [Color(red: 0.52, green: 0.80, blue: 1.00),
                                   Color(red: 0.32, green: 0.56, blue: 0.96)]
        case .sand:        return [Color(red: 0.90, green: 0.78, blue: 0.56),
                                   Color(red: 0.76, green: 0.56, blue: 0.36)]
        case .obsidian:    return [Color(red: 0.16, green: 0.20, blue: 0.30),
                                   Color(red: 0.04, green: 0.05, blue: 0.09)]
        case .darkside:    return [Color(white: 0.10), .black]
        case .hacker:      return [Color(red: 0.10, green: 0.90, blue: 0.30), .black]
        case .gold:        return [Color(red: 0.95, green: 0.80, blue: 0.42), .black]
        }
    }

    /// The actual window/island surface: always a **dark, text-safe** gradient
    /// tinted with the theme's own hue. Decoupled from `gradient` because the
    /// whole UI is built as white-on-dark (`DS.dsPrimary == .white`), so a light
    /// or hot swatch color (Frosted's white, Cream's tan, Neon's magenta) painted
    /// as the background left text unreadable. Here every theme resolves to a
    /// deep base that keeps its temperature but guarantees contrast — the picker
    /// still shows the vivid `gradient`, the window wears this.
    public var surface: [Color] {
        switch self {
        case .liquidGlass: return [Color(red: 0.16, green: 0.31, blue: 0.62),
                                   Color(red: 0.05, green: 0.10, blue: 0.32)]
        case .frosted:     return [Color(red: 0.16, green: 0.19, blue: 0.24),
                                   Color(red: 0.08, green: 0.10, blue: 0.13)]
        case .midnight:    return [.black, Color(white: 0.12)]
        case .cream:       return [Color(red: 0.20, green: 0.16, blue: 0.10),
                                   Color(red: 0.10, green: 0.08, blue: 0.05)]
        case .neon:        return [Color(red: 0.16, green: 0.04, blue: 0.16),
                                   Color(red: 0.05, green: 0.06, blue: 0.10)]
        case .mono:        return [Color(white: 0.10), Color(white: 0.02)]
        case .forest:      return [Color(red: 0.04, green: 0.15, blue: 0.09),
                                   Color(red: 0.02, green: 0.07, blue: 0.05)]
        case .sunset:      return [Color(red: 0.22, green: 0.08, blue: 0.10),
                                   Color(red: 0.10, green: 0.03, blue: 0.07)]
        case .ocean:       return [Color(red: 0.03, green: 0.13, blue: 0.22),
                                   Color(red: 0.01, green: 0.06, blue: 0.12)]
        case .aurora:      return [Color(red: 0.06, green: 0.15, blue: 0.16),
                                   Color(red: 0.06, green: 0.05, blue: 0.16)]
        case .rose:        return [Color(red: 0.20, green: 0.11, blue: 0.12),
                                   Color(red: 0.10, green: 0.05, blue: 0.07)]
        case .graphite:    return [Color(red: 0.14, green: 0.15, blue: 0.17),
                                   Color(red: 0.05, green: 0.06, blue: 0.07)]
        case .amethyst:    return [Color(red: 0.13, green: 0.07, blue: 0.20),
                                   Color(red: 0.06, green: 0.03, blue: 0.11)]
        case .ember:       return [Color(red: 0.20, green: 0.08, blue: 0.04),
                                   Color(red: 0.09, green: 0.04, blue: 0.02)]
        case .sky:         return [Color(red: 0.06, green: 0.12, blue: 0.22),
                                   Color(red: 0.02, green: 0.05, blue: 0.11)]
        case .sand:        return [Color(red: 0.18, green: 0.14, blue: 0.09),
                                   Color(red: 0.09, green: 0.07, blue: 0.04)]
        case .obsidian:    return [Color(red: 0.09, green: 0.11, blue: 0.15),
                                   Color(red: 0.02, green: 0.03, blue: 0.05)]
        case .darkside:    return [Color(white: 0.02), .black]
        case .hacker:      return [Color(red: 0.0, green: 0.06, blue: 0.02), .black]
        case .gold:        return [Color(red: 0.12, green: 0.09, blue: 0.02), .black]
        }
    }

    /// The interactive accent — selection bars, chips, streak fills, the focus
    /// button. Deliberately decoupled from `gradient.first`, because on Midnight
    /// that is black (invisible on the dark UI) and on Frosted/Cream it is
    /// near-white (indistinguishable from the app's white chrome). Each value is
    /// hand-picked to (a) read against the dark glass surfaces and (b) carry the
    /// theme's own temperature — cool blues for the cool themes, warm amber for
    /// Cream. Backgrounds still use `surface`; only accents use this.
    public var accent: Color {
        switch self {
        case .liquidGlass: return .paletteFocusStart                        // blue
        case .frosted:     return Color(red: 0.52, green: 0.72, blue: 1.00)  // cool steel-blue
        case .midnight:    return Color(red: 0.45, green: 0.68, blue: 1.00)  // bright blue on black
        case .cream:       return Color(red: 1.00, green: 0.70, blue: 0.34)  // warm amber
        case .neon:        return Color(red: 0.95, green: 0.20, blue: 0.80)  // magenta
        case .mono:        return Color(white: 0.92)                         // near-white on black
        case .forest:      return Color(red: 0.30, green: 0.85, blue: 0.55)  // emerald
        case .sunset:      return Color(red: 1.00, green: 0.48, blue: 0.42)  // coral
        case .ocean:       return Color(red: 0.30, green: 0.78, blue: 0.95)  // cyan
        case .aurora:      return Color(red: 0.36, green: 0.95, blue: 0.72)  // mint-green
        case .rose:        return Color(red: 1.00, green: 0.62, blue: 0.68)  // rose pink
        case .graphite:    return Color(red: 0.70, green: 0.76, blue: 0.84)  // cool silver
        case .amethyst:    return Color(red: 0.78, green: 0.56, blue: 1.00)  // lilac
        case .ember:       return Color(red: 1.00, green: 0.55, blue: 0.28)  // orange
        case .sky:         return Color(red: 0.50, green: 0.78, blue: 1.00)  // sky blue
        case .sand:        return Color(red: 0.95, green: 0.78, blue: 0.48)  // golden sand
        case .obsidian:    return Color(red: 0.44, green: 0.60, blue: 0.92)  // steel blue
        case .darkside:    return Color(white: 0.78)                         // dim silver
        case .hacker:      return Color(red: 0.20, green: 1.00, blue: 0.40)  // matrix green
        case .gold:        return Color(red: 1.00, green: 0.82, blue: 0.40)  // gold
        }
    }
}
