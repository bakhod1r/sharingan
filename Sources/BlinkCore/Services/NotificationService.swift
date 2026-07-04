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
        notify(title: "Blink",
               body: "Pomodoro ends in 5 minutes. Break coming up soon.",
               identifier: "blink.fiveMinLeft")
    }

    /// Schedules a one-off notification to fire at `date` (ignored if in the past).
    public func schedule(title: String, body: String, identifier: String, at date: Date) {
        guard let center, date > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: identifier, content: content,
                                        trigger: trigger)
        center.add(req)
    }

    public func cancel(identifier: String) {
        center?.removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
