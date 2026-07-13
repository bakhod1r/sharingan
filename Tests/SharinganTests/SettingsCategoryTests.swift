import Testing
@testable import SharinganCore

@Suite("Settings categories")
struct SettingsCategoryTests {

    @Test("Simple root shows exactly 7 categories, without Voice/Shortcuts")
    func simpleVisibility() {
        let visible = SettingsCategory.visible(in: .simple)
        #expect(visible.count == 7)
        #expect(!visible.contains(.voice))
        #expect(!visible.contains(.shortcuts))
    }

    @Test("Advanced root shows all 9 in declaration order")
    func advancedVisibility() {
        #expect(SettingsCategory.visible(in: .advanced) == SettingsCategory.allCases)
    }

    @Test("only Voice and Shortcuts are advanced-only categories")
    func tierMetadata() {
        for cat in SettingsCategory.allCases {
            let expected: SettingsTier =
                (cat == .voice || cat == .shortcuts) ? .advanced : .simple
            #expect(cat.tier == expected)
        }
    }

    @Test("search keywords still find advanced-only categories")
    func searchFindsAdvanced() {
        #expect(SettingsCategory.voice.matches("pitch"))
        #expect(SettingsCategory.shortcuts.matches("hotkey"))
    }

    @Test("every category except General has advanced-only rows")
    func advancedRows() {
        #expect(!SettingsCategory.general.hasAdvancedRows)
        for cat in SettingsCategory.allCases where cat != .general {
            #expect(cat.hasAdvancedRows)
        }
    }
}
