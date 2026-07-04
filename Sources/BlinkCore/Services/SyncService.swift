import Foundation
import CloudKit

/// CloudKit SyncService — PomodoroSettings + stats'ni iCloud'ga sinxronlash.
/// Faqat settings modelini JSON blob sifatida yozadi (oddiy approach).
@MainActor
public final class SyncService: ObservableObject {
    public static let shared = SyncService()

    public enum SyncStatus: String, Sendable {
        case disabled, idle, syncing, error
    }

    @Published public private(set) var status: SyncStatus = .disabled
    @Published public var enabled: Bool = false

    private let container = CKContainer.default()
    private let zoneID = CKRecordZone.ID(zoneName: "BlinkZone")
    private let recordName = "PomodoroSettings"

    public init() {}

    public func enable() {
        enabled = true
        status = .idle
        Task { await ensureZone() }
    }

    public func disable() {
        enabled = false
        status = .disabled
    }

    public func push(_ settings: PomodoroSettings, _ stats: PomodoroStats) async {
        guard enabled else { return }
        status = .syncing

        let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        let record = CKRecord(recordType: "BlinkSettings", recordID: recordID)

        do {
            let sData = try JSONEncoder().encode(settings)
            let tData = try JSONEncoder().encode(stats)
            record["settings"] = sData as NSData
            record["stats"] = tData as NSData
            record["updatedAt"] = Date() as NSDate

            try await saveRecord(record)
            status = .idle
        } catch {
            status = .error
        }
    }

    public func pull() async -> (PomodoroSettings, PomodoroStats)? {
        guard enabled else { return nil }
        status = .syncing

        let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        do {
            let record = try await fetchRecord(recordID)
            guard let sData = record["settings"] as? Data,
                  let tData = record["stats"] as? Data else {
                status = .idle
                return nil
            }
            let settings = try JSONDecoder().decode(PomodoroSettings.self, from: sData)
            let stats = try JSONDecoder().decode(PomodoroStats.self, from: tData)
            status = .idle
            return (settings, stats)
        } catch let error as CKError where error.code == .unknownItem {
            status = .idle
            return nil
        } catch {
            status = .error
            return nil
        }
    }

    // MARK: - CloudKit helpers

    private func ensureZone() async {
        let zone = CKRecordZone(zoneID: zoneID)
        do {
            _ = try await saveZone(zone)
        } catch {
            // Zone already exists or other benign errors — ignore.
        }
    }

    private func saveRecord(_ record: CKRecord) async throws {
        try await container.privateCloudDatabase.saveRecord(record)
    }

    private func fetchRecord(_ id: CKRecord.ID) async throws -> CKRecord {
        try await container.privateCloudDatabase.record(for: id)
    }

    private func saveZone(_ zone: CKRecordZone) async throws -> CKRecordZone {
        try await container.privateCloudDatabase.saveRecordZone(zone)
    }
}

// MARK: - CloudKit async shim (macOS 13+ natively supports these but
// provide explicit wrappers for robustness).

private extension CKDatabase {
    func saveRecord(_ record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { cont in
            save(record) { saved, error in
                if let e = error { cont.resume(throwing: e) }
                else if let r = saved { cont.resume(returning: r) }
                else { cont.resume(throwing: CKError(.unknownItem)) }
            }
        }
    }

    func record(for id: CKRecord.ID) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { cont in
            fetch(withRecordID: id) { r, e in
                if let err = e { cont.resume(throwing: err) }
                else if let r = r { cont.resume(returning: r) }
                else { cont.resume(throwing: CKError(.unknownItem)) }
            }
        }
    }

    func saveRecordZone(_ zone: CKRecordZone) async throws -> CKRecordZone {
        try await withCheckedThrowingContinuation { cont in
            save(zone) { z, e in
                if let err = e { cont.resume(throwing: err) }
                else if let z = z { cont.resume(returning: z) }
                else { cont.resume(throwing: CKError(.unknownItem)) }
            }
        }
    }
}