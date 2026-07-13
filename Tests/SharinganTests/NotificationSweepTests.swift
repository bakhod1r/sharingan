import Foundation
import Testing
@testable import SharinganCore

/// Covers the guard/idempotency logic around `TaskStore.sweepLegacyNotificationsIfNeeded`,
/// the one-shot cleanup for orphaned "blink.task.*" notification requests left
/// behind by the Blink → Sharingan rename (see RebrandMigrationTests for the
/// UserDefaults/App Support side of that migration).
///
/// `NotificationService` wraps `UNUserNotificationCenter` directly with no
/// protocol seam, and the test host has no bundle identifier, so
/// `NotificationService`'s `center` is always nil here — real pending-request
/// listing/removal can't be exercised in a unit test. What *is* testable, and
/// what this suite covers, is the decision logic around that: the sweep must
/// (a) skip entirely once already marked done, and (b) never mark itself done
/// when it couldn't actually reach the notification center, so a later launch
/// with a real bundle id still gets a chance to sweep.
@MainActor
@Suite("Legacy notification sweep")
struct NotificationSweepTests {
    private func tempStore() -> TaskStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("blink-notif-sweep-\(UUID().uuidString).sqlite")
        return TaskStore(fileURL: url)
    }

    private func freshDefaults() -> UserDefaults {
        let name = "notif-sweep-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test("already-swept flag short-circuits without touching notifications")
    func alreadySweptIsNoop() async {
        let store = tempStore()
        let defaults = freshDefaults()
        defaults.set(true, forKey: TaskStore.legacyNotificationSweepDefaultsKey)

        await store.sweepLegacyNotificationsIfNeeded(defaults: defaults)

        #expect(defaults.bool(forKey: TaskStore.legacyNotificationSweepDefaultsKey))
    }

    @Test("an unreachable notification center leaves the flag unset for a later retry")
    func unreachableCenterDoesNotMarkSwept() async {
        let store = tempStore()
        let defaults = freshDefaults()
        #expect(!defaults.bool(forKey: TaskStore.legacyNotificationSweepDefaultsKey))

        // The test host has no bundle identifier, so NotificationService can't
        // reach UNUserNotificationCenter — this exercises exactly that path.
        await store.sweepLegacyNotificationsIfNeeded(defaults: defaults)

        #expect(!defaults.bool(forKey: TaskStore.legacyNotificationSweepDefaultsKey))
    }

    @Test("repeated calls stay idempotent")
    func repeatedCallsAreIdempotent() async {
        let store = tempStore()
        let defaults = freshDefaults()

        await store.sweepLegacyNotificationsIfNeeded(defaults: defaults)
        await store.sweepLegacyNotificationsIfNeeded(defaults: defaults)
        await store.sweepLegacyNotificationsIfNeeded(defaults: defaults)

        // No crash, no assertion failure regardless of how many times it runs.
        #expect(!defaults.bool(forKey: TaskStore.legacyNotificationSweepDefaultsKey))
    }
}
