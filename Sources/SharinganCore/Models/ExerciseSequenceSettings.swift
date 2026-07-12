import Foundation

/// Break eye-exercise sequence sozlamalari.
public struct ExerciseSequenceSettings: Codable, Equatable, Sendable {
    /// 20-20-20, gaze, blink mashqlari alohida yoqiladi.
    public var twentyRuleEnabled: Bool = true
    public var gazeEnabled: Bool = true
    public var blinkEnabled: Bool = true
    /// Har step default ladagi holdSeconds (foydalanuvchi masshtab qiladi).
    public var stepHoldScale: Double = 1.0
    /// Minimal/normal hold vaqt chegaralari.
    public var minHoldSeconds: Double = 1.0
    public var maxHoldSeconds: Double = 30.0
    /// How many times the enabled-exercise sequence repeats during a break.
    public var rounds: Int = 1

    public init() {}

    public var enabledExerciseIds: [String] {
        var ids: [String] = []
        if twentyRuleEnabled { ids.append(BreakExercise.twentyRule.name) }
        if gazeEnabled { ids.append(BreakExercise.gaze.name) }
        if blinkEnabled { ids.append(BreakExercise.blink.name) }
        return ids
    }

    public func scaledHold(_ seconds: Double) -> Double {
        let scaled = seconds * stepHoldScale
        return max(minHoldSeconds, min(maxHoldSeconds, scaled))
    }

    /// Build qilingan exercise sequence — faqat yoqilgan mashqlar, ScaledHold bilan.
    public func buildSequence() -> [BreakExercise] {
        var one: [BreakExercise] = []
        if twentyRuleEnabled { one.append(scale(BreakExercise.twentyRule)) }
        if gazeEnabled      { one.append(scale(BreakExercise.gaze)) }
        if blinkEnabled     { one.append(scale(BreakExercise.blink)) }
        let n = max(1, rounds)
        return n == 1 ? one : Array(repeating: one, count: n).flatMap { $0 }
    }

    private func scale(_ ex: BreakExercise) -> BreakExercise {
        let scaledSteps = ex.steps.map { step in
            BreakExerciseStep(direction: step.direction,
                              holdSeconds: scaledHold(step.holdSeconds),
                              instruction: step.instruction)
        }
        return BreakExercise(name: ex.name, steps: scaledSteps)
    }
}