import Foundation

/// Horizontal travel of the MoveEyes iris across the almond opening (pure math; the view feeds in
/// the sampled aperture). At full left / right the iris sits as far toward the tip as the opening
/// is still tall enough to show most of it.
public enum MoveEyeTravel {
    /// The iris centre may go as far out as the opening's half-height is at least this fraction
    /// of the iris radius.
    public static let minVisibleFraction = 0.8

    /// Screen position (0...1 across the eye frame) of the iris centre for gaze `dx` (-1...1).
    /// - `irisUnitR`: iris radius in the same unit as `halfHeight`.
    /// - `halfHeight`: half-height of the opening at screen position u (0...1). Pass the smaller of
    ///   both mirrored eyes so they travel equally.
    public static func uScreen(dx: Double, irisUnitR: Double, halfHeight: (Double) -> Double) -> Double {
        let g = max(-1, min(1, dx))
        guard g != 0 else { return 0.5 }
        let need = minVisibleFraction * irisUnitR
        let dir = g < 0 ? -1.0 : 1.0
        var reach = 0.0
        let step = 0.005
        while reach + step <= 0.5, halfHeight(0.5 + dir * (reach + step)) >= need { reach += step }
        return 0.5 + g * reach
    }
}
