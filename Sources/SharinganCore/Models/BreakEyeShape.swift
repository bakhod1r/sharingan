import Foundation

/// Which face the break screen draws. Wallpaper, menu-bar icon, Dock icon
/// and the exercise sequence always keep the Sharingan eye.
public enum BreakEyeShape: String, Codable, CaseIterable, Identifiable, Sendable {
    case sharingan
    case lookingFor
    case angry

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .sharingan:  return "Sharingan"
        case .lookingFor: return "Looking-for"
        case .angry:      return "Angry"
        }
    }
}
