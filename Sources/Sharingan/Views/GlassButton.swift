import SwiftUI

struct GlassButton: View {
    var label: String
    var systemImage: String
    var tint: Color = .white
    var isEnabled: Bool = true
    /// Filled accent treatment for the one primary action on a screen.
    var prominent: Bool = false
    /// Accent color used when `prominent` (defaults to the system accent, but
    /// callers pass the theme accent).
    var accent: Color = .accentColor
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    // Cross-fade between glyphs (e.g. play ↔ pause) instead of a hard swap.
                    .contentTransition(.opacity)
                Text(label)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
            }
            .foregroundStyle(prominent ? Color.white : tint)
            .padding(.horizontal, 22).padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(prominentBackground)
            .opacity(isEnabled ? 1 : 0.45)
        }
        .disabled(!isEnabled)
        .buttonStyle(.pressable)
    }

    @ViewBuilder
    private var prominentBackground: some View {
        if prominent {
            Capsule()
                .fill(LinearGradient(colors: [accent, accent.opacity(0.82)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                .shadow(color: accent.opacity(0.5), radius: 10, y: 4)
        } else {
            // Same capsule language as the prominent Start button, one step
            // quieter: a translucent theme-accent fill instead of neutral
            // glass, so every control in the stack reads as one themed family.
            Capsule()
                .fill(LinearGradient(colors: [accent.opacity(0.30), accent.opacity(0.18)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Capsule().stroke(accent.opacity(0.40), lineWidth: 1))
        }
    }
}