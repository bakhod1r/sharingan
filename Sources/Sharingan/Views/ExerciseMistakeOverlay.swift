import SwiftUI
import SharinganCore

/// Strong "you're doing the step wrong" warning: red edge glow, a nudging arrow
/// toward the target side, and a title + subtitle. Non-interactive.
struct ExerciseMistakeOverlay: View {
    let mistake: ExerciseMistake?
    let target: GazeDirection

    private let red = Color(red: 1, green: 0.18, blue: 0.23)

    var body: some View {
        ZStack {
            if let mistake {
                content(mistake)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: mistake)
        .allowsHitTesting(false)
    }

    private func content(_ m: ExerciseMistake) -> some View {
        GeometryReader { geo in
            ZStack {
                Rectangle()
                    .strokeBorder(red, lineWidth: 5)
                    .shadow(color: red.opacity(0.55), radius: 40)
                    .blur(radius: 0.5)
                    .ignoresSafeArea()

                if let dir = m.arrow(target: target) {
                    // Phase-based nudge (no repeatForever).
                    TimelineView(.periodic(from: .now, by: 1.0 / 20)) { ctx in
                        let t = ctx.date.timeIntervalSinceReferenceDate
                        let nudge = (sin(t * 2 * .pi / 0.8) + 1) / 2 * 14
                        arrow(dir, nudge: nudge, size: geo.size)
                    }
                }

                VStack(spacing: 6) {
                    Text(m.title)
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                    Text(m.subtitle)
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 8)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, geo.size.height * 0.2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(m.title). \(m.subtitle)")
    }

    private func arrow(_ dir: GazeDirection, nudge: Double, size: CGSize) -> some View {
        let len = max(1, dir.magnitude)
        let ux = dir.dx / len, uy = dir.dy / len
        let angle = Angle(radians: atan2(uy, ux))
        let edge = min(size.width, size.height) * 0.42
        return Image(systemName: "arrowtriangle.right.fill")
            .font(.system(size: 90))
            .foregroundStyle(red)
            .shadow(color: red.opacity(0.7), radius: 24)
            .rotationEffect(angle)
            .offset(x: ux * (size.width * 0.42 + nudge),
                    y: uy * (edge + nudge))
    }
}
