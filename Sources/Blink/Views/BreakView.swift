import SwiftUI
import BlinkCore

struct BreakView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var validator = ExerciseValidator.shared
    @ObservedObject private var eyeTracker = EyeTracker.shared
    var onTapSkip: () -> Void
    /// Force-show the Exit button regardless of the user setting (used by the
    /// Settings "Preview break screen" so the preview can always be closed).
    var forceExit: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let remaining = max(0, timer.remainingSeconds)

        GeometryReader { geo in
            // Eyes scale with the screen. Big and centred on pure black — no card.
            let eyeH = min(geo.size.width * 0.15, geo.size.height * 0.22)

            ZStack {
                // Fully black backdrop.
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    titleRow(remaining: remaining)
                        .padding(.horizontal, max(40, geo.size.width * 0.05))
                        .padding(.top, max(34, geo.size.height * 0.05))

                    Spacer()

                    // Center — big Sharingan eyes over a slow breathing halo.
                    ZStack {
                        breathingGuide(size: min(geo.size.width, geo.size.height) * 0.5)
                        MoveEyePair(direction: validator.currentStep?.direction ?? "center",
                                    gaze: validator.currentStep?.targetGaze ?? .center,
                                    eyeSize: eyeH,
                                    style: timer.settings.sharinganStyle)
                    }

                    Spacer()

                    caption
                        .padding(.bottom, 18)

                    // A break should never fully trap the user. When the exit
                    // button is enabled it's a clear glass button; otherwise a
                    // quiet low-key "Skip break", so there is always an escape.
                    if showExit {
                        GlassButton(label: "Exit break",
                                    systemImage: "xmark.circle.fill",
                                    tint: .white.opacity(0.9),
                                    action: onTapSkip)
                            .frame(maxWidth: 220)
                            .padding(.bottom, 40)
                            .accessibilityLabel("Exit break")
                    } else {
                        Button(action: onTapSkip) {
                            Text("Skip break")
                                .font(.system(.caption, design: .rounded).weight(.medium))
                                .foregroundStyle(.white.opacity(0.32))
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 30)
                        .accessibilityLabel("Skip break")
                    }
                }

                if timer.settings.cameraEyeTrackingEnabled,
                   CameraService.shared.isAuthorized {
                    VStack {
                        Spacer()
                        HStack { Spacer()
                            CameraIndicatorBadge(camera: CameraService.shared)
                                .padding(20)
                        }
                    }
                }
            }
        }
        .onAppear(perform: startBreak)
        .onDisappear(perform: endBreak)
        .onReceive(eyeTracker.$state) { state in
            validator.ingest(gaze: state.gaze, isBlinking: state.isBlinking)
        }
    }

    private var showExit: Bool { timer.settings.showExitBreakButton || forceExit }

    /// A soft ring that expands and contracts on a ~5s cycle — a gentle
    /// breathe-in / breathe-out pacer behind the eyes.
    private func breathingGuide(size: CGFloat) -> some View {
        TimelineView(.animation(paused: reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let phase = (sin(t * (2 * .pi / 5.0)) + 1) / 2   // 0…1
            let scale = 0.82 + phase * 0.5
            Circle()
                .stroke(
                    RadialGradient(colors: [Color.white.opacity(0.14), .clear],
                                   center: .center, startRadius: 0, endRadius: size * 0.7),
                    lineWidth: size * 0.14)
                .frame(width: size, height: size)
                .scaleEffect(scale)
                .opacity(0.35 + phase * 0.45)
                .blur(radius: 6)
        }
        .allowsHitTesting(false)
    }

    private func titleRow(remaining: TimeInterval) -> some View {
        HStack(alignment: .center) {
            Text(validator.currentExercise?.name ?? "Sharingan exercises")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1).minimumScaleFactor(0.7)

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Text("Time Left:")
                    .foregroundStyle(.white.opacity(0.55))
                Text(timer.settings.timeFormat.string(remaining))
                    .font(.dsTimer(20))
                    .foregroundStyle(.white)
            }
            .font(.system(size: 20, weight: .medium, design: .rounded))
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(.white.opacity(0.08)))
        }
    }

    // MARK: - Caption (instruction + step dots)

    private var caption: some View {
        VStack(spacing: 8) {
            Text(captionText)
                .font(.system(.callout, design: .rounded).weight(.medium))
                .foregroundStyle(validator.needsRetry ? .red.opacity(0.95)
                                                       : .white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
                .animation(.easeInOut(duration: 0.25), value: captionText)
            stepDots
        }
    }

    private var captionText: String {
        if validator.needsRetry { return "Try again — follow the eyes" }
        return validator.currentStep?.instruction ?? "Relax and follow the eyes"
    }

    @ViewBuilder
    private var stepDots: some View {
        if let ex = validator.currentExercise {
            HStack(spacing: 6) {
                ForEach(Array(ex.steps.enumerated()), id: \.offset) { idx, _ in
                    Capsule()
                        .fill(idx < validator.currentStepIndex ? Color.green.opacity(0.9)
                              : (idx == validator.currentStepIndex ? Color.white.opacity(0.75)
                                                                   : Color.white.opacity(0.2)))
                        .frame(width: idx == validator.currentStepIndex ? 20 : 10, height: 4)
                }
            }
        }
    }

    // MARK: - Lifecycle

    private func startBreak() {
        TTSKalibrator.shared.update(settings: timer.settings.ttsSettings,
                                    rate: timer.settings.ttsRate,
                                    pitch: timer.settings.ttsPitch)
        TTSKalibrator.shared.attach(to: validator)
        if timer.settings.ttsSettings.enabled {
            TTSService.shared.speak("Starting break. " + timer.settings.breakMessage,
                                    rate: timer.settings.ttsRate,
                                    pitch: timer.settings.ttsPitch)
        }
        validator.exercises = timer.settings.exerciseSettings.buildSequence()
        validator.reset()
        validator.start()
        // Camera runs only for the duration of this break screen, never in focus.
        if timer.settings.cameraEyeTrackingEnabled {
            Task { @MainActor in
                _ = await CameraService.shared.requestPermission()
                CameraService.shared.start()
                EyeTracker.shared.resetBlinkWindow()
                EyeTracker.shared.start()
            }
        }
    }

    private func endBreak() {
        TTSService.shared.stop()
        TTSKalibrator.shared.stop()
        validator.stop()
        EyeTracker.shared.stop()
        CameraService.shared.stop()
    }
}
