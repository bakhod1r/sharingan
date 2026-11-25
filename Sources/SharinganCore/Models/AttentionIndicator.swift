import Foundation

/// What the tiny attention dot next to the timer shows. Pure mapping from the
/// guard's state so the widget / notch stay dumb.
public enum AttentionIndicator: Equatable, Sendable {
    case hidden, onScreen, drifting, distracted

    public static func from(state: AttentionState, isEngaged: Bool) -> AttentionIndicator {
        guard isEngaged else { return .hidden }
        switch state {
        case .attentive: return .onScreen
        case .drifting: return .drifting
        case .away, .noFace: return .distracted
        }
    }

    public var label: String {
        switch self {
        case .hidden: return ""
        case .onScreen: return "On screen"
        case .drifting: return "…"
        case .distracted: return "Distracted"
        }
    }
}
