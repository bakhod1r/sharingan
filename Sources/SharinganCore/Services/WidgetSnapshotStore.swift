import Foundation

/// Reads/writes the snapshot file both processes share.
///
/// The canonical location is the app-group container — the only directory a
/// sandboxed appex and the (unsandboxed) app can both touch. On macOS the
/// group needs no provisioning profile, so it works with the ad-hoc signing
/// `make-app.sh` uses; macOS 15+ may ask the user once before granting an
/// unprovisioned app access to the container.
public enum WidgetSnapshotStore {
    /// Must match `com.apple.security.application-groups` in both
    /// Resources/App.entitlements and Resources/Widget.entitlements.
    public static let appGroupID = "group.com.sharingan.app"
    public static let fileName = "widget-snapshot.json"

    public static var defaultFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    /// Atomic, best-effort: a failed write leaves the previous snapshot
    /// intact and never throws into timer code paths.
    public static func write(_ snapshot: WidgetSnapshot, to url: URL? = nil) {
        guard let url = url ?? defaultFileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// nil on missing/corrupt/newer-schema files — the widget falls back to
    /// its placeholder instead of misrendering.
    public static func read(from url: URL? = nil) -> WidgetSnapshot? {
        guard let url = url ?? defaultFileURL,
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data),
              snapshot.schemaVersion <= WidgetSnapshot.currentSchemaVersion
        else { return nil }
        return snapshot
    }
}
