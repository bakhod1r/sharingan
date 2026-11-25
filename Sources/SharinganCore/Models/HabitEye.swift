import Foundation

/// The awakening stage of a habit's eye, driven by streak length (in scheduled
/// units: days, or weeks for times-per-week habits). Pure.
public enum HabitEyeStage: Int, CaseIterable, Comparable, Sendable {
    case dormant, tomoe1, tomoe2, tomoe3, mangekyou, eternalMangekyou, rinnegan

    /// Streak length at which each stage is reached.
    public var threshold: Int {
        switch self {
        case .dormant: return 0
        case .tomoe1: return 1
        case .tomoe2: return 3
        case .tomoe3: return 7
        case .mangekyou: return 14
        case .eternalMangekyou: return 30
        case .rinnegan: return 90
        }
    }

    public static func < (a: HabitEyeStage, b: HabitEyeStage) -> Bool { a.rawValue < b.rawValue }

    public static func stage(forStreak streak: Int) -> HabitEyeStage {
        allCases.last { streak >= $0.threshold } ?? .dormant
    }

    /// nil = dormant: render as a plain red iris.
    public var style: SharinganStyle? {
        switch self {
        case .dormant: return nil
        case .tomoe1: return .tomoe1
        case .tomoe2: return .tomoe2
        case .tomoe3: return .classic
        case .mangekyou: return .mangekyou
        case .eternalMangekyou: return .mangekyouEternal
        case .rinnegan: return .rinnegan
        }
    }

    public var awakened: String {
        switch self {
        case .dormant: return "Dormant"
        case .tomoe1: return "1 Tomoe"
        case .tomoe2: return "2 Tomoe"
        case .tomoe3: return "3 Tomoe"
        case .mangekyou: return "Mangekyō"
        case .eternalMangekyou: return "Eternal Mangekyō"
        case .rinnegan: return "Rinnegan"
        }
    }

    /// One stage lower (dormant stays dormant).
    public var lowered: HabitEyeStage { HabitEyeStage(rawValue: max(0, rawValue - 1)) ?? .dormant }

    /// The stage after `streak`'s and how many more units reach it; nil at the top.
    public static func nextStage(after streak: Int) -> (stage: HabitEyeStage, unitsToGo: Int)? {
        guard let next = allCases.first(where: { $0.threshold > streak }) else { return nil }
        return (next, next.threshold - streak)
    }
}
