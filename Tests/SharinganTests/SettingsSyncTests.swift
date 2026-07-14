import XCTest
@testable import SharinganCore

/// In-memory KeyValueStore so no test ever touches the real
/// NSUbiquitousKeyValueStore (which silently no-ops without an iCloud
/// entitlement — exactly the kind of "passes on my machine" dependency
/// tests must not have).
private final class FakeKV: KeyValueStore {
    var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) {
        if let value { values[key] = value } else { values.removeValue(forKey: key) }
    }
    @discardableResult func synchronize() -> Bool { true }
}

final class SettingsSyncTests: XCTestCase {

    private func freshDefaults(_ name: String) -> UserDefaults {
        let suite = "SettingsSyncTests.\(name)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    // MARK: - Push

    func testOnlyAllowlistedKeysArePushed() throws {
        let defaults = freshDefaults(#function)
        // Allowlisted: the settings JSON blob and a task-sort intent.
        let blob = try JSONEncoder().encode(PomodoroSettings())
        defaults.set(blob, forKey: PomodoroSettings.defaultsKey)
        defaults.set("dueDate", forKey: "tasks.sortMode")
        // Not allowlisted: machine-local widget position and a random key.
        defaults.set(412.0, forKey: "sharingan.dockwidget.x")
        defaults.set("secret", forKey: "internal.debugFlag")

        let kv = FakeKV()
        SettingsSync.pushLocal(defaults: defaults, kv: kv)

        XCTAssertEqual(kv.values[PomodoroSettings.defaultsKey] as? Data, blob)
        XCTAssertEqual(kv.values["tasks.sortMode"] as? String, "dueDate")
        XCTAssertNil(kv.values["sharingan.dockwidget.x"])
        XCTAssertNil(kv.values["internal.debugFlag"])
    }

    func testPushSkipsKeysWithNoLocalValue() {
        let defaults = freshDefaults(#function)
        defaults.set("manual", forKey: "tasks.sortMode")

        let kv = FakeKV()
        SettingsSync.pushLocal(defaults: defaults, kv: kv)

        XCTAssertEqual(kv.values.count, 1)
        XCTAssertNil(kv.values["report.sortMode"])
    }

    // MARK: - Allowlist shape

    // Machine-local settings (window/widget positions, NSStatusItem slots,
    // one-shot migration flags, caches, the sync toggle itself) must never
    // travel — they'd fight between Macs.
    func testDeviceLocalKeysAreNotSynced() {
        let banned = [
            "sharingan.dockwidget.x",
            "sharingan.dockwidget.y",
            "sharingan.todayPanel.origin",
            "sidebar.collapsed.categories",
            "sidebar.collapsed.tags",
            "sidebar.collapsed.priority",
            "sharingan.migration.notificationsSwept",
            "com.sharingan.cliSnapshot",
            "com.sharingan.stats",
            "sharingan.focusQueue",
            "sync.enabled",
            "onboarding.seen",
        ]
        for key in banned {
            XCTAssertFalse(SettingsSync.syncedKeys.contains(key),
                           "\(key) is machine-local and must not sync")
        }
        XCTAssertFalse(SettingsSync.syncedKeys.contains { $0.hasPrefix("window.") })
        XCTAssertFalse(SettingsSync.syncedKeys.contains { $0.hasPrefix("NSStatusItem") })
        XCTAssertFalse(SettingsSync.syncedKeys.contains { $0.hasPrefix("SU") },
                       "Sparkle bookkeeping must not sync")
    }

    func testAllowlistCoversTheRealIntentKeys() {
        let wanted = [
            PomodoroSettings.defaultsKey,           // the whole settings blob
            "tasks.sortMode",
            "tasks.subtaskSortMode",
            "report.sortMode",
            TaskStore.preReminderDefaultsKey,
        ]
        for key in wanted {
            XCTAssertTrue(SettingsSync.syncedKeys.contains(key), "missing \(key)")
        }
    }

    // MARK: - Apply remote

    func testRemoteValueOverwritesLocalForAllowlistedKey() {
        let defaults = freshDefaults(#function)
        defaults.set("manual", forKey: "tasks.sortMode")
        let kv = FakeKV()
        kv.values["tasks.sortMode"] = "priority"

        SettingsSync.applyRemote(kv: kv, defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: "tasks.sortMode"), "priority")
    }

    func testRemoteValueForNonAllowlistedKeyIsIgnored() {
        let defaults = freshDefaults(#function)
        let kv = FakeKV()
        kv.values["sharingan.dockwidget.x"] = 999.0
        kv.values["sharingan.migration.notificationsSwept"] = true

        SettingsSync.applyRemote(kv: kv, defaults: defaults)

        XCTAssertNil(defaults.object(forKey: "sharingan.dockwidget.x"))
        XCTAssertNil(defaults.object(forKey: "sharingan.migration.notificationsSwept"))
    }

    func testApplyRemoteLeavesLocalWhenRemoteHasNoValue() {
        let defaults = freshDefaults(#function)
        defaults.set("manual", forKey: "tasks.sortMode")

        SettingsSync.applyRemote(kv: FakeKV(), defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: "tasks.sortMode"), "manual")
    }

    func testApplyRemoteCanBeScopedToChangedKeys() {
        let defaults = freshDefaults(#function)
        defaults.set("manual", forKey: "tasks.sortMode")
        defaults.set("time", forKey: "report.sortMode")
        let kv = FakeKV()
        kv.values["tasks.sortMode"] = "priority"
        kv.values["report.sortMode"] = "name"

        // Only the key the external-change notification named is applied —
        // last writer wins *per key*, not per store.
        SettingsSync.applyRemote(kv: kv, defaults: defaults,
                                 changedKeys: ["tasks.sortMode"])

        XCTAssertEqual(defaults.string(forKey: "tasks.sortMode"), "priority")
        XCTAssertEqual(defaults.string(forKey: "report.sortMode"), "time")
    }
}
