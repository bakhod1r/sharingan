import Foundation

/// How the break screen chooses its face and eye: the fixed pair from
/// Settings, or a random draw from a user-picked pool.
public enum BreakFaceEyeMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case fixed
    case random

    public var id: String { rawValue }
    public var label: String { self == .fixed ? "Fixed" : "Random" }
}

/// One entry of the random eye pool. Encoded as a single string: "original"
/// or the `SharinganStyle` raw value.
public enum BreakEyeChoice: Hashable, Codable, Sendable, Identifiable {
    case original
    case sharingan(SharinganStyle)

    /// All offered choices: Original first, then every Sharingan style.
    public static var allChoices: [BreakEyeChoice] {
        [.original] + SharinganStyle.allCases.map { .sharingan($0) }
    }

    public var token: String {
        switch self {
        case .original:         return "original"
        case .sharingan(let s): return s.rawValue
        }
    }

    public init?(token: String) {
        if token == "original" { self = .original; return }
        guard let s = SharinganStyle(rawValue: token) else { return nil }
        self = .sharingan(s)
    }

    public var id: String { token }

    public var label: String {
        switch self {
        case .original:         return "Original"
        case .sharingan(let s): return s.label
        }
    }

    /// The iris kind this choice draws.
    public var iris: BreakIrisStyle {
        switch self {
        case .original:    return .original
        case .sharingan:   return .sharingan
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let v = BreakEyeChoice(token: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "unknown eye choice \(raw)"))
        }
        self = v
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(token)
    }
}

/// When a random look is re-drawn.
public enum BreakRandomChange: String, Codable, CaseIterable, Identifiable, Sendable {
    case eachBreak
    case eachStep

    public var id: String { rawValue }
    public var label: String { self == .eachBreak ? "Each break" : "Each step" }
}

/// Whether both eyes of the pair share one draw.
public enum BreakRandomPairing: String, Codable, CaseIterable, Identifiable, Sendable {
    case same
    case separate

    public var id: String { rawValue }
    public var label: String { self == .same ? "Same both" : "Separate" }
}

/// What the break screen actually draws: face, iris kind and per-eye styles.
/// `rightStyle == nil` means the right eye mirrors `leftStyle`.
public struct BreakLook: Equatable, Sendable {
    public var face: BreakEyeShape
    public var iris: BreakIrisStyle
    public var leftStyle: SharinganStyle
    public var rightStyle: SharinganStyle?

    public init(face: BreakEyeShape, iris: BreakIrisStyle,
                leftStyle: SharinganStyle, rightStyle: SharinganStyle?) {
        self.face = face
        self.iris = iris
        self.leftStyle = leftStyle
        self.rightStyle = rightStyle
    }
}

/// Pure picker for the break look. The random source is injected.
///
/// Mapping: `.original` => iris `.original` (style irrelevant, the Fixed
/// style is kept); `.sharingan(s)` => iris `.sharingan`, style `s`.
/// Iris is one value per pair, so with `.separate` pairing the right eye is
/// drawn only from choices of the same iris kind as the left one; the pair
/// never mixes Original and Sharingan.
public enum BreakFaceEyeRandomizer {

    /// The look from the Fixed settings.
    public static func fixedLook(_ s: PomodoroSettings) -> BreakLook {
        BreakLook(face: s.breakEyeShape, iris: s.breakIrisStyle,
                  leftStyle: s.sharinganStyle, rightStyle: s.sharinganStyleRight)
    }

    private static func isUsable(_ s: PomodoroSettings) -> Bool {
        s.breakFaceEyeMode == .random && !s.breakRandomFaces.isEmpty && !s.breakRandomEyes.isEmpty
    }

    /// Fixed mode, or an empty pool, returns the fixed look. Random avoids
    /// returning `previous` when more than one look is possible.
    public static func look<G: RandomNumberGenerator>(
        settings s: PomodoroSettings, previous: BreakLook?, using rng: inout G
    ) -> BreakLook {
        guard isUsable(s) else { return fixedLook(s) }
        let faces = unique(s.breakRandomFaces)
        let multiple = faces.count * eyeCombinationCount(s) > 1
        var result = draw(settings: s, face: faces.randomElement(using: &rng)!, using: &rng)
        guard multiple, let previous else { return result }
        var tries = 0
        while result == previous && tries < 64 {
            result = draw(settings: s, face: faces.randomElement(using: &rng)!, using: &rng)
            tries += 1
        }
        return result
    }

    /// Re-pick the eyes only; the face of `current` stays (a face change
    /// mid-break would replay the intro/outro).
    public static func eyesOnly<G: RandomNumberGenerator>(
        settings s: PomodoroSettings, current: BreakLook, using rng: inout G
    ) -> BreakLook {
        guard isUsable(s) else { return current }
        let multiple = eyeCombinationCount(s) > 1
        var result = draw(settings: s, face: current.face, using: &rng)
        guard multiple else { return result }
        var tries = 0
        while result == current && tries < 64 {
            result = draw(settings: s, face: current.face, using: &rng)
            tries += 1
        }
        return result
    }

    private static func unique<T: Hashable>(_ a: [T]) -> [T] {
        var seen = Set<T>()
        return a.filter { seen.insert($0).inserted }
    }

    private static func eyeCombinationCount(_ s: PomodoroSettings) -> Int {
        let eyes = unique(s.breakRandomEyes)
        guard s.breakRandomPairing == .separate else { return eyes.count }
        return eyes.reduce(0) { n, l in n + eyes.filter { $0.iris == l.iris }.count }
    }

    private static func draw<G: RandomNumberGenerator>(
        settings s: PomodoroSettings, face: BreakEyeShape, using rng: inout G
    ) -> BreakLook {
        let eyes = unique(s.breakRandomEyes)
        let left = eyes.randomElement(using: &rng)!
        var right = left
        if s.breakRandomPairing == .separate {
            right = eyes.filter { $0.iris == left.iris }.randomElement(using: &rng) ?? left
        }
        let leftStyle = style(of: left, fallback: s.sharinganStyle)
        let rightStyle: SharinganStyle?
        if s.breakRandomPairing == .same {
            rightStyle = nil
        } else {
            rightStyle = style(of: right, fallback: s.sharinganStyleRight ?? s.sharinganStyle)
        }
        return BreakLook(face: face, iris: left.iris, leftStyle: leftStyle, rightStyle: rightStyle)
    }

    private static func style(of c: BreakEyeChoice, fallback: SharinganStyle) -> SharinganStyle {
        if case .sharingan(let s) = c { return s }
        return fallback
    }
}
