import Foundation

/// A durable, coalescing queue of "this record must be pushed" intents.
///
/// WHY THIS EXISTS ALONGSIDE THE SHADOW, NOT INSTEAD OF IT
/// ------------------------------------------------------
/// The shadow diff (SyncShadow.diff) already behaves like an outbox in the one
/// way that matters most: it is DERIVED from two durable facts — the current
/// rows and the last-confirmed shadow — so "what still needs pushing" survives
/// a quit, a crash, or a week offline without anyone having to remember to
/// write a queue row. An outbox that duplicated that would only add a second
/// source of truth that can disagree with the first, and the disagreement is
/// always the outbox's fault (a missed enqueue point silently drops a change
/// forever, whereas a missed diff is impossible — the diff sees the rows).
///
/// So this queue deliberately does NOT own "what changed". It owns the two
/// things the diff genuinely cannot express:
///
///  1. INTENT THAT OUTLIVES THE ROW. The diff infers a delete from a record's
///     ABSENCE relative to the shadow. That inference is only available while
///     the shadow row survives: `resetSyncState()` (account change, zoneNotFound,
///     zone purged) wipes the shadow, and every pending delete evaporates with
///     it — the record is still on the server, the next fetch pulls it back, and
///     a task the user deleted returns from the dead. A tombstone row here is an
///     explicit `.delete` op that survives a shadow reset.
///
///  2. ATTEMPT BOOKKEEPING. The diff is stateless: it cannot tell a record that
///     has never been tried from one that has failed nine times, so it cannot
///     back off, and a poison record re-enters every batch at full speed forever.
///
/// Everything here is pure and synchronous so the coalescing and backoff rules —
/// the part that must never be wrong — are testable without CloudKit, an
/// account, or a network. Persistence is behind `SyncOutboxStorage` so this type
/// does not depend on TaskDatabase.
public final class SyncOutbox {

    // MARK: - Op model

    /// What the record needs done to it. Not "what changed" — the diff and the
    /// RecordMapper resolve the payload at send time from the live model, so an
    /// op is only ever a pointer to a record, never a copy of it. That is what
    /// keeps a queued op from going stale: five edits to one task push once,
    /// carrying the fifth version, not the first.
    public enum Kind: String, Sendable, Equatable {
        case save
        case delete
    }

    public struct Op: Equatable, Sendable {
        /// `SyncRecordType.rawValue` — kept a String so the queue's persistence
        /// interface stays free of the CloudKit-importing enum.
        public let recordType: String
        public let recordName: String
        public var kind: Kind
        /// When this record FIRST became dirty and stayed dirty. Preserved
        /// across coalescing so that ordering is by age of the intent, not by
        /// age of the last keystroke — otherwise a task being actively typed in
        /// would starve behind every later change.
        public var enqueuedAt: Date
        /// Consecutive failed flushes. Reset on any new local intent: fresh
        /// content deserves a fresh chance, and the old failure may well have
        /// been about the old content (a validation error, a size limit).
        public var attempts: Int
        /// Earliest time this op may be included in a batch (backoff gate).
        public var nextAttemptAt: Date

        public init(recordType: String,
                    recordName: String,
                    kind: Kind,
                    enqueuedAt: Date = Date(),
                    attempts: Int = 0,
                    nextAttemptAt: Date = .distantPast) {
            self.recordType = recordType
            self.recordName = recordName
            self.kind = kind
            self.enqueuedAt = enqueuedAt
            self.attempts = attempts
            self.nextAttemptAt = nextAttemptAt
        }

        /// Identity is (type, name) — one op per record, always. A queue that
        /// let a record appear twice would push it twice.
        public var key: Key { Key(recordType: recordType, recordName: recordName) }
    }

    public struct Key: Hashable, Sendable {
        public let recordType: String
        public let recordName: String
        public init(recordType: String, recordName: String) {
            self.recordType = recordType
            self.recordName = recordName
        }
    }

    // MARK: - Storage

