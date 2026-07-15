import Testing
@testable import SharinganCore

@Suite("Settings categories")
struct SettingsCategoryTests {

    @Test("all 11 categories are present, Integrations follows General, Notch right after Timer")
    func allCasesPresent() {
        #expect(SettingsCategory.allCases.count == 11)
        #expect(SettingsCategory.allCases.first == .general)
        let cases = SettingsCategory.allCases
        #expect(cases.dropFirst().first == .integrations)
        let timerIdx = cases.firstIndex(of: .timer)!
        #expect(cases[timerIdx + 1] == .notch)
    }

    @Test("search keywords still find Voice and Shortcuts")
    func searchFindsVoiceAndShortcuts() {
        #expect(SettingsCategory.voice.matches("pitch"))
        #expect(SettingsCategory.shortcuts.matches("hotkey"))
    }

    /// The notch HUD is its own category now, so the words a user would search
    /// for — the island, the ears, the camera housing — route to `.notch`, and
    /// no longer to Timer, which handed those keywords over.
    @Test("search finds the notch HUD on its own page, not Timer")
    func searchFindsTheNotch() {
        for query in ["notch", "island", "hud", "ears", "camera housing", "menu bar"] {
            #expect(SettingsCategory.notch.matches(query))
            #expect(!SettingsCategory.timer.matches(query))
        }
    }

    @Test("Timer keeps its own (non-notch) keywords")
    func timerKeepsItsKeywords() {
        for query in ["dock", "opacity", "repeat", "today panel"] {
            #expect(SettingsCategory.timer.matches(query))
        }
    }

    @Test("Notch has a label, subtitle, and icon")
    func notchHasChrome() {
        #expect(!SettingsCategory.notch.title.isEmpty)
        #expect(!SettingsCategory.notch.subtitle.isEmpty)
        #expect(!SettingsCategory.notch.icon.isEmpty)
    }

    @Test("hasAdvancedRows is false exactly for General, Voice, and Shortcuts")
    func advancedRows() {
        for cat in SettingsCategory.allCases {
            let expected = !(cat == .general || cat == .integrations || cat == .voice || cat == .shortcuts)
            #expect(cat.hasAdvancedRows == expected)
        }
    }

    @Test("Integrations is searchable by Jira terms")
    func integrationsKeywords() {
        for query in ["jira", "worklog", "api token", "transition"] {
            #expect(SettingsCategory.integrations.matches(query))
        }
    }
}
