import SwiftUI

/// Big glowing circular call-to-action (CleanMyMac "Scan" style), used as the
/// primary Start/Pause control on the timer screen.
struct CircularRunButton: View {
    var isRunning: Bool
    var colors: [Color]
    var action: () -> Void

    private var glow: Color { colors.first ?? .cyan }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer glow ring — brighter while running. Static on
                // purpose: a breathing blur/shadow made SwiftUI re-layout the
                // whole main window every frame (~20% CPU for the session).
                Circle()
                    .stroke(glow, lineWidth: 3)
                    .frame(width: 104, height: 104)
                    .blur(radius: isRunning ? 6 : 3)
                    .opacity(isRunning ? 0.9 : 0.7)

                // Crisp ring on top of the glow
                Circle()
                    .stroke(glow.opacity(0.9), lineWidth: 2)
                    .frame(width: 104, height: 104)

                // Inner glass disc
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle().fill(
                            LinearGradient(colors: colors.map { $0.opacity(0.35) },
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing))
                    )
                    .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
                    .frame(width: 88, height: 88)

                VStack(spacing: 3) {
                    Image(systemName: isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 24, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                        .animation(DS.Motion.snappy, value: isRunning)
                    Text(isRunning ? "Pause" : "Start")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                }
                .foregroundStyle(.white)
            }
            .shadow(color: glow.opacity(0.55), radius: isRunning ? 22 : 16)
            .animation(.easeOut(duration: 0.4), value: isRunning)
            .contentShape(Circle())
        }
        .buttonStyle(.pressable)
    }
}

/// Small round glass control used for secondary timer actions (Skip / Reset).
struct GlassIconButton: View {
    var systemImage: String
    var label: String
    var tint: Color = .white
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 52, height: 52)
                    .glass(Circle(), material: .regular)
                Text(label)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(tint.opacity(0.75))
            }
        }
        .buttonStyle(.pressableSubtle)
    }
}
