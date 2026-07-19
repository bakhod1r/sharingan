import Foundation
import SwiftUI

/// App-wide text size. The UI is built on SwiftUI's semantic text styles
/// (`.body`, `.headline`, …), so scaling is expressed as a `DynamicTypeSize`
/// applied at the root of each hosted view — every semantic font follows it,
/// no per-label wiring. Custom fixed-point sizes (the big timer digits) stay
/// put on purpose; only the reading text scales.
public enum TextSize: String, Codable, CaseIterable, Sendable, Identifiable {
    case small
    case standard
    case large
    case xLarge

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .small:    return "Small"
        case .standard: return "Standard"
        case .large:    return "Large"
        case .xLarge:   return "Extra Large"
        }
    }

    /// The dynamic type category this maps to. `.standard` is SwiftUI's own
    /// default (`.large`), so an untouched install looks exactly as before.
    public var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .small:    return .medium
        case .standard: return .large
        case .large:    return .xLarge
        case .xLarge:   return .xxLarge
        }
    }
}
