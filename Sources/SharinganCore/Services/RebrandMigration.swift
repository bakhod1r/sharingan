import Foundation

/// One-shot Blink → Sharingan storage rename. The app was renamed in the UI
/// long ago; this migrates the on-disk identifiers so existing users keep
/// their settings, stats, tasks and templates. Old defaults keys are copied
/// (kept for rollback); the App Support directory is moved. Safe to call on
/// every launch — copies and moves only happen when the new location is
/// still empty. Called by the app (AppDelegate) and the `tired` CLI before
/// anything reads storage.
public enum RebrandMigration {

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
        migrateDefaults(defaults)
        if let base = fileManager.urls(for: .applicationSupportDirectory,
                                       in: .userDomainMask).first {
            migrateAppSupport(base: base, fileManager: fileManager)
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