    private let storage: SyncOutboxStorage
    /// Write-through cache. The queue is read on every flush and written on
    /// every persist, and it is small (one row per dirty record, not per edit),
    /// so keeping it in memory avoids a SELECT per keystroke.
    private var ops: [Key: Op]

    /// The ceiling the exponential backoff flattens out at. Configurable so the
    /// app can expose "how long between retries at most" as a setting; the
    /// default matches the documented 5-minute cap. Only read at `markFailed`
    /// time, so changing it takes effect on the next failure.
    public var maxBackoff: TimeInterval = 300

    public init(storage: SyncOutboxStorage) {
        self.storage = storage
        self.ops = Dictionary(uniqueKeysWithValues: storage.loadOutbox().map { ($0.key, $0) })
    }

    // MARK: - Enqueue

    /// Records an intent, coalescing with whatever is already queued for the
    /// record. Idempotent by construction: enqueueing `.save` for an already
    /// queued `.save` is a no-op beyond refreshing the retry budget, which is
    /// what lets the caller enqueue unconditionally on every persist without
    /// checking first.
    ///
    /// The coalescing rules, and why each is the only safe answer:
    ///   save  → save   : one push carrying the latest content. Keep the ORIGINAL
    ///                    enqueuedAt (see `Op.enqueuedAt`).
    ///   save  → delete : delete wins. The queued save was never sent, so there
    ///                    is nothing to preserve; pushing a save the user has
    ///                    since deleted would resurrect it on every other Mac.
    ///   delete → save  : save wins — this is a deliberate resurrection (undo of
    ///                    a trash, or a re-create at the same record name), and
    ///                    it is strictly newer information than the tombstone.
    ///                    The enqueuedAt RESETS here: the tombstone's intent is
    ///                    dead, and inheriting its age would misorder the save.
    ///   delete → delete: no-op.
    @discardableResult
    public func enqueue(recordType: String,
                        recordName: String,
                        kind: Kind,
                        now: Date = Date()) -> Op {
        let key = Key(recordType: recordType, recordName: recordName)
        var op: Op
        if var existing = ops[key] {
            // A resurrect (delete → save) is a new intent, not a continuation
            // of the tombstone's — so it does not inherit the tombstone's age.
            if existing.kind == .delete, kind == .save {
                existing.enqueuedAt = now
            }
            existing.kind = kind
            existing.attempts = 0
            existing.nextAttemptAt = .distantPast
            op = existing
        } else {
            op = Op(recordType: recordType, recordName: recordName,
                    kind: kind, enqueuedAt: now)
        }
        ops[key] = op
        storage.upsertOutbox(op)
        return op
    }

    // MARK: - Flush

    /// The ops eligible for the next batch: everything whose backoff has
    /// elapsed, oldest intent first. Deterministic ordering (age, then type,
    /// then name) so batches — and tests — are reproducible, and so a record
    /// that keeps failing cannot jump the queue ahead of fresh work.
    ///
    /// Deletes are NOT ordered before saves. CloudKit records here carry no
    /// CKReferences (subtasks are JSON inside their task; a task names its
    /// category by string), so no op depends on another having landed first.
    /// If a reference is ever introduced, that changes and this is where the
    /// dependency ordering would go.
    public func ready(at now: Date = Date()) -> [Op] {
        ops.values
            .filter { $0.nextAttemptAt <= now }
            .sorted {
                if $0.enqueuedAt != $1.enqueuedAt { return $0.enqueuedAt < $1.enqueuedAt }
                if $0.recordType != $1.recordType { return $0.recordType < $1.recordType }
                return $0.recordName < $1.recordName
            }
    }

    public var pendingCount: Int { ops.count }

    public func op(recordType: String, recordName: String) -> Op? {
        ops[Key(recordType: recordType, recordName: recordName)]
    }

    /// The server confirmed the op. Dropping the row is the ONLY place an op
    /// leaves the queue on success — mirroring the shadow's rule that state is
    /// written on confirmation and never speculatively, so an interrupted flush
    /// re-sends rather than forgets.
    public func markSent(_ key: Key) {
        guard ops[key] != nil else { return }
        ops[key] = nil
        storage.deleteOutbox(recordType: key.recordType, recordName: key.recordName)
    }

