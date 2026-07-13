import Testing
@testable import SharinganCore

@Suite("Settings categories")
struct SettingsCategoryTests {

    @Test("all 9 categories are present, General first")
    func allCasesPresent() {
        #expect(SettingsCategory.allCases.count == 9)
        #expect(SettingsCategory.allCases.first == .general)
    }

    @Test("search keywords still find Voice and Shortcuts")
    func searchFindsVoiceAndShortcuts() {
        #expect(SettingsCategory.voice.matches("pitch"))
        #expect(SettingsCategory.shortcuts.matches("hotkey"))
    }

    /// The notch HUD's settings live on the Timer page (next to the floating
    /// timer and the menu bar — the other surfaces the timer paints itself on),
    /// so the words a user would actually search for have to lead there.
    @Test("search finds the notch HUD on the Timer page")
    func searchFindsTheNotch() {
        for query in ["notch", "island", "hud", "ears", "camera housing"] {
            #expect(SettingsCategory.timer.matches(query))
        }
    }

    @Test("hasAdvancedRows is false exactly for General, Voice, and Shortcuts")
    func advancedRows() {
        for cat in SettingsCategory.allCases {
            let expected = !(cat == .general || cat == .voice || cat == .shortcuts)
            #expect(cat.hasAdvancedRows == expected)
        }
    }
}
