import Foundation
import Testing

/// Every interactive control in Settings must use the liquid-glass primitives
/// (GlassMenuPicker, GlassSlider, GlassSegmentedPicker, `.glass`, `.glassSwitch`).
/// Plain AppKit-styled controls render as opaque system chrome on the glass panels.
@Suite struct GlassControlsGuardTests {
    private static let files = [
        "SettingsView.swift", "SettingsSyncSection.swift",
        "FaceEyeSettingsSection.swift", "ReminderRow.swift",
    ]
    private static let banned = [
        ".pickerStyle(.menu)", ".pickerStyle(.segmented)",
        ".buttonStyle(.bordered)", ".toggleStyle(.switch)",
    ]

    @Test func settingsUseGlassControlsOnly() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for name in Self.files {
            let url = root.appendingPathComponent("Sources/Sharingan/Views/\(name)")
            let text = try String(contentsOf: url, encoding: .utf8)
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("//") { continue }
                for token in Self.banned {
                    #expect(!t.contains(token), "\(name): \(token) must be a glass control — \(t)")
                }
                var rest = Substring(t)
                while let r = rest.range(of: "Slider(") {
                    let before = rest[rest.startIndex..<r.lowerBound]
                    #expect(before.hasSuffix("Glass"), "\(name): bare Slider( — use GlassSlider — \(t)")
                    rest = rest[r.upperBound...]
                }
            }
        }
    }
}
