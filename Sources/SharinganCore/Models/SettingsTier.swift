import Foundation

/// Settings surface tier: Simple shows the most-used essentials, Advanced
/// shows everything. Pure UI state — stored in UserDefaults, never in the
/// PomodoroSettings JSON blob. Advanced values hidden by Simple keep
/// persisting and keep taking effect.
public enum SettingsTier: String, CaseIterable, Sendable {
    case simple, advanced

    /// UserDefaults key holding the chosen tier's rawValue.
    public static let defaultsKey = "settingsTier"

    /// Tier from a stored raw string; unknown or missing → Simple.
    public static func from(_ raw: String?) -> SettingsTier {
        raw.flatMap(SettingsTier.init(rawValue:)) ?? .simple
    }

    /// One-shot default: fresh installs start Simple; an existing settings
    /// blob (a user updating from an older build) starts Advanced so no
    /// control they already saw disappears. No-op once a tier is stored.
    public static func seedIfNeeded(defaults: UserDefaults = .standard) {
        guard defaults.string(forKey: defaultsKey) == nil else { return }
        let hasBlob = defaults.data(forKey: PomodoroSettings.defaultsKey) != nil
        defaults.set((hasBlob ? SettingsTier.advanced : .simple).rawValue,
                     forKey: defaultsKey)
    }
}
