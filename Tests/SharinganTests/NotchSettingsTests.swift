import Testing
import Foundation
@testable import SharinganCore

@Suite("Notch settings")
struct NotchSettingsTests {

    @Test("defaults: HUD on, both ears, activities on")
    func defaults() {
        let s = PomodoroSettings()
        #expect(s.notchHUDEnabled)
        #expect(s.notchEars == .both)
        #expect(s.notchLiveActivity)
    }

    @Test("settings survive a codable round trip")
    func roundTrip() throws {
        var s = PomodoroSettings()
        s.notchHUDEnabled = false
        s.notchEars = .trailingOnly
        s.notchLiveActivity = false
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(PomodoroSettings.self, from: data)
        #expect(back.notchHUDEnabled == false)
        #expect(back.notchEars == .trailingOnly)
        #expect(back.notchLiveActivity == false)
    }

    @Test("settings saved before the notch HUD existed still decode")
    func decodesLegacyJSON() throws {
        // A settings blob written by an older build has no notch keys at all.
        var s = PomodoroSettings()
        s.longBreakMinutes = 12
        let data = try JSONEncoder().encode(s)
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "notchHUDEnabled")
        json.removeValue(forKey: "notchEars")
        json.removeValue(forKey: "notchLiveActivity")
        let legacy = try JSONSerialization.data(withJSONObject: json)

        let back = try JSONDecoder().decode(PomodoroSettings.self, from: legacy)
        #expect(back.longBreakMinutes == 12)   // the rest of the blob survived
        #expect(back.notchHUDEnabled)          // and the new keys took their defaults
        #expect(back.notchEars == .both)
    }

    @Test("every ears mode has a label and is codable")
    func earsModes() throws {
        for mode in NotchEarsMode.allCases {
            #expect(!mode.label.isEmpty)
            let data = try JSONEncoder().encode([mode])
            #expect(try JSONDecoder().decode([NotchEarsMode].self, from: data) == [mode])
        }
    }
}
