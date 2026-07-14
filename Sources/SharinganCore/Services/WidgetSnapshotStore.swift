import Foundation

/// Reads/writes the snapshot file the app and the widget appex share.
///
/// The canonical home is the **widget's own sandbox container**
/// (`~/Library/Containers/com.bakhod1r.sharingan.widget/Data/…`), not the app
/// group. The group looked right, but containermanagerd on macOS 26 REJECTS
/// a team-ID-less (ad-hoc) signature's claim to a TCC-protected group
/// container — "group containers identifiers should be prefixed by
/// requestor's team ID" — so the sandboxed appex can never read the group
/// under this repo's signing. Its own container it can always read, and the
/// unsandboxed app can write straight into that container's Data directory.
/// The group stays as a secondary location so a build signed with a real
/// team ID keeps working unchanged.
public enum WidgetSnapshotStore {
    /// Must match `com.apple.security.application-groups` in both
    /// Resources/App.entitlements and Resources/Widget.entitlements.
    public static let appGroupID = "89LCRZKZ48.com.bakhod1r.sharingan"
    /// Must match CFBundleIdentifier in Resources/Widget-Info.plist.
    public static let widgetBundleID = "com.bakhod1r.sharingan.widget"
    public static let fileName = "widget-snapshot.json"

    /// The snapshot inside the widget's own container, from either process.
    ///
    /// Pure: `home` is the calling process's home directory (the container's
    /// Data dir when the appex itself calls — sandboxed processes live there),
    /// `directoryExists` answers "is this a real directory?". From the app
    /// side this returns nil until the container has been materialized by a
    /// first widget launch — the app must never fabricate bare directories
    /// where containermanagerd expects to create the container itself.
    static func containerFileURL(home: String,
                                 directoryExists: (URL) -> Bool) -> URL? {
        let support = "Library/Application Support"
        if home.contains("/Library/Containers/") {          // the appex itself
            return URL(fileURLWithPath: home)
                .appendingPathComponent(support)
                .appendingPathComponent(fileName)
        }
        let data = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Containers/\(widgetBundleID)/Data")
        guard directoryExists(data) else { return nil }
        return data.appendingPathComponent(support).appendingPathComponent(fileName)
    }

    public static var containerFileURL: URL? {
        containerFileURL(home: NSHomeDirectory()) { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path,
                                                  isDirectory: &isDir) && isDir.boolValue
        }
    }

    /// App-group location — only readable by the appex when the signature
    /// carries a team ID (Developer ID / App Store builds).
    public static var groupFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    /// Preferred read/write target for callers that want one URL.
    public static var defaultFileURL: URL? { containerFileURL ?? groupFileURL }

    /// True when the widget's container exists but holds no snapshot yet —
    /// the one moment the publisher must write regardless of its change
    /// fingerprint (a freshly placed widget would otherwise render empty
    /// until the next timer/task change).
    public static var needsSeed: Bool {
        guard let url = containerFileURL else { return false }
        return !FileManager.default.fileExists(atPath: url.path)
    }

    /// Atomic, best-effort: a failed write leaves the previous snapshot
    /// intact and never throws into timer code paths. With no explicit URL
    /// it writes every reachable location (widget container + app group).
    public static func write(_ snapshot: WidgetSnapshot, to url: URL? = nil) {
        let targets = url.map { [$0] }
            ?? [containerFileURL, groupFileURL].compactMap { $0 }
        guard !targets.isEmpty,
              let data = encoded(snapshot) else { return }
        for target in targets {
            try? FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try? data.write(to: target, options: .atomic)
        }
    }

    /// nil on missing/corrupt/newer-schema files — the widget falls back to
    /// its placeholder instead of misrendering. With no explicit URL it
    /// tries the widget container first, then the app group.
    public static func read(from url: URL? = nil) -> WidgetSnapshot? {
        let candidates = url.map { [$0] }
            ?? [containerFileURL, groupFileURL].compactMap { $0 }
        for candidate in candidates {
            if let snapshot = readFile(candidate) { return snapshot }
        }
        return nil
    }

    private static func encoded(_ snapshot: WidgetSnapshot) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(snapshot)
    }

    private static func readFile(_ url: URL) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data),
              snapshot.schemaVersion <= WidgetSnapshot.currentSchemaVersion
        else { return nil }
        return snapshot
    }
}
