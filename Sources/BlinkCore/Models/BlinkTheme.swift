import Foundation
import SwiftUI

public enum BlinkTheme: String, Codable, CaseIterable, Sendable {
    case liquidGlass
    case frosted
    case midnight
    case cream
    case neon
    case mono

    public var label: String {
        switch self {
        case .liquidGlass: return "Liquid Glass"
        case .frosted:     return "Frosted"
        case .midnight:    return "Midnight"
        case .cream:       return "Cream"
        case .neon:        return "Neon"
        case .mono:        return "Mono"
        }
    }

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
        }
    }

    /// The interactive accent — selection bars, chips, streak fills, the focus
    /// button. Deliberately decoupled from `gradient.first`, because on Midnight
    /// that is black (invisible on the dark UI) and on Frosted/Cream it is
    /// near-white (indistinguishable from the app's white chrome). Each value is
    /// hand-picked to (a) read against the dark glass surfaces and (b) carry the
    /// theme's own temperature — cool blues for the cool themes, warm amber for
    /// Cream. Backgrounds still use the full `gradient`; only accents use this.
    public var accent: Color {
        switch self {
        case .liquidGlass: return .paletteFocusStart                        // blue
        case .frosted:     return Color(red: 0.52, green: 0.72, blue: 1.00)  // cool steel-blue
        case .midnight:    return Color(red: 0.45, green: 0.68, blue: 1.00)  // bright blue on black
        case .cream:       return Color(red: 1.00, green: 0.70, blue: 0.34)  // warm amber
        case .neon:        return Color(red: 0.95, green: 0.20, blue: 0.80)  // magenta
        case .mono:        return Color(white: 0.92)                         // near-white on black
        }
    }
}