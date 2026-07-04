import Foundation
import UserNotifications

/// Foydalanuvchi tomonidan sozlangan interval-based eslatmalar
/// (posture, water, custom). Faqat `settings.enabled` bo'lsa scheduler'ni boshqaradi.
/// Break vaqtida (focusOnly bo'lsa) yoki timer stop bo'lsa o'chiriladi.
@MainActor
public final class ReminderService: ObservableObject {
    public static let shared = ReminderService()

    @Published public private(set) var isScheduled = false
    public var settings: ReminderSettings = .init()

    private var ticker: Task<Void, Never>?

    public init() {}

    public func update(_ settings: ReminderSettings, focusPhase: Bool) {
        self.settings = settings
        cancel()
        guard settings.enabled else { return }
        let shouldRun = settings.duringFocusOnly ? focusPhase : true
        guard shouldRun else { return }
        let active = settings.reminders.filter { $0.enabled }
        guard !active.isEmpty else { return }
        schedule(active)
    }

    public func pauseForBreak() {
        guard settings.duringFocusOnly else { return }
        cancel()
    }

    public func resumeForFocus() {
        guard settings.enabled else { return }
        update(settings, focusPhase: true)
    }

    public func cancel() {
        ticker?.cancel()
        ticker = nil
        isScheduled = false
    }

    // MARK: - Schedule

    private func schedule(_ reminders: [ReminderItem]) {
        cancel()
        isScheduled = true
        ticker = Task { @MainActor [weak self] in
            var nextReminder: [ReminderItem: Date] = [:]
            let now = Date()
            for r in reminders { nextReminder[r] = now }
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                let check = Date()
                for r in reminders {
                    if let nxt = nextReminder[r], check >= nxt {
                        self.fire(r)
                        nextReminder[r] = check.addingTimeInterval(r.intervalSeconds)
                    }
                }
            }
        }
    }

    private func fire(_ reminder: ReminderItem) {
        NotificationService.shared.notify(
            title: "Blink — \(reminder.kind.label)",
            body: reminder.resolvedMessage,
            identifier: "blink.reminder.\(reminder.id)"
        )
        NotificationCenter.default.post(name: .reminderFired,
                                        object: self,
                                        userInfo: ["reminder": reminder])
    }
}

extension Notification.Name {
    static let reminderFired = Notification.Name("blink.reminderFired")
}