import SwiftUI
import BlinkCore

struct BreakView: View {
    @ObservedObject var timer: PomodoroTimer
    var onTapSkip: () -> Void

    @State private var animateBlobs = false

    var body: some View {
        let phase = timer.phase
        let total = timer.totalSeconds
        let remaining = max(0, timer.remainingSeconds)
        let progress = total > 0 ? 1 - remaining / total : 0

        ZStack {
            LiquidMeshBackground(colors: phase.gradient)
                .overlay(Color.black.opacity(0.22))

            VStack(spacing: 36) {
                chip(phase: phase)

                ZStack {
                    CountdownRing(progress: progress,
                                  colors: phase.gradient,
                                  lineWidth: 22)
                        .frame(width: 320, height: 320)
                    VStack(spacing: 8) {
                        Text(formatted(remaining))
                            .font(.system(size: 88, weight: .light,
                                          design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.4),
                                    radius: 12, y: 6)
                        Label(phase.label, systemImage: phase.systemImage)
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .glassCapsule()
                            .padding(.horizontal, 26).padding(.vertical, 8)
                    }
                }
                .liquidShadow()

                VStack(spacing: 20) {
                    Text(timer.settings.breakMessage)
                        .font(.system(.title2, design: .rounded).weight(.medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 64)

                    eyeAnimation()
                }

                GlassButton(label: "Tanaffusni chiqar",
                            systemImage: "xmark.circle.fill",
                            tint: .white.opacity(0.9),
                            action: onTapSkip)
                    .frame(maxWidth: 320)
            }
        }
        .onAppear {
            if timer.settings.ttsEnabled {
                TTSService.shared.speak("Tanaffus vaqtini boshladik. " +
                                        timer.settings.breakMessage,
                                        rate: timer.settings.ttsRate,
                                        pitch: timer.settings.ttsPitch)
            }
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                animateBlobs = true
            }
        }
        .onDisappear {
            TTSService.shared.stop()
        }
    }

    private func chip(phase: PomodoroPhase) -> some View {
        HStack(spacing: 10) {
            Circle().fill(phase.glow).frame(width: 10, height: 10)
                .shadow(color: phase.glow, radius: 8)
            Text(phase.label.uppercased())
                .font(.system(.caption, design: .rounded).weight(.bold))
                .tracking(2.5)
                .foregroundStyle(.white.opacity(0.9))
        }
        .glassCapsule()
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    private func eyeAnimation() -> some View {
        HStack(spacing: 28) {
            eyeShape(direction: .top)
            eyeShape(direction: .center)
            eyeShape(direction: .right)
        }
        .glassRounded(28, material: .regular)
        .padding(20)
    }

    private enum Gaze { case top, center, right }
    private func eyeShape(direction: Gaze) -> some View {
        ZStack {
            EyeOutline()
                .fill(Color.white.opacity(0.12))
                .overlay(EyeOutline().stroke(Color.white.opacity(0.5), lineWidth: 2))
            Circle()
                .fill(Color.white)
                .frame(width: 14, height: 14)
                .shadow(color: .white.opacity(0.6), radius: 8)
                .offset(x: direction == .right ? 14 : 0,
                        y: direction == .top ? -8 : 0)
                .animation(.easeInOut(duration: 1.4)
                            .repeatForever(autoreverses: true),
                           value: animateBlobs)
        }
        .frame(width: 72, height: 72)
    }

    private func formatted(_ s: TimeInterval) -> String {
        let m = Int(s) / 60
        let sec = Int(s) % 60
        return String(format: "%02d:%02d", m, sec)
    }
}

private struct EyeOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRoundedRect(in: rect, cornerSize: CGSize(width: rect.height*0.5,
                                                      height: rect.height*0.55))
        return p
    }
}