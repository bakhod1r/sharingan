import Foundation

/// The iris drawn inside the "Looking-for" break eye.
public enum BreakIrisStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    /// The configured Sharingan pattern (style, evolution, spin).
    case sharingan
    /// The video's black pupil with its white highlight.
    case original

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .sharingan: return "Sharingan"
        case .original:  return "Original"
        }
    }
}
