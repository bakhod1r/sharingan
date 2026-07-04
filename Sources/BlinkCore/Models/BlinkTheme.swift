import Foundation
import SwiftUI

public enum BlinkTheme: String, Codable, CaseIterable, Sendable {
    case liquidGlass
    case frosted
    case midnight
    case cream
    case neon

    public var label: String {
        switch self {
        case .liquidGlass: return "Liquid Glass"
        case .frosted:     return "Frosted"
        case .midnight:    return "Midnight"
        case .cream:       return "Cream"
        case .neon:        return "Neon"
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
        }
    }
}