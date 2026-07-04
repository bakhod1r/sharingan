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

    private var cancellable: AnyCancellable?
    private var ticker: Timer?

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

        // Step varieties: "blink" checks blink count over hold window;
        // "far" / "center" pass without gaze match.
        let matched: Bool
        switch step.direction.lowercased() {
        case "blink": matched = isBlinking
        case "far", "center": matched = true
        default: matched = gaze.matches(target, tolerance: gazeTolerance)
        }

        if matched {
            needsRetry = false
        } else if heldSeconds > minHoldSeconds {
            // After a grace period, if not matching, mark retry.
            needsRetry = true
        }
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.isHolding, let step = self.currentStep else { return }
            self.heldSeconds += 0.1
            // Auto-complete hold once full duration elapsed WITHOUT pending retry.
            if self.heldSeconds >= step.holdSeconds && !self.needsRetry {
                self.completeStep()
            }
        }
    }

    private func beginStep() {
        stepHoldStart = .now
        heldSeconds = 0
        needsRetry = false
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