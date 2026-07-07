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

extension View {
    /// The one canonical group-label style: uppercase, tracked, tertiary color.
    func dsSectionLabel() -> some View {
        self.font(.system(.caption2, design: .rounded).weight(.heavy))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(Color.dsSecondary)
    }
}
