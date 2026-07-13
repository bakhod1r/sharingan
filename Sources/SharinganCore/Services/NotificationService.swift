import Foundation
import UserNotifications

@MainActor
public final class NotificationService {
    public static let shared = NotificationService()

    /// `UNUserNotificationCenter.current()` throws an uncatchable exception when
    /// the process has no bundle identifier (e.g. run unbundled via `swift run`).
    /// Guard every access so development runs don't crash; the packaged `.app`
    /// has a bundle id and works normally.
    private var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }

    public func requestAuthorization() async {
        guard let center else { return }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            // Permission denied — silently ignore, UI handles status.
        }
    }

    public func notify(title: String, body: String, identifier: String) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: identifier, content: content,
                                        trigger: nil)
        center.add(req)
    }

    public func focusFiveMinLeft() {
        notify(title: "Sharingan",
               body: "Pomodoro ends in 5 minutes. Break coming up soon.",
               identifier: "sharingan.fiveMinLeft")
    }

    /// Schedules a one-off notification to fire at `date` (ignored if in the past).
    public func schedule(title: String, body: String, identifier: String, at date: Date) {
        guard let center, date > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Fire at the exact interval from now. A calendar trigger truncated to
        // minute precision would misfire a "20 s from now" reminder to the next
        // matching minute — potentially ~24h later.
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        let req = UNNotificationRequest(identifier: identifier, content: content,
                                        trigger: trigger)
        center.add(req)
    }

    public func cancel(identifier: String) {
        center?.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    /// Removes every pending request whose identifier starts with `prefix` and
    /// returns the identifiers removed. Used by the one-shot Blink → Sharingan
    /// notification-ID sweep (see `TaskStore.sweepLegacyNotificationsIfNeeded`).
    /// Returns `nil` — instead of an empty array — when there's no bundle id
    /// (dev/test runs), so the caller can tell "nothing to sweep" apart from
    /// "couldn't ask the notification center" and avoid marking the sweep done.
    public func removePendingRequests(withPrefix prefix: String) async -> [String]? {
        guard let center else { return nil }
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        if !ids.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
        return ids
    }
}
