import SwiftUI
import SharinganCore

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

                    exercisePicker
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, max(40, geo.size.width * 0.05))
                        .padding(.top, 14)

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

                    // The break ends when its time is up — there is no Skip.
                    // "Auto-start break" off parks the countdown at full length,
                    // so Start is what begins it (never in the Settings preview,
                    // which must not touch the real timer). "Exit break" appears
                    // only when the user has opted into it, or in that preview.
                    VStack(spacing: 12) {
                        if !forceExit && !timer.isRunning {
                            GlassButton(label: "Start break",
                                        systemImage: "play.fill",
                                        tint: .white.opacity(0.95),
                                        accent: timer.settings.theme.accent) {
                                timer.start()
                            }
                            .frame(maxWidth: 220)
                            .accessibilityLabel("Start break")
                        }
                        if showExit {
                            GlassButton(label: "Exit break",
                                        systemImage: "xmark.circle.fill",
                                        tint: .white.opacity(0.9),
                                        accent: timer.settings.theme.accent,
                                        action: onTapSkip)
                                .frame(maxWidth: 220)
                                .accessibilityLabel("Exit break")
                        }
                    }
                    .padding(.bottom, 40)
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

    // MARK: - Exercise picker (top chips)

    /// One chip per distinct exercise in the break sequence. The active one is
    /// highlighted; tapping another jumps the validator (and so the eyes) to it.
    private var exercisePicker: some View {
        HStack(spacing: 8) {
            ForEach(pickerNames, id: \.self) { name in
                let active = validator.currentExercise?.name == name
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        validator.select(named: name)
                    }
                } label: {
                    Text(name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(active ? .black.opacity(0.85) : .white.opacity(0.7))
                        .lineLimit(1)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Capsule().fill(active ? .white.opacity(0.9)
                                                          : .white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start \(name)")
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .animation(.easeInOut(duration: 0.25), value: validator.currentExerciseIndex)
    }

    /// Distinct exercise names in sequence order (rounds repeat the same three).
    private var pickerNames: [String] {
        var seen = Set<String>()
        return validator.exercises.compactMap { seen.insert($0.name).inserted ? $0.name : nil }
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