    public func markSent<S: Sequence>(_ keys: S) where S.Element == Key {
        for key in keys { markSent(key) }
    }

    /// The op failed and should be retried later. The row STAYS: a failure is
    /// the one case where forgetting the intent loses data, and the caller
    /// cannot distinguish "will never work" from "the network blinked".
    public func markFailed(_ key: Key, at now: Date = Date()) {
        guard var op = ops[key] else { return }
        op.attempts += 1
        op.nextAttemptAt = now.addingTimeInterval(Self.backoff(attempts: op.attempts, cap: maxBackoff))
        ops[key] = op
        storage.upsertOutbox(op)
    }

    /// The op can never succeed as queued (the record is gone, the payload is
    /// rejected outright) — drop it rather than retry a known-dead push forever.
    /// Separate from `markSent` so the two reasons a row leaves the queue stay
    /// legible at the call site.
    public func discard(_ key: Key) { markSent(key) }

    /// Everything the queue knows, dropped. For account change ONLY: one
    /// person's pending pushes must never be replayed into another's database.
    public func reset() {
        ops.removeAll()
        storage.clearOutbox()
    }

    // MARK: - Backoff

    /// Exponential, capped, deterministic: 2s, 4s, 8s … 5 min.
    ///
    /// No jitter, deliberately. Jitter exists to de-synchronize many clients
    /// stampeding one server; here the "clients" are one user's two Macs, and
    /// the untestability it buys (a pure function you cannot assert on) costs
    /// more than the thundering herd it prevents. The 5-minute cap keeps a
    /// permanently failing record from drifting to an hour-long retry while
    /// still costing effectively nothing.
    ///
    /// This backoff gates the APP's flush, not CloudKit's own retry — CKSyncEngine
    /// still owns rate limiting and `retryAfter` for transient server errors.
    /// The two compose: whichever says "wait" wins.
    public static func backoff(attempts: Int, cap: TimeInterval = 300) -> TimeInterval {
        guard attempts > 0 else { return 0 }
        // Grow 2, 4, 8 … then flatten at `cap`. The exponent is bounded only to
        // keep `pow` away from silly magnitudes; min(., cap) is what actually
        // limits the wait, so any reasonable cap (a minute, ten minutes) is
        // reached rather than being clipped by a too-small exponent ceiling.
        let capped = min(attempts, 20)
        return min(pow(2.0, Double(capped)), cap)
    }
}

/// Where the queue's rows live. A protocol, not a concrete TaskDatabase call,
/// for two reasons: the coalescing rules can then be tested against an in-memory
/// store with no SQLite file, and the queue does not force `TaskDatabase` to be
/// visible to anything that wants to reason about pending pushes.
public protocol SyncOutboxStorage: AnyObject {
    func loadOutbox() -> [SyncOutbox.Op]
    func upsertOutbox(_ op: SyncOutbox.Op)
    func deleteOutbox(recordType: String, recordName: String)
    func clearOutbox()
}

/// Non-durable storage, for tests and for a build with no database. Using this
/// in the app would silently reduce the queue to a session-scoped cache — which
/// is exactly the failure mode the outbox exists to prevent — so the real
/// implementation must be the SQLite one (see the `sync_outbox` table).
public final class InMemorySyncOutboxStorage: SyncOutboxStorage {
    private var rows: [SyncOutbox.Key: SyncOutbox.Op] = [:]

    public init(seed: [SyncOutbox.Op] = []) {
        rows = Dictionary(uniqueKeysWithValues: seed.map { ($0.key, $0) })
    }

    public func loadOutbox() -> [SyncOutbox.Op] { Array(rows.values) }

    public func upsertOutbox(_ op: SyncOutbox.Op) { rows[op.key] = op }

    public func deleteOutbox(recordType: String, recordName: String) {
        rows[SyncOutbox.Key(recordType: recordType, recordName: recordName)] = nil
    }

    public func clearOutbox() { rows.removeAll() }
}
