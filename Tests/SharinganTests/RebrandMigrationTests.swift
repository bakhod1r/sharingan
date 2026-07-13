import Testing
import Foundation
@testable import SharinganCore

@Suite("Rebrand migration")
struct RebrandMigrationTests {

    private func freshDefaults() -> UserDefaults {
        let name = "rebrand-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func tempBase() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rebrand-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("old defaults values are copied to new keys, old kept")
    func defaultsCopied() {
        let d = freshDefaults()
        d.set(Data([0x7b]), forKey: "com.blink.settings")
        d.set(Data([0x5b]), forKey: "com.blink.stats")
        d.set(120.0, forKey: "blink.floating.x")
        RebrandMigration.migrateDefaults(d)
        #expect(d.data(forKey: PomodoroSettings.defaultsKey) == Data([0x7b]))
        #expect(d.data(forKey: "com.sharingan.stats") == Data([0x5b]))
        #expect(d.double(forKey: "sharingan.floating.x") == 120.0)
        #expect(d.data(forKey: "com.blink.settings") != nil)  // kept
    }

    @Test("existing new-key values are never overwritten")
    func newKeyWins() {
        let d = freshDefaults()
        d.set(Data([0x01]), forKey: "com.sharingan.settings")
        d.set(Data([0x02]), forKey: "com.blink.settings")
        RebrandMigration.migrateDefaults(d)
        #expect(d.data(forKey: "com.sharingan.settings") == Data([0x01]))
    }

    @Test("no-op on a fresh install")
    func freshNoop() {
        let d = freshDefaults()
        RebrandMigration.migrateDefaults(d)
        #expect(d.data(forKey: PomodoroSettings.defaultsKey) == nil)
    }

    @Test("Blink app-support dir is renamed to Sharingan")
    func dirMoved() throws {
        let base = try tempBase()
        let old = base.appendingPathComponent("Blink", isDirectory: true)
        try FileManager.default.createDirectory(
            at: old.appendingPathComponent("cli"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: old.appendingPathComponent("tasks.json"))
        RebrandMigration.migrateAppSupport(base: base)
        let new = base.appendingPathComponent("Sharingan", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: new.appendingPathComponent("tasks.json").path))
        #expect(!FileManager.default.fileExists(atPath: old.path))
    }

    @Test("dir move never clobbers an existing Sharingan dir")
    func dirMoveNoClobber() throws {
        let base = try tempBase()
        let old = base.appendingPathComponent("Blink", isDirectory: true)
        let new = base.appendingPathComponent("Sharingan", isDirectory: true)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: new.appendingPathComponent("tasks.json"))
        RebrandMigration.migrateAppSupport(base: base)
        let kept = try Data(contentsOf: new.appendingPathComponent("tasks.json"))
        #expect(String(decoding: kept, as: UTF8.self) == "new")
    }

    @Test("fresh DND defaults say Sharingan")
    func dndDefaults() {
        let s = PomodoroSettings()
        #expect(s.dndShortcutOn == "Sharingan Focus On")
        #expect(s.dndShortcutOff == "Sharingan Focus Off")
    }
}
