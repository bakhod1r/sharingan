import Foundation

/// One-shot Blink → Sharingan storage rename. The app was renamed in the UI
/// long ago; this migrates the on-disk identifiers so existing users keep
/// their settings, stats, tasks and templates. Old defaults keys are copied
/// (kept for rollback); the App Support directory is moved. Safe to call on
/// every launch — copies and moves only happen when the new location is
/// still empty. Called by the app (AppDelegate) and the `tired` CLI before
/// anything reads storage.
public enum RebrandMigration {

    /// Bundle identifiers before/after the 1.13.0 rename. Until then the app
    /// shipped as `com.blink.app`, so every persisted default lives in that
    /// domain; renaming the bundle moved `UserDefaults.standard` to a fresh,
    /// empty `com.sharingan.app` domain.
    public static let oldBundleID = "com.blink.app"
    /// 1.1.x shipped as com.sharingan.app; 1.2.0 (Developer ID signing)
    /// moved to the developer-scoped ID below.
    public static let sharinganV1BundleID = "com.sharingan.app"
    public static let newBundleID = "com.bakhod1r.sharingan"

    /// The status item's defaults key for its menu-bar slot (points from the
    /// screen's RIGHT edge; AppKit reads it only at item creation).
    public static let menuBarSlotKey = "NSStatusItem Preferred Position sharingan.menubar"

    /// The far-right slot next to the system items — visible on every Mac,
    /// and the same value `rescueFromNotchIfHidden` seeds.
    public static let rightmostSlot = 6.0

    /// Old→new UserDefaults keys (values copied verbatim, old kept).
    static let keyMap: [(old: String, new: String)] = [
        ("com.blink.settings", "com.sharingan.settings"),
        ("com.blink.stats", "com.sharingan.stats"),
        ("com.blink.cliSnapshot", "com.sharingan.cliSnapshot"),
        ("blink.floating.x", "sharingan.floating.x"),
        ("blink.floating.y", "sharingan.floating.y"),
        ("blink.floating.w", "sharingan.floating.w"),
        ("blink.floating.h", "sharingan.floating.h"),
        ("blink.todayPanel.origin", "sharingan.todayPanel.origin"),
        ("blink.focusQueue", "sharingan.focusQueue"),
        ("blink.task.preReminderMinutes", "sharingan.task.preReminderMinutes"),
        // The status item's menu-bar slot. macOS stores it under the item's
        // autosaveName (AppDelegate renamed it blink.menubar → sharingan.menubar);
        // without the copy the item is re-created in the leftmost status slot,
        // which a crowded notched menu bar pushes under the camera housing —
        // the icon silently vanishes.
        ("NSStatusItem Preferred Position blink.menubar",
         "NSStatusItem Preferred Position sharingan.menubar"),
        ("NSStatusItem Visible blink.menubar",
         "NSStatusItem Visible sharingan.menubar"),
    ]

    public static func migrate(defaults: UserDefaults = .standard,
                               fileManager: FileManager = .default) {
        // Domain copy only makes sense inside the renamed app bundle — the
        // `tired` CLI (no bundle id) and the test runner must not import the
        // app's old domain into their own.
        if Bundle.main.bundleIdentifier == newBundleID {
            migrateDomain(from: oldBundleID, into: defaults)
            migrateDomain(from: sharinganV1BundleID, into: defaults)
        }
        migrateDefaults(defaults)
        if let base = fileManager.urls(for: .applicationSupportDirectory,
                                       in: .userDomainMask).first {
            migrateAppSupport(base: base, fileManager: fileManager)
        }
    }

    /// Copies everything persisted under the old `com.blink.app` domain into
    /// the renamed app's own domain (existing new-domain values win), EXCEPT
    /// the `NSStatusItem …` keys: the old domain carried a stale mid-bar slot
    /// (897 pt from the right edge on a 1440 pt bar) that macOS 26's menu-bar
    /// item hiding collapses behind the chevron, plus the system-managed
    /// `VisibleCC` flag. Dropping them re-registers the item as new, and the
    /// slot is seeded to the far right so the icon reappears next to the
    /// system items.
    public static func migrateDomain(from oldDomain: String = oldBundleID,
                                     into defaults: UserDefaults = .standard) {
        guard let old = defaults.persistentDomain(forName: oldDomain) else { return }
        for (key, value) in old
        where !key.hasPrefix("NSStatusItem ")
            && defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
        if defaults.object(forKey: menuBarSlotKey) == nil {
            defaults.set(rightmostSlot, forKey: menuBarSlotKey)
        }
    }

    public static func migrateDefaults(_ defaults: UserDefaults) {
        for (old, new) in keyMap
        where defaults.object(forKey: new) == nil {
            if let value = defaults.object(forKey: old) {
                defaults.set(value, forKey: new)
            }
        }
    }

    public static func migrateAppSupport(base: URL,
                                         fileManager: FileManager = .default) {
        let old = base.appendingPathComponent("Blink", isDirectory: true)
        let new = base.appendingPathComponent("Sharingan", isDirectory: true)
        guard fileManager.fileExists(atPath: old.path),
              !fileManager.fileExists(atPath: new.path) else { return }
        try? fileManager.moveItem(at: old, to: new)
    }
}
