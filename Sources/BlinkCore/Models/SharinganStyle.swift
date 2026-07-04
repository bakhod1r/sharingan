import Foundation

/// The Sharingan iris artwork shown during break eye exercises. Each case maps
/// to a PNG bundled with the Blink app target (`Resources/Sharingan/<file>.png`).
public enum SharinganStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case classic
    case mangekyou
    case mangekyouKamui
    case mangekyouEternal
    case itachi
    case sixStar
    case blade

    public var id: String { rawValue }

    /// Resource file name (without extension).
    public var fileName: String {
        switch self {
        case .classic:         return "classic"
        case .mangekyou:       return "mangekyou"
        case .mangekyouKamui:  return "mangekyou_kamui"
        case .mangekyouEternal:return "mangekyou_eternal"
        case .itachi:          return "itachi"
        case .sixStar:         return "sixstar"
        case .blade:           return "blade"
        }
    }

    public var label: String {
        switch self {
        case .classic:         return "Classic (3 tomoe)"
        case .mangekyou:       return "Mangekyō"
        case .mangekyouKamui:  return "Mangekyō — Kamui"
        case .mangekyouEternal:return "Mangekyō — Eternal"
        case .itachi:          return "Itachi"
        case .sixStar:         return "Six-point star"
        case .blade:           return "Three-blade"
        }
    }
}
