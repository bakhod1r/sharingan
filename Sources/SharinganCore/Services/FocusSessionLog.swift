import Foundation
import os.log

/// Append-only store of `SessionRecord`s in a JSON file. Writes are
/// fire-and-forget on a background queue — a failed save must never block or
/// crash the timer (the same rule the widget-snapshot write follows). A corrupt
/// file is set aside as `<name>.corrupt.json` and the log restarts empty rather
/// than crashing or silently destroying the blob.
@MainActor
public final class FocusSessionLog: ObservableObject {
    public static let shared = FocusSessionLog()

    @Published public private(set) var records: [SessionRecord] = []

    private let fileURL: URL
    private let saveQueue = DispatchQueue(label: "sharingan.sessionlog.save",
                                          qos: .utility)
    // nonisolated so the background save closure can log without hopping actors
    // (Logger is Sendable).
    nonisolated private static let log = Logger(subsystem: "sharingan", category: "sessionlog")
    /// Only the last `retentionDays` days are kept — enough history for the
    /// yearly heatmap and time machine.
    private static let retentionDays = 400

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let dir = base.appendingPathComponent("Sharingan", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir,
                                                     withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("focus-sessions.json")
        }
        load()
    }

    public func append(_ r: SessionRecord) {
        records.append(r)
        trim()
        save()
    }

    /// Sessions whose START falls on `day` — a midnight-spanning session
    /// belongs to the day it began.
    public func sessions(on day: Date) -> [SessionRecord] {
        let cal = Calendar.current
        return records.filter { cal.isDate($0.start, inSameDayAs: day) }
    }

    public func sessions(in interval: DateInterval) -> [SessionRecord] {
        records.filter { interval.contains($0.start) }
    }

    /// Start-of-day keys of every day that has at least one record.
    public func daysWithData() -> Set<Date> {
        let cal = Calendar.current
        return Set(records.map { cal.startOfDay(for: $0.start) })
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            records = try JSONDecoder().decode([SessionRecord].self, from: data)
                .sorted { $0.start < $1.start }
        } catch {
            Self.log.error("corrupt session log, setting aside: \(String(describing: error))")
            let aside = fileURL.deletingPathExtension()
                .appendingPathExtension("corrupt.json")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: fileURL, to: aside)
            records = []
        }
    }

    private func trim() {
        let cutoff = Calendar.current.date(
            byAdding: .day, value: -Self.retentionDays,
            to: Calendar.current.startOfDay(for: Date())) ?? .distantPast
        records.removeAll { $0.start < cutoff }
    }

    private func save() {
        let snapshot = records
        let url = fileURL
        saveQueue.async {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                Self.log.error("session log save failed: \(String(describing: error))")
            }
        }
    }

    /// Blocks until pending background writes land — tests only.
    public func flushForTesting() {
        saveQueue.sync {}
    }
}
