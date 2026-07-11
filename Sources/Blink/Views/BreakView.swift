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
    var body: some View {
        let remaining = max(0, timer.remainingSeconds)

        GeometryReader { geo in
            // Eyes scale with the screen, centred on one flat backdrop color —
            // no cards or seams, the whole screen is a single tone.
            let eyeH = min(geo.size.width * 0.15, geo.size.height * 0.22)
            let bg = timer.settings.breakBackgroundStyle

            ZStack {
                Color(red: bg.color.r, green: bg.color.g, blue: bg.color.b)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    titleRow(remaining: remaining)
                        .padding(.horizontal, max(40, geo.size.width * 0.05))
                        .padding(.top, max(34, geo.size.height * 0.05))

                    Spacer()

                    MoveEyePair(direction: validator.currentStep?.direction ?? "center",
                                gaze: validator.currentStep?.targetGaze ?? .center,
                                eyeSize: eyeH,
                                style: timer.settings.sharinganStyle,
                                rightStyle: timer.settings.sharinganStyleRight,
                                holdSeconds: validator.currentStep?.holdSeconds ?? 0,
                                transition: timer.settings.breakPatternTransition,
                                endDate: Date().addingTimeInterval(remaining),
                                evolves: timer.settings.breakPatternMixed,
                                spinSeconds: timer.settings.breakPatternSpinSeconds)

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
        // Break session start/stop (TTS, validator, camera) lives in
        // BreakWindowManager — one view is created PER SCREEN, so doing it
        // here ran everything once per monitor.
        .onReceive(eyeTracker.$state) { state in
            validator.ingest(gaze: state.gaze, isBlinking: state.isBlinking)
        }
    }

    private var showExit: Bool { timer.settings.showExitBreakButton || forceExit }

    private func titleRow(remaining: TimeInterval) -> some View {
        HStack(alignment: .center) {
            Text(validator.currentExercise?.name ?? "Sharingan exercises")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))
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
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(validator.needsRetry ? .red.opacity(0.95)
                                                       : .white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
                .animation(.easeInOut(duration: 0.25), value: captionText)
            stepDots
            // Quiet hint: the queued task focus resumes on when the break ends.
            if let next = nextQueuedTitle {
                Text("Next: \(next)")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .padding(.horizontal, 40)
                    .padding(.top, 2)
            }
        }
    }

    /// Title of the task the focus queue will hand off to next. Read-only scan
    /// (not `current(validatedAgainst:)`) so rendering never mutates published
    /// queue state mid view-update.
    @MainActor
    private var nextQueuedTitle: String? {
        let store = TaskStore.shared
        return AppServices.focusQueue.taskIDs.lazy
            .compactMap { id in store.tasks.first { $0.id == id && !$0.isDone } }
            .first?.title
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

}
