import Testing
import Foundation
@testable import SharinganCore

@Suite("Attention settings")
struct AttentionSettingsTests {
    private final class FakeKV: KeyValueStore {
        var values: [String: Any] = [:]
        func object(forKey key: String) -> Any? { values[key] }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
        @discardableResult func synchronize() -> Bool { true }
    }

    private let cal = AttentionCalibration(yawMin: -10, yawMax: 10, pitchMin: -8, pitchMax: 8,
                                           gazeXMin: -0.3, gazeXMax: 0.3,
                                           gazeYMin: -0.2, gazeYMax: 0.2,
                                           createdAt: Date(timeIntervalSince1970: 1_000))

    @Test func legacyJSONDecodesToDefaults() throws {
        let s = try JSONDecoder().decode(PomodoroSettings.self, from: Data("{}".utf8))
        #expect(s.focusAttentionEnabled == false)
        #expect(s.focusAttentionSensitivity == .medium)
        #expect(s.focusAttentionGrace == 2)
        #expect(s.focusAttentionSound == false)
        #expect(s.attentionCalibration == nil)
    }

    @Test func roundTripKeepsAttentionFields() throws {
        var s = PomodoroSettings()
        s.focusAttentionEnabled = true
        s.focusAttentionSensitivity = .strict
        s.focusAttentionGrace = 4
        s.attentionCalibration = cal
        let back = try JSONDecoder().decode(PomodoroSettings.self,
                                            from: JSONEncoder().encode(s))
        #expect(back.focusAttentionEnabled)
        #expect(back.focusAttentionSensitivity == .strict)
        #expect(back.focusAttentionGrace == 4)
        #expect(back.attentionCalibration == cal)
    }

    @Test func remoteBlobKeepsLocalCalibration() throws {
        let suite = "AttentionSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var local = PomodoroSettings()
        local.attentionCalibration = cal
        defaults.set(try JSONEncoder().encode(local), forKey: PomodoroSettings.defaultsKey)

        var remote = PomodoroSettings()
        remote.focusAttentionEnabled = true
        remote.attentionCalibration = nil
        let kv = FakeKV()
        kv.values[PomodoroSettings.defaultsKey] = try JSONEncoder().encode(remote)

        SettingsSync.applyRemote(kv: kv, defaults: defaults)

        let applied = try JSONDecoder().decode(
            PomodoroSettings.self,
            from: try #require(defaults.data(forKey: PomodoroSettings.defaultsKey)))
        #expect(applied.focusAttentionEnabled)       // remote intent applied
        #expect(applied.attentionCalibration == cal) // local calibration kept
    }
}
