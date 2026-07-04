import SwiftUI
import BlinkCore

struct FloatingTimerView: View {
    @ObservedObject var timer: PomodoroTimer
    @State private var animate = false

    var body: some View {
        let phase = timer.phase
        let remaining = max(0, timer.remainingSeconds)

        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: max(0.001, timer.progress))
                    .stroke(
                        AngularGradient(colors: phase.gradient + [phase.gradient.first ?? .white],
                                        center: .center),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Image(systemName: phase.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 1) {
                Text(formatted(remaining))
                    .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                Text(phase.label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .glassRounded(20, material: .regular)
        .liquidShadow(radius: 12, y: 6)
        .overlay {
            if timer.isFlashing {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.9), lineWidth: 2)
                    .blur(radius: 4)
                    .opacity(animate ? 1 : 0.2)
                    .animation(.easeInOut(duration: 0.5).repeatForever(), value: animate)
                    .allowsHitTesting(false)
            }
        }
        .onAppear { animate = true }
        .onChange(of: timer.isFlashing) { _ in animate = timer.isFlashing }
    }

    private func formatted(_ s: TimeInterval) -> String {
        let m = Int(s) / 60, sec = Int(s) % 60
        return String(format: "%02d:%02d", m, sec)
    }
}