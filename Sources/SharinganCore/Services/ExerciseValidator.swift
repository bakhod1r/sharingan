import Foundation
import Combine

@MainActor
public final class ExerciseValidator: ObservableObject {
    public static let shared = ExerciseValidator()

    @Published public private(set) var currentExerciseIndex: Int = 0
    @Published public private(set) var currentStepIndex: Int = 0
    @Published public private(set) var stepHoldStart: Date = .now
    @Published public private(set) var stepsCompletedInExercise: Int = 0
    @Published public private(set) var exercisesCompleted: Int = 0
    @Published public private(set) var needsRetry: Bool = false
    @Published public private(set) var isHolding: Bool = false
    @Published public private(set) var heldSeconds: Double = 0
    @Published public private(set) var lastValidatedAt: Date?

    public var exercises: [BreakExercise] = BreakExercise.library()
    public var gazeTolerance: Double = 0.40
    public var minHoldSeconds: Double = 0.6
    /// Extra time beyond a step's hold after which it auto-advances even if the
    /// gaze never validated — so a mis-detected/unsupported step can't wedge the
    /// whole exercise on "Try again" for the rest of the break.
    public var maxRetryGrace: Double = 5.0
    /// When on, camera-validatable steps (8-way gaze + blink) never auto-advance
    /// on the grace timer: the step waits until the camera actually confirms the
    /// movement. Guidance-only steps (far/center/closed/path sweeps) still
    /// complete on their hold timer. The app wires this on only when camera
    /// tracking is enabled AND permission is granted, so it can't wedge a break
    /// that has no camera to confirm with.
    public var strictValidation: Bool = false

    private var cancellable: AnyCancellable?
    private var ticker: Timer?
    /// A blink was detected at least once during the current "blink" step.
    private var blinkSeenInStep = false
    /// The camera confirmed the step's movement at least once during the hold.
    private var matchedInStep = false

    public init() {}

    public var currentExercise: BreakExercise? {
        guard currentExerciseIndex < exercises.count else { return nil }
        return exercises[currentExerciseIndex]
    }

    public var currentStep: BreakExerciseStep? {
        guard let ex = currentExercise, currentStepIndex < ex.steps.count else { return nil }
        return ex.steps[currentStepIndex]
    }

    public var progressInExercise: Double {
        guard let ex = currentExercise, !ex.steps.isEmpty else { return 0 }
        return Double(currentStepIndex) / Double(ex.steps.count)
    }

    public func start() {
        currentExerciseIndex = 0
        currentStepIndex = 0
        stepsCompletedInExercise = 0
        exercisesCompleted = 0
        needsRetry = false
        beginStep()
        startTicker()
    }

    public func stop() {
        ticker?.invalidate()
        ticker = nil
        isHolding = false
    }

    public func reset() {
        stop()
        currentExerciseIndex = 0
        currentStepIndex = 0
        stepsCompletedInExercise = 0
        exercisesCompleted = 0
        needsRetry = false
        heldSeconds = 0
    }

    // MARK: - Per-frame update

    /// Called by EyeTracker publisher with latest gaze sample.
    public func ingest(gaze: GazeDirection, isBlinking: Bool) {
        guard isHolding, let step = currentStep else { return }
        let target = step.targetGaze

        // Step varieties: "blink" passes once a blink is seen in the hold
        // window (single-frame blinks must not flash "Try again" between
        // them); "far" / "center" / "closed" pass without gaze match
        // ("closed" is guidance only — shut eyes can't read a retry prompt);
        // path sweeps (circle / figure-8) have no single target to match.
        let matched: Bool
        switch step.direction.lowercased() {
        case "blink":
            if isBlinking { blinkSeenInStep = true }
            matched = blinkSeenInStep
        case "far", "center", "closed",
             "circle_cw", "circle_ccw", "figure8": matched = true
        // Match on the 8-way direction label so the requirement is literally the
        // same as the on-screen eye: the detected gaze must point the same way the
        // Sharingan iris does. Comparing distance to the unit target was too strict
        // — a real gaze rarely reaches full magnitude, so steps never completed.
        default: matched = gaze.label == target.label
        }

        if matched {
            needsRetry = false
            matchedInStep = true
        } else if heldSeconds > minHoldSeconds {
            // After a grace period, if not matching, mark retry.
            needsRetry = true
        }
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Timer fires on the main run loop, so main-actor state is safe here.
            MainActor.assumeIsolated { self.tick(0.1) }
        }
    }

    /// Advance the hold clock by `dt` and complete the step when eligible.
    /// Split out of the Timer callback so tests can drive time synchronously.
    func tick(_ dt: Double) {
        guard isHolding, let step = currentStep else { return }
        heldSeconds += dt
        // In strict mode a camera-validatable step must have been confirmed at
        // least once — and not be in a retry — before it can complete.
        let requiresMatch = strictValidation && Self.cameraValidated(step.direction)
        // Auto-complete the hold once its full duration elapsed without a
        // pending retry…
        if heldSeconds >= step.holdSeconds && !needsRetry
            && (!requiresMatch || matchedInStep) {
            completeStep()
        } else if !requiresMatch && heldSeconds >= step.holdSeconds + maxRetryGrace {
            // …or, as a fail-safe, after an extra grace period regardless of
            // match, so detection errors never permanently stall the flow.
            // Strict mode deliberately opts out: an unconfirmed movement waits.
            completeStep()
        }
    }

    /// Steps the camera can actually confirm: the 8-way gaze directions and
    /// "blink". Guidance-only steps (focus far, eyes closed, path sweeps) have
    /// nothing to match against.
    private static func cameraValidated(_ direction: String) -> Bool {
        switch direction.lowercased() {
        case "far", "center", "closed", "circle_cw", "circle_ccw", "figure8":
            return false
        default:
            return true
        }
    }

    /// Jump to the first exercise with the given name — the break-screen picker
    /// lets the user run any exercise on demand instead of waiting for the
    /// sequence to reach it. From there the normal sequence continues.
    public func select(named name: String) {
        guard let idx = exercises.firstIndex(where: { $0.name == name }),
              idx != currentExerciseIndex || currentStepIndex > 0 else { return }
        currentExerciseIndex = idx
        currentStepIndex = 0
        stepsCompletedInExercise = 0
        beginStep()
    }

    private func beginStep() {
        stepHoldStart = .now
        heldSeconds = 0
        needsRetry = false
        blinkSeenInStep = false
        matchedInStep = false
        isHolding = true
    }

    private func completeStep() {
        stepsCompletedInExercise += 1
        lastValidatedAt = .now
        if let ex = currentExercise, currentStepIndex + 1 >= ex.steps.count {
            advanceExercise()
        } else {
            currentStepIndex += 1
            beginStep()
        }
    }

    private func advanceExercise() {
        exercisesCompleted += 1
        if currentExerciseIndex + 1 >= exercises.count {
            // Loop the library for long breaks.
            currentExerciseIndex = 0
        } else {
            currentExerciseIndex += 1
        }
        currentStepIndex = 0
        stepsCompletedInExercise = 0
        beginStep()
    }
}

extension ExerciseValidator {
    public func formattedHoldRemaining() -> String {
        guard let step = currentStep, isHolding else { return "--" }
        let remaining = max(0, step.holdSeconds - heldSeconds)
        return String(format: "%.1fs", remaining)
    }
}