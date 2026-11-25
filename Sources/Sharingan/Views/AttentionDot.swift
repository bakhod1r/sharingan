import SwiftUI
import SharinganCore

/// Tiny status dot for the Focus Attention Guard. Always reserves its slot's
/// size when `reserveSpace` is true so hiding it never shifts the timer.
struct AttentionDot: View {
    @ObservedObject private var attention = FocusAttentionService.shared
    var size: CGFloat = 7
    var reserveSpace = false

    private var indicator: AttentionIndicator {
        AttentionIndicator.from(state: attention.state, isEngaged: attention.isEngaged)
    }

    private var color: Color {
        switch indicator {
        case .hidden, .onScreen: return Color(red: 0.298, green: 0.961, blue: 0.780)  // #4cf5c7
        case .drifting: return Color(red: 0.851, green: 0.541, blue: 0.0)               // #d98a00
        case .distracted: return Color(red: 1.0, green: 0.176, blue: 0.227)             // #ff2d3a
        }
    }

    var body: some View {
        if indicator != .hidden {
            Circle().fill(color)
                .frame(width: size, height: size)
                .help(indicator.label)
                .accessibilityLabel("Attention: \(indicator.label)")
        } else if reserveSpace {
            Color.clear.frame(width: size, height: size)
        }
    }
}
