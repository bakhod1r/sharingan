import Foundation

/// A running focus session's app restriction, derived from the active task.
public struct FocusLock: Equatable, Sendable {
    public let taskID: UUID
    public let taskTitle: String
    public let allowedApps: [BlockedApp]

    public init(taskID: UUID, taskTitle: String, allowedApps: [BlockedApp]) {
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.allowedApps = allowedApps
    }
}

public enum FocusLockPolicy {
    /// System UI that must never trigger the reminder.
    public static let systemBundleIDs: Set<String> = [
        "com.apple.loginwindow", "com.apple.dock", "com.apple.Spotlight",
        "com.apple.controlcenter", "com.apple.notificationcenterui",
        "com.apple.systemuiserver", "com.apple.SecurityAgent",
        "com.apple.UserNotificationCenter", "com.apple.finder",
        "com.apple.screencaptureui",
    ]

    public static let snoozeDuration: TimeInterval = 300

    public static func lock(activeTask: TaskItem?, phase: PomodoroPhase, isRunning: Bool) -> FocusLock? {
        guard isRunning, phase == .focus, let task = activeTask,
              !task.isDone, task.trashedAt == nil else { return nil }
        let enabled = task.allowedApps.filter(\.isEnabled)
        guard !enabled.isEmpty else { return nil }
        return FocusLock(taskID: task.id, taskTitle: task.title, allowedApps: enabled)
    }

    public static func shouldBlock(bundleID: String?, lock: FocusLock, ownBundleID: String?,
                                   snoozedUntil: Date?, now: Date) -> Bool {
        guard let bundleID else { return false }
        if let snoozedUntil, snoozedUntil > now { return false }
        let id = bundleID.lowercased()
        if id == ownBundleID?.lowercased() { return false }
        if systemBundleIDs.contains(where: { $0.lowercased() == id }) { return false }
        return !lock.allowedApps.contains { $0.isEnabled && $0.bundleID.lowercased() == id }
    }
}
