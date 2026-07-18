import Foundation

/// The slice of NSUbiquitousKeyValueStore behavior SettingsSync needs.
/// NSUbiquitousKeyValueStore conforms as-is; tests use an in-memory fake so
/// they never depend on iCloud (the real store silently no-ops without an
/// entitlement, which would make tests pass or fail by signing accident).
public protocol KeyValueStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: KeyValueStore {}

/// Mirrors an allowlisted subset of UserDefaults into the iCloud key-value
/// store, so the user's *intent* settings follow them between Macs.
///
/// This is deliberately an allowlist, never a blanket mirror of the defaults
/// domain. What syncs — the settings the user chose on purpose:
///   - `com.sharingan.settings`: the one JSON blob PomodoroTimer persists
///     `PomodoroSettings` under. It carries every timer/appearance intent —
///     per-kind focus/break durations, auto-start toggles, repeat + long-break
///     config, break screen (message, background, block, exit button),
///     ambience + alarm sounds, TTS, reminders, exercise settings, theme,
///     Sharingan styles, notch/dock-widget *preferences* (enabled, size,
///     opacity — not positions). Persisted atomically as one key, so it syncs
///     as one key; splitting it would invent a second schema for the same
///     struct. Caveat that rides along: `launchAtLogin` lives inside the blob,
///     so that flag travels too — acceptable because it is still a stated
///     preference, and the blob cannot be partially synced.
///   - `tasks.sortMode`, `tasks.subtaskSortMode`, `report.sortMode`: how the
///     user likes their lists ordered, shared by every task surface.
///   - `sharingan.task.preReminderMinutes`: the default reminder lead time
///     applied to new tasks.
///
/// What must NOT sync — machine-local state that would visibly fight between
/// two Macs writing to the same iCloud store:
///   - Window/widget geometry: `sharingan.dockwidget.x`/`.y`,
///     `sharingan.todayPanel.origin`, `NSStatusItem Preferred Position …` —
///     screens differ per Mac; syncing frames teleports windows off-screen.
///   - Per-window UI state: `sidebar.collapsed.*` — transient layout, not intent.
///   - One-shot flags: `sharingan.migration.notificationsSwept` and any
///     onboarding/"seen" markers — each install must run its own migrations.
///   - Data, not preferences: `com.sharingan.stats` (per-Mac history merged by
///     CloudKit sync, not last-writer-wins), `sharingan.focusQueue` (today's
///     session state), `com.sharingan.cliSnapshot` (a cache for the CLI bridge).
///   - Sync/device identity: `sync.enabled` (turning sync on on one Mac must
///     not force it on another) and the per-device UUID.
///   - Sparkle bookkeeping (`SU*` keys, e.g. SULastCheckTime) — updater state
///     is per-install.
public enum SettingsSync {

    /// Posted (main queue) after `applyRemote` actually changed at least one
    /// local default, so live objects (the running PomodoroTimer's settings)
    /// can reload without an app restart — writing the blob to UserDefaults
    /// alone changed nothing on screen until relaunch.
    public static let didApplyRemoteNotification =
        Notification.Name("sharingan.settingsSync.didApplyRemote")

    /// The allowlist. Every key here is a deliberate cross-Mac intent;
    /// see the type comment for why everything else stays home.
    public static let syncedKeys: [String] = [
        PomodoroSettings.defaultsKey,        // "com.sharingan.settings" blob
        "tasks.sortMode",
        "tasks.subtaskSortMode",
        "report.sortMode",
        TaskStore.preReminderDefaultsKey,    // "sharingan.task.preReminderMinutes"
        BoardColumnStore.defaultsKey,        // "board.columns" — custom board columns
    ]

    /// Copies every allowlisted key that has a local value up to the KV store.
    /// Keys with no local value are left alone remotely — pushing nil would
    /// erase another Mac's setting just because this one never touched it.
    public static func pushLocal(defaults: UserDefaults = .standard,
                                 kv: KeyValueStore = NSUbiquitousKeyValueStore.default) {
        var wrote = false
        for key in syncedKeys {
            if let value = defaults.object(forKey: key),
               !(value as AnyObject).isEqual(kv.object(forKey: key)) {
                kv.set(value, forKey: key)
                wrote = true
            }
        }
        // Unchanged values are skipped above, so applying a remote change
        // (which lands in defaults and re-triggers a push) can't ping-pong
        // the same bytes back to the cloud forever.
        if wrote { kv.synchronize() }
    }

    /// Copies allowlisted values from the KV store into UserDefaults —
    /// remote overwrites local (last writer wins per key; for scalar
    /// preferences there is no merge, one value is simply the newer intent).
    /// Pass `changedKeys` (from didChangeExternallyNotification's userInfo)
    /// to apply only what actually changed; nil means "consider all".
    public static func applyRemote(kv: KeyValueStore = NSUbiquitousKeyValueStore.default,
                                   defaults: UserDefaults = .standard,
                                   changedKeys: [String]? = nil) {
        let keys = changedKeys.map { Set($0).intersection(syncedKeys) }
            ?? Set(syncedKeys)
        var changed = false
        for key in keys {
            if let value = kv.object(forKey: key),
               !(value as AnyObject).isEqual(defaults.object(forKey: key)) {
                defaults.set(value, forKey: key)
                changed = true
            }
        }
        if changed {
            NotificationCenter.default.post(name: didApplyRemoteNotification,
                                            object: nil)
        }
    }

    private static var observer: NSObjectProtocol?
    private static var localObserver: NSObjectProtocol?
    private static var pushDebounce: Timer?

    /// Begins mirroring: pulls whatever iCloud already has, pushes local
    /// values for keys iCloud lacks, and observes external changes.
    /// Safe without an iCloud entitlement — the real store then holds no
    /// values, synchronize() returns false, and the notification never
    /// fires, so this degrades to a harmless no-op.
    public static func start(defaults: UserDefaults = .standard,
                             kv: KeyValueStore = NSUbiquitousKeyValueStore.default) {
        stop()
        if let ubiquitous = kv as? NSUbiquitousKeyValueStore {
            observer = NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: ubiquitous,
                queue: .main
            ) { [weak ubiquitous] note in
                guard let ubiquitous else { return }
                let changed = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey]
                    as? [String]
                applyRemote(kv: ubiquitous, defaults: defaults, changedKeys: changed)
            }
        }
        // Local changes push as they happen, not only at launch: the defaults
        // domain fires on every persist, the debounce coalesces bursts, and
        // pushLocal's value-equality skip makes untouched keys free — so a
        // settings flip on this Mac reaches the other Macs in seconds.
        localObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { _ in
            pushDebounce?.invalidate()
            pushDebounce = Timer.scheduledTimer(withTimeInterval: 2,
                                                repeats: false) { _ in
                pushLocal(defaults: defaults, kv: kv)
            }
        }
        // Remote first (another Mac's newer intent wins on first launch),
        // then push so keys only this Mac has ever set reach the cloud.
        applyRemote(kv: kv, defaults: defaults)
        pushLocal(defaults: defaults, kv: kv)
    }

    /// Removes the observers (idempotent).
    public static func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        if let localObserver {
            NotificationCenter.default.removeObserver(localObserver)
            self.localObserver = nil
        }
        pushDebounce?.invalidate()
        pushDebounce = nil
    }
}
