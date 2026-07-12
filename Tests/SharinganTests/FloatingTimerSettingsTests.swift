import Testing
import Foundation
@testable import SharinganCore

@Suite("Floating timer settings")
struct FloatingTimerSettingsTests {

    // MARK: - Size presets

    @Test("preset pixel mapping is sane and strictly ordered")
    func presetPixelsSane() {
        for size in FloatingTimerSize.allCases {
            #expect(size.width > 0)
            #expect(size.height > 0)
        }
        #expect(FloatingTimerSize.small.width < FloatingTimerSize.medium.width)
        #expect(FloatingTimerSize.medium.width < FloatingTimerSize.large.width)
        #expect(FloatingTimerSize.small.height < FloatingTimerSize.medium.height)
        #expect(FloatingTimerSize.medium.height < FloatingTimerSize.large.height)
    }

    @Test("FloatingTimerSize survives a codable round trip")
    func sizeCodableRoundTrip() throws {
        for size in FloatingTimerSize.allCases {
            let decoded = try JSONDecoder().decode([FloatingTimerSize].self,
                                                   from: JSONEncoder().encode([size]))
            #expect(decoded == [size])
        }
    }

    // MARK: - Settings defaults & round trip

    @Test("new floating fields default to today's look")
    func defaults() {
        let s = PomodoroSettings()
        #expect(s.floatingSize == .medium)
        #expect(s.floatingShowDots == true)
        #expect(s.floatingShowTask == true)
    }

    @Test("floating fields survive a settings codable round trip")
    func settingsRoundTrip() throws {
        var s = PomodoroSettings()
        s.floatingSize = .large
        s.floatingShowDots = false
        s.floatingShowTask = false
        let decoded = try JSONDecoder().decode(PomodoroSettings.self,
                                               from: JSONEncoder().encode(s))
        #expect(decoded.floatingSize == .large)
        #expect(decoded.floatingShowDots == false)
        #expect(decoded.floatingShowTask == false)
        #expect(decoded == s)
    }

    // MARK: - Defensive decode

    @Test("old settings blob without the keys decodes to the defaults")
    func defensiveDecodeFromEmptyBlob() throws {
        let decoded = try JSONDecoder().decode(PomodoroSettings.self,
                                               from: Data("{}".utf8))
        #expect(decoded.floatingSize == .medium)
        #expect(decoded.floatingShowDots == true)
        #expect(decoded.floatingShowTask == true)
    }

    @Test("legacy compact flag maps to the small preset when no preset stored")
    func legacyCompactMigration() throws {
        let decoded = try JSONDecoder().decode(
            PomodoroSettings.self,
            from: Data(#"{"floatingCompact": true}"#.utf8))
        #expect(decoded.floatingSize == .small)
    }

    @Test("garbage floatingSize raw value falls back to the default")
    func garbageSizeFallsBack() throws {
        let decoded = try JSONDecoder().decode(
            PomodoroSettings.self,
            from: Data(#"{"floatingSize": "gigantic"}"#.utf8))
        #expect(decoded.floatingSize == .medium)
    }
}
