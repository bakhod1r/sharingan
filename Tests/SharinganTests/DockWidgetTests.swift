import Testing
import Foundation
@testable import SharinganCore

@Suite("Dock widget")
struct DockWidgetTests {

    // MARK: - Settings flag

    @Test("dockWidgetEnabled defaults to on")
    func defaultIsOn() {
        #expect(PomodoroSettings().dockWidgetEnabled == true)
    }

    @Test("dockWidgetEnabled survives a codable round trip")
    func codableRoundTrip() throws {
        var s = PomodoroSettings()
        s.dockWidgetEnabled = false
        let decoded = try JSONDecoder().decode(PomodoroSettings.self,
                                               from: JSONEncoder().encode(s))
        #expect(decoded.dockWidgetEnabled == false)
        #expect(decoded == s)
    }

    @Test("old settings blob without the key decodes to the default")
    func defensiveDecode() throws {
        let decoded = try JSONDecoder().decode(PomodoroSettings.self,
                                               from: Data("{}".utf8))
        #expect(decoded.dockWidgetEnabled == true)
    }
}
