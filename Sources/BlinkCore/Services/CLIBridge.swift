import Foundation

/// CLI ↔ app ko'prik.
///
/// CLI (`tired`) `Darwin notification` yuboradi — Blink app ešitib action bajaradi.
/// State: app viewWillAppear va phase o'zgarishida `UserDefaults`'ga snapshot yozadi,
/// CLI esa shuni stdout'ga chiqaradi.
public enum CLIBridge {
    public static let snapshotKey = "com.blink.cliSnapshot"
    public static let darwinCommandStart    = "com.blink.cli.start"
    public static let darwinCommandPause    = "com.blink.cli.pause"
    public static let darwinCommandResume   = "com.blink.cli.resume"
    public static let darwinCommandSkip     = "com.blink.cli.skip"
    public static let darwinCommandStop     = "com.blink.cli.stop"
    public static let darwinCommandAdd       = "com.blink.cli.add"
    public static let darwinCommandRemove    = "com.blink.cli.remove"
    public static let darwinCommandSetDuration = "com.blink.cli.setDuration"

    /// CLI'dan yuboriladigan snapshot.
    public struct StateSnapshot: Codable, Equatable, Sendable {
        public var phase: PomodoroPhase
        public var remainingSeconds: TimeInterval
        public var totalSeconds: TimeInterval
        public var isRunning: Bool
        public var cyclesCompletedToday: Int
        public var streak: Int

        public init(phase: PomodoroPhase, remainingSeconds: TimeInterval,
                    totalSeconds: TimeInterval, isRunning: Bool,
                    cyclesCompletedToday: Int, streak: Int) {
            self.phase = phase
            self.remainingSeconds = remainingSeconds
            self.totalSeconds = totalSeconds
            self.isRunning = isRunning
            self.cyclesCompletedToday = cyclesCompletedToday
            self.streak = streak
        }
    }

    // MARK: - Snapshot I/O

    public static func writeSnapshot(_ s: StateSnapshot) {
        if let d = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(d, forKey: snapshotKey)
        }
    }

    public static func readSnapshot() -> StateSnapshot? {
        guard let d = UserDefaults.standard.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(StateSnapshot.self, from: d)
    }

    // MARK: - Post commands (CLI side)

    public static func postCommand(_ name: String, payload: String? = nil) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        if let p = payload {
            UserDefaults.standard.set(p, forKey: name + ".payload")
        }
        CFNotificationCenterPostNotification(center,
                                              CFNotificationName(name as CFString),
                                              nil, nil, true)
    }

    // MARK: - Listen (app side)

    public static func observe(_ name: String,
                                handler: @escaping @MainActor (String?) -> Void) -> DarwinObserver {
        let obs = DarwinObserver(name: name)
        obs.register(handler)
        return obs
    }
}

public final class DarwinObserver: @unchecked Sendable {
    public let name: String
    private var center: Unmanaged<DarwinObserver>?
    private var handler: (@MainActor (String?) -> Void)?

    public init(name: String) { self.name = name }

    public func register(_ handler: @escaping @MainActor (String?) -> Void) {
        self.handler = handler
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let ptr = Unmanaged.passUnretained(self).toOpaque()
        let callback: CFNotificationCallback = { _, observer, _, _, _ in
            guard let observer else { return }
            let me = Unmanaged<DarwinObserver>.fromOpaque(observer).takeUnretainedValue()
            let payload = UserDefaults.standard.string(forKey: me.name + ".payload")
            DispatchQueue.main.async {
                me.handler?(payload)
            }
        }
        CFNotificationCenterAddObserver(center,
                                        Unmanaged.passUnretained(self).toOpaque(),
                                        callback,
                                        name as CFString,
                                        nil,
                                        .deliverImmediately)
    }

    deinit {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveEveryObserver(center, Unmanaged.passUnretained(self).toOpaque())
    }
}