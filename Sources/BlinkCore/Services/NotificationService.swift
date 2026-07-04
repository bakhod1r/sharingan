import Foundation
import UserNotifications

@MainActor
public final class NotificationService {
    public static let shared = NotificationService()

    public func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            // Permission denied — silently ignore, UI handles status.
        }
    }

    public func notify(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: identifier, content: content,
                                        trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    public func focusFiveMinLeft() {
        notify(title: "Blink",
               body: "Pomodoro 5 daqiqada tugaydi. Tez orada tanaffus.",
               identifier: "blink.fiveMinLeft")
    }
}