import SwiftUI

extension Color {
    public static let paletteFocusStart = Color(red: 0.36, green: 0.62, blue: 1.00)
    public static let paletteFocusEnd   = Color(red: 0.20, green: 0.34, blue: 0.98)
    public static let paletteBreakStart = Color(red: 0.30, green: 0.96, blue: 0.78)
    public static let paletteBreakEnd   = Color(red: 0.16, green: 0.74, blue: 0.66)
    public static let paletteLongStart  = Color(red: 0.86, green: 0.74, blue: 1.00)
    public static let paletteLongEnd    = Color(red: 0.62, green: 0.42, blue: 0.98)
    public static let paletteMutedStart = Color(red: 0.55, green: 0.57, blue: 0.62)
    public static let paletteMutedEnd   = Color(red: 0.34, green: 0.36, blue: 0.42)

    public static let glassTint = Color.white.opacity(0.06)
    public static let glassStroke = Color.white.opacity(0.18)
    public static let glassHighlight = Color.white.opacity(0.55)

    /// Parse a `#RRGGBB` (or `#RGB`) hex string into a Color. Shared so task
    /// category colors render consistently across every view.
    public init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255,
                  opacity: 1)
    }
}