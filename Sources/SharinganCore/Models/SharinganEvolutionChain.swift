import Foundation

/// The break-screen awakening order plus the per-eye start rule, kept pure in
/// core so it is unit-testable (the view-side `PatternEvolution` consumes it).
public enum SharinganEvolutionChain {
    /// One tomoe → two → three, then the Mangekyō family, ending on the
    /// Rinnegan before wrapping around.
    public static let chain: [SharinganStyle] = [
        .tomoe1, .tomoe2, .classic,
        .mangekyou, .mangekyouEternal, .itachi, .mangekyouKamui,
        .sixStar, .blade, .fourBlade, .madara, .shuriken, .swirl,
        .triangleTomoe, .ringCrescents, .orbit, .crescent, .rinnegan,
    ]

    /// True when the user configured a different style per eye.
    public static func eyesDiffer(left: SharinganStyle, right: SharinganStyle) -> Bool {
        left != right
    }

    /// Where an eye's walk starts. With one shared style (the default) both
    /// eyes start at the chain's head, as before. When the eyes are configured
    /// differently each walks from its own base (a style outside the chain
    /// starts at the head).
    public static func startIndex(base: SharinganStyle, eyesDiffer: Bool) -> Int {
        guard eyesDiffer else { return 0 }
        return chain.firstIndex(of: base) ?? 0
    }

    /// The style an eye shows after `count` completed steps.
    public static func style(base: SharinganStyle, eyesDiffer: Bool, count: Int) -> SharinganStyle {
        let i = startIndex(base: base, eyesDiffer: eyesDiffer)
        let n = chain.count
        return chain[(((i + count) % n) + n) % n]
    }
}
