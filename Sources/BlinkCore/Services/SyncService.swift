import Foundation

/// iCloud sync is intentionally disabled: distributing an ad-hoc–signed app
/// without an iCloud container entitlement makes `CKContainer.default()` throw
/// an uncatchable exception at launch. This no-op stub keeps the call sites
/// compiling while guaranteeing the app never touches CloudKit.
@MainActor
public final class SyncService: ObservableObject {
    public static let shared = SyncService()

    public enum SyncStatus: String, Sendable {
        case disabled, idle, syncing, error
    }

    @Published public private(set) var status: SyncStatus = .disabled
    @Published public private(set) var enabled: Bool = false

    public init() {}

    /// Always false — sync is not available in this build.
    public var isAvailable: Bool { false }

    public func enable() { status = .disabled }
    public func disable() { status = .disabled }

    public func push(_ settings: PomodoroSettings, _ stats: PomodoroStats) async {}
    public func pull() async -> (PomodoroSettings, PomodoroStats)? { nil }
}
