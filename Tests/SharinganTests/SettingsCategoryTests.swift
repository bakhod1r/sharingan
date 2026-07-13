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

    @Test("hasAdvancedRows is false exactly for General, Voice, and Shortcuts")
    func advancedRows() {
        for cat in SettingsCategory.allCases {
            let expected = !(cat == .general || cat == .voice || cat == .shortcuts)
            #expect(cat.hasAdvancedRows == expected)
        }
    }
}
