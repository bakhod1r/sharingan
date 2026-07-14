import SwiftUI

/// Central design tokens. The app had accumulated a dozen ad-hoc corner radii,
/// five section-header treatments, and a scatter of white-opacity values; these
/// tokens give every surface one shared scale so the UI reads as one language.
enum DS {
    /// Corner-radius scale — map every surface to one of these four tiers.
    enum Radius {
        static let sm: CGFloat = 8    // chips, small controls
        static let md: CGFloat = 12   // rows, cards
        static let lg: CGFloat = 16   // panels, composers
        static let xl: CGFloat = 20   // large containers, columns
    }

    /// 4pt spacing scale.
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
    }

    /// Motion tokens — one shared animation "hand". Every surface had its own
    /// hand-tuned spring/ease before this (20+ distinct timings); these five
    /// roles cover them all. Deliberate one-offs (breathing loops, celebration
    /// flights, continuous TimelineView drivers) stay hand-tuned.
    enum Motion {
        /// Numeric counters, small state flips.
        static let snappy = Animation.snappy(duration: 0.3)
        /// Tab switches, list insert/remove, layout moves, drag targets.
        static let standard = Animation.spring(response: 0.35, dampingFraction: 0.85)
        /// Fades, disclosures, section cross-fades.
        static let gentle = Animation.easeInOut(duration: 0.25)
        /// Hover highlights and press states.
        static let hover = Animation.easeOut(duration: 0.15)
        /// Streak / completion celebrations.
        static let celebrate = Animation.bouncy(duration: 0.45)
    }
}

extension Color {
    // Text ramp on the app's dark surfaces. Three deliberate tiers instead of
    // both `.secondary` and a dozen raw opacities.
    static let dsPrimary   = Color.white
    static let dsSecondary = Color.white.opacity(0.62)
    static let dsTertiary  = Color.white.opacity(0.42)
    // Chrome fills.
    static let dsFill       = Color.white.opacity(0.05)
    static let dsFillStrong = Color.white.opacity(0.10)
    static let dsHairline   = Color.white.opacity(0.09)
}

extension Font {
    // One rounded type ramp. Every surface picked its own `.system(size:)` before
    // this — 170-odd ad-hoc calls with no shared scale. These roles are built on
    // Dynamic Type text styles so they scale with the user's accessibility text
    // size, while staying uniformly `.rounded` to match the app's voice.
    static let dsDisplay  = Font.system(.largeTitle, design: .rounded).weight(.bold)   // screen titles
    static let dsTitle    = Font.system(.title2, design: .rounded).weight(.bold)       // section titles
    static let dsHeadline = Font.system(.headline, design: .rounded)                   // emphasis (semibold)
    static let dsBody     = Font.system(.body, design: .rounded)                       // default text
    static let dsCallout  = Font.system(.callout, design: .rounded).weight(.medium)    // list item text
    static let dsCaption  = Font.system(.caption, design: .rounded).weight(.medium)    // secondary/help
    static let dsMicro    = Font.system(.caption2, design: .rounded).weight(.semibold) // meta, badges

    /// The one countdown-numeral style — a light, rounded, monospaced-digit face
    /// used at every size (76pt hero, menu-bar strip, break screen, Dock widget)
    /// so the clock reads as one element across surfaces. Fixed size
    /// because the digits are laid out to the pixel; weight stays constant.
    static func dsTimer(_ size: CGFloat) -> Font {
        .system(size: size, weight: .light, design: .rounded).monospacedDigit()
    }
}

extension View {
    /// The one canonical group-label style: uppercase, tracked, tertiary color.
    func dsSectionLabel() -> some View {
        self.font(.system(.caption2, design: .rounded).weight(.heavy))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(Color.dsSecondary)
    }
}
