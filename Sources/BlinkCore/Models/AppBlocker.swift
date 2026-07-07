import Foundation

public struct BlockedApp: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String { bundleID }
    public var bundleID: String
    public var name: String
    /// Whether this entry is actively blocked. Lets the user keep an app in the
    /// list but pause blocking it, instead of the toggle being a disguised delete.
    public var isEnabled: Bool

    public init(bundleID: String, name: String, isEnabled: Bool = true) {
        self.bundleID = bundleID
        self.name = name
        self.isEnabled = isEnabled
    }

    // `isEnabled` was added later — decode it defensively so an older saved
    // settings blob (without the key) still loads with blocking on by default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try c.decode(String.self, forKey: .bundleID)
        name = try c.decode(String.self, forKey: .name)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    /// Common distracting defaults.
    public static let presets: [BlockedApp] = [
        .init(bundleID: "com.google.Chrome", name: "Chrome"),
        .init(bundleID: "com.apple.Safari", name: "Safari"),
        .init(bundleID: "com.microsoft.VSCode", name: "VS Code"),
        .init(bundleID: "com.tinyspeck.slackmacgap", name: "Slack"),
        .init(bundleID: "ru.keepcoder.Telegram", name: "Telegram"),
        .init(bundleID: "com.apple.mobilesms", name: "Messages"),
    ]
}

public struct AppBlockerSettings: Codable, Equatable, Sendable {
    public var enabled: Bool = false
    /// Faqat break vaqtida bloklash (true) yoki hamisha (false).
    public var onlyDuringBreak: Bool = true
    public var blockedApps: [BlockedApp] = BlockedApp.presets
    /// Frontmost bo'lib chiqsa darhol kill qilish.
    public var killOnFrontmost: Bool = false

    public init() {}

    public func matches(bundleID: String) -> Bool {
        guard enabled else { return false }
        return blockedApps.contains { $0.bundleID == bundleID && $0.isEnabled }
    }
}