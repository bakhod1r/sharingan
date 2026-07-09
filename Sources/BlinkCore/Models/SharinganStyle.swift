import Foundation

/// The Sharingan iris artwork shown during break eye exercises. Every style is
/// drawn in code as vector art (see MoveIrisView) — no PNG assets.
public enum SharinganStyle: String, CaseIterable, Codable, Sendable, Identifiable {
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

    public var id: String { rawValue }

    public var label: String {
        switch self {
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
        }
    }
}
