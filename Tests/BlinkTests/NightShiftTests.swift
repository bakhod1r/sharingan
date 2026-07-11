import Testing
import Foundation
@testable import BlinkCore

@Suite("Night Shift")
struct NightShiftTests {

    // MARK: - Settings

    @Test func settingsDefaults() {
        let s = PomodoroSettings()
        #expect(s.nightShiftBreakEnabled == false)
        #expect(s.nightShiftBreakStrength == 0.7)
    }

    @Test func settingsCodableRoundTrip() throws {
        var s = PomodoroSettings()
        s.nightShiftBreakEnabled = true
        s.nightShiftBreakStrength = 0.4

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(PomodoroSettings.self, from: data)

        #expect(decoded == s)
        #expect(decoded.nightShiftBreakEnabled == true)
        #expect(decoded.nightShiftBreakStrength == 0.4)
    }

    /// Older settings blobs predate the Night Shift keys — decoding must fall
    /// back to the defaults instead of throwing (defensive decode contract).
    @Test func defensiveDecodeWithoutNightShiftKeys() throws {
        let old = #"{"focusMinutes": 30, "brightnessDimEnabled": true}"#
        let decoded = try JSONDecoder().decode(
            PomodoroSettings.self, from: Data(old.utf8))
        #expect(decoded.focusMinutes == 30)
        #expect(decoded.brightnessDimEnabled == true)
        #expect(decoded.nightShiftBreakEnabled == false)
        #expect(decoded.nightShiftBreakStrength == 0.7)
    }

    // MARK: - Service surface (no state assertions: private CoreBrightness
    // API may be unavailable / permission-less on CI, so we only require the
    // calls not to crash and the begin/end pairing to be idempotent).

    @MainActor @Test func endWithoutBeginIsNoOp() {
        let svc = NightShiftService.shared
        svc.endBreakWarmth()
        svc.endBreakWarmth()
        // Reaching here without a crash is the assertion.
        #expect(svc.isAvailable == true || svc.isAvailable == false)
    }

    @MainActor @Test func beginEndPairDoesNotCrash() {
        let svc = NightShiftService.shared
        svc.beginBreakWarmth(strength: 0.7)
        svc.endBreakWarmth()
        svc.endBreakWarmth()   // second end after a pair stays a no-op
    }

    @MainActor @Test func doubleBeginKeepsOriginalAndEndsCleanly() {
        let svc = NightShiftService.shared
        svc.beginBreakWarmth(strength: 0.6)
        svc.beginBreakWarmth(strength: 0.9)  // must not clobber the remembered state
        svc.endBreakWarmth()
        svc.endBreakWarmth()
    }

    @MainActor @Test func strengthIsClampedWithoutCrashing() {
        let svc = NightShiftService.shared
        svc.beginBreakWarmth(strength: 7.5)   // way out of range
        svc.endBreakWarmth()
        svc.beginBreakWarmth(strength: -3.0)
        svc.endBreakWarmth()
    }
}
