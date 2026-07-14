import Testing
import Foundation
@testable import SharinganCore

@Suite("Icon spin setting")
struct IconSpinSettingsTests {

    @Test("defaults to spinning")
    func defaultsOn() {
        #expect(PomodoroSettings().animateIcon)
    }

    @Test("survives a codable round trip")
    func roundTrip() throws {
        var s = PomodoroSettings()
        s.animateIcon = false
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(PomodoroSettings.self, from: data)
        #expect(back.animateIcon == false)
    }

    @Test("settings saved before the toggle existed still decode, spinning")
    func decodesLegacyJSON() throws {
        // A blob written by an older build has no animateIcon key at all.
        let s = try JSONDecoder().decode(PomodoroSettings.self, from: Data("{}".utf8))
        #expect(s.animateIcon)
    }
}
