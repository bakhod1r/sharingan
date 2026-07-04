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

                    if timer.settings.cameraEyeTrackingEnabled,
                       CameraService.shared.isAuthorized {
ExerciseSequenceView(validator: ExerciseValidator.shared,
                                             eyeTracker: EyeTracker.shared)
                        .onAppear {
                            TTSKalibrator.shared.attach(to: ExerciseValidator.shared)
                        }
                        CameraIndicatorBadge(camera: CameraService.shared)
                    } else {
                        EyeExerciseAnimation()
                            .glassRounded(28, material: .regular)
                            .padding(20)
                    }
                }

                GlassButton(label: "Exit break",
                            systemImage: "xmark.circle.fill",
                            tint: .white.opacity(0.9),
                            action: onTapSkip)
                    .frame(maxWidth: 320)
            }
        }
        .onAppear {
            TTSKalibrator.shared.update(settings: timer.settings.ttsSettings,
                                        rate: timer.settings.ttsRate,
                                        pitch: timer.settings.ttsPitch)
            if timer.settings.ttsSettings.enabled {
                TTSService.shared.speak("Starting break. " + timer.settings.breakMessage,
                                        rate: timer.settings.ttsRate,
                                        pitch: timer.settings.ttsPitch)
            }
            ExerciseValidator.shared.exercises = timer.settings.exerciseSettings.buildSequence()
            if timer.settings.cameraEyeTrackingEnabled {
                ExerciseValidator.shared.reset()
            }
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                animateBlobs = true
            }
        }
        .onDisappear {
            TTSService.shared.stop()
            TTSKalibrator.shared.stop()
            ExerciseValidator.shared.stop()
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

    private func formatted(_ s: TimeInterval) -> String {
        let m = Int(s) / 60
        let sec = Int(s) % 60
        return String(format: "%02d:%02d", m, sec)
    }
}