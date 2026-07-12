import Foundation

/// CLI ↔ app ko'prik.
///
/// CLI (`tired`) `Darwin notification` yuboradi — Sharingan app ešitib action bajaradi.
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
    public static let darwinCommandTaskAdd   = "com.blink.cli.task.add"
    public static let darwinCommandTaskDone  = "com.blink.cli.task.done"
    public static let darwinCommandTaskStart = "com.blink.cli.task.start"
    public static let darwinCommandTaskQueue = "com.blink.cli.task.queue"

    /// CLI'dan yuboriladigan snapshot.
    public struct StateSnapshot: Codable, Equatable, Sendable {
        public var phase: PomodoroPhase
        public var remainingSeconds: TimeInterval
        public var totalSeconds: TimeInterval
        public var isRunning: Bool
        public var cyclesCompletedToday: Int
        public var streak: Int
        /// When the snapshot was written. The app only writes on state *changes*
        /// (not per tick), so a running countdown is reconstructed CLI-side as
        /// `remainingSeconds - (now - updatedAt)` — and a snapshot whose countdown
        /// ran out long ago exposes a crashed/quit app instead of a phantom
        /// "Focus 12:34 ●" forever. Optional so pre-field snapshots still decode.
        public var updatedAt: Date?

        public init(phase: PomodoroPhase, remainingSeconds: TimeInterval,
                    totalSeconds: TimeInterval, isRunning: Bool,
                    cyclesCompletedToday: Int, streak: Int,
                    updatedAt: Date? = nil) {
            self.phase = phase
            self.remainingSeconds = remainingSeconds
            self.totalSeconds = totalSeconds
            self.isRunning = isRunning
            self.cyclesCompletedToday = cyclesCompletedToday
            self.streak = streak
            self.updatedAt = updatedAt
        }
    }

    /// One open task in the CLI-readable snapshot — just enough for
    /// `tired task list` to print it and address it by number.
    public struct TaskSnapshotEntry: Codable, Equatable, Sendable {
        public var id: UUID
        public var title: String
        /// "P1"…"P3"; empty when the task has no priority flag.
        public var priorityLabel: String
        public var due: Date?
        public var tags: [String]
        public var project: String?

        public init(id: UUID, title: String, priorityLabel: String = "",
                    due: Date? = nil, tags: [String] = [], project: String? = nil) {
            self.id = id
            self.title = title
            self.priorityLabel = priorityLabel
            self.due = due
            self.tags = tags
            self.project = project
        }
    }

    // MARK: - Shared storage
    //
    // The app and the `tired` CLI are separate processes with separate
    // `UserDefaults.standard` domains, so state written by one is invisible to
    // the other. Communicate through files in a shared directory instead —
    // deterministic across processes, no App Group entitlement required.

    private static var sharedDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Blink/cli", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var snapshotURL: URL { sharedDir.appendingPathComponent("snapshot.json") }
    private static var taskSnapshotURL: URL { sharedDir.appendingPathComponent("tasks.json") }
    private static func payloadURL(_ name: String) -> URL {
        sharedDir.appendingPathComponent(name + ".payload")
    }

    // MARK: - Snapshot I/O

    public static func writeSnapshot(_ s: StateSnapshot) {
        if let d = try? JSONEncoder().encode(s) {
            try? d.write(to: snapshotURL, options: .atomic)
        }
    }

    public static func readSnapshot() -> StateSnapshot? {
        guard let d = try? Data(contentsOf: snapshotURL) else { return nil }
        return try? JSONDecoder().decode(StateSnapshot.self, from: d)
    }

    // MARK: - Task snapshot I/O

    public static func writeTaskSnapshot(_ entries: [TaskSnapshotEntry]) {
        if let d = try? JSONEncoder().encode(entries) {
            try? d.write(to: taskSnapshotURL, options: .atomic)
        }
    }

    public static func readTaskSnapshot() -> [TaskSnapshotEntry]? {
        guard let d = try? Data(contentsOf: taskSnapshotURL) else { return nil }
        return try? JSONDecoder().decode([TaskSnapshotEntry].self, from: d)
    }

    /// The store's open tasks as snapshot entries, in list order (manual
    /// `sortOrder`, creation time as the stable tiebreak — the open-task half
    /// of `TaskStore.inListOrder`). The entry index +1 is the number the CLI
    /// prints and accepts.
    public static func taskSnapshotEntries(from tasks: [TaskItem]) -> [TaskSnapshotEntry] {
        tasks.filter { !$0.isDone }
            .sorted {
                $0.sortOrder != $1.sortOrder
                    ? $0.sortOrder < $1.sortOrder
                    : $0.createdAt < $1.createdAt
            }
            .map {
                TaskSnapshotEntry(id: $0.id, title: $0.title,
                                  priorityLabel: $0.priority == .none ? "" : $0.priority.label,
                                  due: $0.dueDate, tags: $0.tags, project: $0.project)
            }
    }

    /// Resolves a 1-based `tired task list` number to the task's UUID.
    public static func resolveTaskIndex(_ n: Int, in entries: [TaskSnapshotEntry]) -> UUID? {
        guard n >= 1, n <= entries.count else { return nil }
        return entries[n - 1].id
    }

    // MARK: - Post commands (CLI side)

    public static func postCommand(_ name: String, payload: String? = nil) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        if let p = payload {
            try? Data(p.utf8).write(to: payloadURL(name), options: .atomic)
        } else {
            // Darwin notifications carry no data — the payload rides in a side
            // file. Clear any leftover one, or a plain `tired start` after a
            // `tired start 50m` would replay the stale "50m".
            try? FileManager.default.removeItem(at: payloadURL(name))
        }
        CFNotificationCenterPostNotification(center,
                                              CFNotificationName(name as CFString),
                                              nil, nil, true)
    }

    /// Reads (and consumes) the payload written for a command (app side).
    static func readPayload(_ name: String) -> String? {
        guard let d = try? Data(contentsOf: payloadURL(name)) else { return nil }
        try? FileManager.default.removeItem(at: payloadURL(name))
        return String(decoding: d, as: UTF8.self)
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
            let payload = CLIBridge.readPayload(me.name)
            DispatchQueue.main.async {
                me.handler?(payload)
            }
        }
        CFNotificationCenterAddObserver(center,
                                        ptr,
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