import Foundation
import CryptoKit

/// A record that can be diffed against the sync shadow.
///
/// `contentHash` must cover every field that is synced and nothing else —
/// a hash that moves when nothing meaningful changed turns one edited task
/// into a full-collection upload.
public protocol SyncableRecord {
    var recordName: String { get }
    var contentHash: String { get }
}

public struct ShadowEntry: Equatable, Sendable {
    public let recordName: String
    public let contentHash: String
    /// Archived CKRecord system fields (change tag, zone, etc.). Nil until
    /// CloudKit has confirmed the record once.
    public let systemFields: Data?

    public init(recordName: String, contentHash: String, systemFields: Data?) {
        self.recordName = recordName
        self.contentHash = contentHash
        self.systemFields = systemFields
    }
}

public struct SyncDiff<T: SyncableRecord>: Equatable where T: Equatable {
    public let created: [T]
    public let changed: [T]
    public let deletedRecordNames: [String]

    public init(created: [T], changed: [T], deletedRecordNames: [String]) {
        self.created = created
        self.changed = changed
        self.deletedRecordNames = deletedRecordNames
    }
}

public enum SyncShadow {
    /// Derives what CloudKit must be told from a whole-collection save.
    ///
    /// The store rewrites every row on every change (TaskDatabase.save*), so
    /// "what changed" exists nowhere else: this diff against the last
    /// confirmed sync state is the only source of deletes, and the content
    /// hash is what keeps a 300-row rewrite from becoming a 300-record push.
    /// Ordering is stable so batches — and tests — are reproducible.
    public static func diff<T: SyncableRecord & Equatable>(
        local: [T], shadow: [String: ShadowEntry]
    ) -> SyncDiff<T> {
        var created: [T] = [], changed: [T] = []
        var seen = Set<String>()
        for record in local.sorted(by: { $0.recordName < $1.recordName }) {
            seen.insert(record.recordName)
            guard let known = shadow[record.recordName] else { created.append(record); continue }
            if known.contentHash != record.contentHash { changed.append(record) }
        }
        let deleted = shadow.keys.filter { !seen.contains($0) }.sorted()
        return SyncDiff(created: created, changed: changed, deletedRecordNames: deleted)
    }

    /// Stable content hash for any Encodable payload. Sorted keys make it
    /// order-independent; a raw Hashable hashValue would be seeded per
    /// process and could not be persisted.
    public static func hash<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(value) else { return UUID().uuidString }
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }
}
