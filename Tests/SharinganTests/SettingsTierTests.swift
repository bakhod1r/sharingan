import Testing
import Foundation
@testable import SharinganCore

@Suite("Settings tier")
struct SettingsTierTests {

    /// Isolated defaults so tests never touch the real app domain.
    private func freshDefaults() -> UserDefaults {
        let name = "tier-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test("fresh install seeds Simple")
    func freshInstallSeedsSimple() {
        let d = freshDefaults()
        SettingsTier.seedIfNeeded(defaults: d)
        #expect(d.string(forKey: SettingsTier.defaultsKey) == "simple")
    }

    @Test("existing settings blob seeds Advanced")
    func existingUserSeedsAdvanced() throws {
        let d = freshDefaults()
        let blob = try JSONEncoder().encode(PomodoroSettings())
        d.set(blob, forKey: PomodoroSettings.defaultsKey)
        SettingsTier.seedIfNeeded(defaults: d)
        #expect(d.string(forKey: SettingsTier.defaultsKey) == "advanced")
    }

    @Test("a stored choice is never overwritten")
    func storedChoiceWins() {
        let d = freshDefaults()
        d.set("simple", forKey: SettingsTier.defaultsKey)
        d.set(Data([0x7b]), forKey: PomodoroSettings.defaultsKey)
        SettingsTier.seedIfNeeded(defaults: d)
        #expect(d.string(forKey: SettingsTier.defaultsKey) == "simple")
    }

    @Test("raw-string resolution falls back to Simple")
    func rawResolution() {
        #expect(SettingsTier.from(nil) == .simple)
        #expect(SettingsTier.from("banana") == .simple)
        #expect(SettingsTier.from("simple") == .simple)
        #expect(SettingsTier.from("advanced") == .advanced)
    }
}
