import Foundation

public struct BlockedApp: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String { bundleID }
    public var bundleID: String
    public var name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
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
        return blockedApps.contains { $0.bundleID == bundleID }
    }
}