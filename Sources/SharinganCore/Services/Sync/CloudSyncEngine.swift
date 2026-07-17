import CloudKit
import Combine
import Foundation
import Security
import os

/// Owns the CKSyncEngine and the two loops it drives:
///
///   save → diff against the shadow → push          (nextRecordZoneChangeBatch)
///   fetch → merge via MergePolicy → save → shadow  (handleEvent)
///
/// Everything that decides *what* to send or *how* to reconcile lives in the
/// pure types (SyncShadow, MergePolicy, RecordMapper) so it can be tested
/// without an account; this class is the plumbing around them.
///
/// Degradation contract: without the iCloud entitlement, without an account,
/// or with sync toggled off, none of this may throw into normal code paths —
/// `start()` parks the status on `.unavailable`/`.disabled` and the app
/// behaves exactly as it does today.
@MainActor
public final class CloudSyncEngine: ObservableObject {
    public static let containerID = "iCloud.com.bakhod1r.sharingan"
    public static let zoneName = "SharinganData"
    /// UserDefaults key for the master toggle (default OFF — sync is opt-in).
    public static let syncEnabledKey = "sync.enabled"
    /// UserDefaults key for the retry backoff ceiling, in minutes. Absent means
    /// the default of 5. Bounds the longest wait between push retries for a
    /// record the server keeps rejecting.
    public static let syncRetryMaxMinutesKey = "sync.retryMaxMinutes"
    public static let defaultRetryMaxMinutes = 5

    @Published public private(set) var status: SyncStatus = .disabled

    private let store: TaskStore
    private let templates: TemplateStore?
    /// Own handle on the shared SQLite file (WAL + busy timeout make that
    /// safe — TemplateStore does the same). TaskDatabase is internal to
    /// SharinganCore, so the app target could not pass one in anyway.
    private let database: TaskDatabase?
    /// The durable push queue. Its rows outlive a shadow reset, so a delete the
    /// user made while offline still ships after an account/zone reset wipes the
    /// shadow — see SyncOutbox. The shadow diff still decides WHAT changed; the
    /// outbox only carries the intent forward and gates per-record retry.
    private let outbox: SyncOutbox
    private var engine: CKSyncEngine?
    private var fallbackTimer: Timer?
    /// Coalesces a burst of persists into one diff pass — see scheduleEnqueue().
    private var enqueueDebounce: Timer?
    /// When the current burst's first persist arrived, so the debounce can be
    /// capped and never starve under continuous typing.
    private var burstStartedAt: Date?
    private let log = Logger(subsystem: "com.bakhod1r.sharingan", category: "sync")

    /// How long after a persist to wait for more before diffing. Long enough to
    /// swallow a burst of keystrokes, short enough that "Sync now" is never what
    /// the user reaches for.
    static let enqueueDebounceInterval: TimeInterval = 0.75
    /// Hard ceiling on that wait: continuous typing must not defer the push
    /// indefinitely, so a burst always diffs at least this often.
    static let enqueueDebounceCap: TimeInterval = 5

    private var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    // sync_state keys.
    private enum StateKey {
        static let engineState = "engineState"
        static let lastSynced = "lastSynced"
        static let subscriptionSaved = "subscriptionSaved"
    }

    /// `databaseURL`, when given (tests), points at an isolated SQLite file;
    /// the app default is the same `blink.sqlite` TaskStore persists to.
    public init(store: TaskStore,
                templates: TemplateStore? = nil,
                databaseURL: URL? = nil) {
        self.store = store
        self.templates = templates
        let dbURL: URL
        if let databaseURL {
            dbURL = databaseURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            dbURL = base.appendingPathComponent("Sharingan", isDirectory: true)
                .appendingPathComponent("blink.sqlite")
        }
        let database = TaskDatabase(path: dbURL.path)
        self.database = database
        // The SQLite store is what makes the queue durable; the in-memory store
        // is only reached when the database itself failed to open, in which case
        // sync as a whole is already degraded and a session-scoped queue is moot.
        self.outbox = SyncOutbox(storage: database ?? InMemorySyncOutboxStorage())
        applyRetryCap()
    }

    /// The user-facing "retry at most every N minutes" setting → the outbox's
    /// backoff ceiling. Reading the stored default here (rather than binding it)
    /// keeps SyncOutbox free of UserDefaults; the setter is called live when the
    /// slider changes, and init picks up whatever was last stored.
    public func applyRetryCap() {
        let minutes = UserDefaults.standard.object(forKey: Self.syncRetryMaxMinutesKey) as? Int
            ?? Self.defaultRetryMaxMinutes
        outbox.maxBackoff = TimeInterval(max(1, minutes)) * 60
    }

    public func setRetryCapMinutes(_ minutes: Int) {
        UserDefaults.standard.set(minutes, forKey: Self.syncRetryMaxMinutesKey)
        outbox.maxBackoff = TimeInterval(max(1, minutes)) * 60
    }

    // MARK: - Lifecycle

    /// Brings sync up, or parks it on a calm status when it can't run.
    /// Checked in order: the entitlement (a build without an embedded
    /// provisioning profile has none — CloudKit would raise an Objective-C
    /// exception Swift cannot catch, so the check happens BEFORE any CKContainer
    /// call), then the account. Neither failure mode throws into the app.
    public func start() {
        guard engine == nil else { return }
        guard Self.hasCloudKitEntitlement else {
            status = .unavailable("iCloud is unavailable in this build")
            return
        }
        let container = CKContainer(identifier: Self.containerID)
        let ckDatabase = container.privateCloudDatabase

        var serialization: CKSyncEngine.State.Serialization?
        if let data = database?.syncStateValue(StateKey.engineState) {
            serialization = try? JSONDecoder()
                .decode(CKSyncEngine.State.Serialization.self, from: data)
        }
        let configuration = CKSyncEngine.Configuration(
            database: ckDatabase,
            stateSerialization: serialization,
            delegate: self)
        let engine = CKSyncEngine(configuration)
        self.engine = engine

        // Idempotent: saving an existing zone is a no-op server-side, and the
        // engine dedupes pending changes.
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])

        store.didPersist = { [weak self] in self?.scheduleEnqueue() }
        templates?.didPersist = { [weak self] in self?.scheduleEnqueue() }

        status = .idle(lastSynced: lastSyncedDate())
        Task { [weak self] in
            guard let self else { return }
            do {
                let account = try await container.accountStatus()
                guard account == .available else {
                    self.status = .unavailable("Signed out of iCloud")
                    return
                }
            } catch {
                self.status = .unavailable("iCloud is unreachable")
                return
            }
            // Adopt whatever changed while sync was off (or has never synced):
            // the shadow diff turns the current collections into the exact
            // pending set, so a first run is a clean upload.
            self.enqueueLocalChanges()
            self.registerSubscriptionIfNeeded(in: ckDatabase)
            try? await self.engine?.fetchChanges()
        }

        // Fallback for Macs the silent push doesn't reach (the Developer ID
        // build carries no aps-environment entitlement, so in practice this
        // IS the delivery path): poll every 60 seconds while sync is on —
        // cheap against CloudKit, and it keeps mirrored timers, breaks and
        // settings landing within a minute worst-case instead of 15.
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 60,
                                             repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.fetchChanges()
                // Re-arm ops whose backoff has now elapsed. Nothing persisted to
                // trigger a fresh diff, so without this a failed push would only
                // retry on the next unrelated edit.
                if let engine = self.engine { self.submitReadyOutbox(to: engine) }
            }
        }
    }

    /// Turns sync off. Deletes NOTHING — not locally, not in iCloud; the
    /// engine simply stops talking to CloudKit until start() runs again.
    public func stop() {
        store.didPersist = nil
        templates?.didPersist = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        // Dropping a debounced diff on the floor loses nothing: the pending set
        // is DERIVED from the rows and the shadow, both already on disk, so the
        // next start() re-derives exactly the same work. That property is what
        // makes debouncing safe at all — see scheduleEnqueue().
        enqueueDebounce?.invalidate()
        enqueueDebounce = nil
        burstStartedAt = nil
        engine = nil
        status = .disabled
    }

    /// The Settings "Sync now" button: push whatever is pending, pull whatever
    /// the server has.
    public func syncNow() {
        guard let engine else { return }
        // Explicit user intent — never make them wait out the debounce.
        enqueueLocalChanges()
        Task { [weak self] in
            do {
                try await engine.sendChanges()
                try await engine.fetchChanges()
            } catch {
                self?.status = .failed("Sync failed: \(error.localizedDescription)")
            }
        }
    }

    /// Pull-only entry point: silent pushes, wake, and foreground all funnel
    /// here. Failures are the engine's to retry — no status flapping.
    public func fetchChanges() {
        guard let engine else { return }
        Task { try? await engine.fetchChanges() }
    }

    /// Called when the iCloud account changes: one person's shadow must never
    /// be reused against another's database.
    public func accountChanged() {
        database?.resetSyncState()
        // The account change is the ONLY reset that clears the outbox: one
        // person's pending pushes (including tombstones, which survive every
        // other reset) must never replay into another's database.
        outbox.reset()
        let wasRunning = engine != nil
        stop()
        if wasRunning { start() }
    }

    // MARK: - Pure helpers (tested)

    /// Records the current save has to push, given the last-confirmed shadow.
    nonisolated public static func pendingChanges(tasks: [TaskItem],
                                      shadow: [String: ShadowEntry]) -> [TaskItem] {
        let diff = SyncShadow.diff(local: tasks, shadow: shadow)
        return diff.created + diff.changed
    }

    /// The shadow as it would be if everything currently in the store had just
    /// been synced — used by tests as the "all clean" baseline.
    public static func shadowSnapshot(of store: TaskStore) -> [String: ShadowEntry] {
        Dictionary(uniqueKeysWithValues: store.tasks.map {
            ($0.recordName, ShadowEntry(recordName: $0.recordName,
                                        contentHash: $0.contentHash,
                                        systemFields: nil))
        })
    }

    /// Whether a server-side delete may be applied locally. It may NOT when
    /// the local copy was edited after the last confirmed sync (its hash no
    /// longer matches the shadow): that unsynced edit is newer information
    /// than the tombstone, so the record is kept and re-uploaded instead —
    /// "a delete never wins over a newer edit" without needing tombstone
    /// timestamps CloudKit does not provide.
    nonisolated public static func shouldApplyRemoteDelete(localHash: String?,
                                               lastSyncedHash: String?) -> Bool {
        guard let localHash else { return true }   // nothing local to protect
        return localHash == lastSyncedHash
    }

    // MARK: - Local diff → pending changes

    /// The didPersist hook: coalesce a burst of saves into ONE diff pass.
    ///
    /// Why this is needed: the store persists the whole collection on every
    /// mutation, so typing a note fires didPersist per keystroke, and each one
    /// used to cost a full `enqueueLocalChanges()` — five shadow SELECTs plus a
    /// JSON-encode-and-SHA256 of every task, category, tag and focus-log entry
    /// in the database, on the main actor, to discover that ONE record moved.
    /// The diff is not wrong, just far too eager; a whole-collection rewrite
    /// already can't become a whole-collection upload (that's what the content
    /// hashes buy), but it could absolutely become a whole-collection re-hash.
    ///
    /// Why debouncing is safe here and would not be in a hand-maintained queue:
    /// nothing is buffered in memory that isn't already on disk. The pending set
    /// is a pure function of (rows, shadow), so a quit, crash, or power loss
    /// mid-debounce loses no change — start() re-derives the identical set. The
    /// only thing deferred is when we look.
    ///
    /// The cap matters: without it, a user typing steadily for two minutes would
    /// reset the timer on every keystroke and push nothing for two minutes.
    private func scheduleEnqueue() {
        let now = Date()
        if burstStartedAt == nil { burstStartedAt = now }
        // Burst has run long enough — diff now and start a fresh window,
        // rather than let the next keystroke defer it again.
        if let start = burstStartedAt, now.timeIntervalSince(start) >= Self.enqueueDebounceCap {
            enqueueLocalChanges()
            return
        }
        enqueueDebounce?.invalidate()
        enqueueDebounce = Timer.scheduledTimer(
            withTimeInterval: Self.enqueueDebounceInterval, repeats: false
        ) { [weak self] _ in
            Task { @MainActor in self?.enqueueLocalChanges() }
        }
    }

    /// Diff every synced collection against its shadow and hand the result to
    /// the engine as pending changes. The content hashes keep a whole-collection
    /// rewrite from becoming a whole-collection upload. Call directly only for
    /// explicit intent (syncNow, start, post-merge); routine persists go through
    /// `scheduleEnqueue()`.
    private func enqueueLocalChanges() {
        // Whatever prompted this pass, the current burst is now accounted for.
        enqueueDebounce?.invalidate()
        enqueueDebounce = nil
        burstStartedAt = nil

        guard let engine, let database else { return }
        let now = Date()

        // The shadow diff stays the source of truth for WHAT changed; each pass
        // reconciles the outbox to it. A record that is dirty gets a queued op;
        // a record whose queued .save is no longer dirty (a remote merge already
        // overwrote it to match the shadow) has its op marked sent — there is
        // nothing left to push, and leaving it would re-send stale content.
        func collect<T: SyncableRecord & Equatable>(_ type: SyncRecordType, _ local: [T]) {
            let diff = SyncShadow.diff(local: local,
                                       shadow: database.loadShadow(recordType: type.rawValue))
            var dirty = Set<String>()
            for record in diff.created + diff.changed {
                dirty.insert(record.recordName)
                outbox.enqueue(recordType: type.rawValue,
                               recordName: record.recordName, kind: .save, now: now)
            }
            for name in diff.deletedRecordNames {
                outbox.enqueue(recordType: type.rawValue,
                               recordName: name, kind: .delete, now: now)
            }
            // Clean-again saves: a pending .save the diff no longer reports.
            for op in outbox.ready(at: now)
            where op.recordType == type.rawValue && op.kind == .save && !dirty.contains(op.recordName) {
                outbox.markSent(op.key)
            }
        }

        collect(.task, store.tasks)
        collect(.category, store.customCategories)
        collect(.tag, store.customTags.map(SyncableTag.init))
        collect(.focusLog, store.focusLog)
        if let templates { collect(.template, templates.templates) }

        submitReadyOutbox(to: engine, at: now)
    }

    /// Hands the engine every outbox op whose backoff has elapsed. CKSyncEngine
    /// dedupes pending changes, so calling this from both the diff pass and the
    /// fallback timer (which retries backed-off ops with no new persist to
    /// trigger a diff) is safe.
    private func submitReadyOutbox(to engine: CKSyncEngine, at now: Date = Date()) {
        let pending: [CKSyncEngine.PendingRecordZoneChange] = outbox.ready(at: now).map { op in
            op.kind == .delete
                ? .deleteRecord(recordID(op.recordName))
                : .saveRecord(recordID(op.recordName))
        }
        guard !pending.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: pending)
    }

    private func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: zoneID)
    }

    /// The current local model for a pending save, as a CKRecord re-hydrated
    /// from the shadow's archived system fields (that is what makes the save
    /// an update rather than a clobber). Nil when the object vanished between
    /// enqueue and send — the engine then drops the pending change.
    private func record(for recordID: CKRecord.ID) -> CKRecord? {
        let name = recordID.recordName
        if let task = store.tasks.first(where: { $0.recordName == name }) {
            return RecordMapper.record(for: task, in: zoneID,
                                       systemFields: shadowFields(.task, name))
        }
        if let category = store.customCategories.first(where: { $0.recordName == name }) {
            return RecordMapper.record(for: category, in: zoneID,
                                       systemFields: shadowFields(.category, name))
        }
        if store.customTags.contains(name) {
            return RecordMapper.record(for: SyncableTag(name), in: zoneID,
                                       systemFields: shadowFields(.tag, name))
        }
        if let entry = store.focusLog.first(where: { $0.recordName == name }) {
            return RecordMapper.record(for: entry, in: zoneID,
                                       systemFields: shadowFields(.focusLog, name))
        }
        if let template = templates?.templates.first(where: { $0.recordName == name }) {
            return RecordMapper.record(for: template, in: zoneID,
                                       systemFields: shadowFields(.template, name))
        }
        return nil
    }

    private func shadowFields(_ type: SyncRecordType, _ name: String) -> Data? {
        database?.loadShadow(recordType: type.rawValue)[name]?.systemFields
    }

    // MARK: - Fetched changes → merge → save → shadow

    private func applyFetched(modifications: [CKRecord],
                              deletions: [CKDatabase.RecordZoneChange.Deletion]) {
        var tasks: [TaskItem] = []
        var categories: [TaskCategory] = []
        var tags: [String] = []
        var focus: [FocusLogEntry] = []
        var fetchedTemplates: [TaskTemplate] = []

        for record in modifications {
            guard let type = SyncRecordType(rawValue: record.recordType) else { continue }
            switch type {
            case .task:
                guard let task = RecordMapper.task(from: record) else { continue }
                tasks.append(task)
                confirmShadow(type, record, hash: task.contentHash)
            case .category:
                guard let category = RecordMapper.category(from: record) else { continue }
                categories.append(category)
                confirmShadow(type, record, hash: category.contentHash)
            case .tag:
                guard let tag = RecordMapper.tag(from: record) else { continue }
                tags.append(tag.name)
                confirmShadow(type, record, hash: tag.contentHash)
            case .focusLog:
                guard let entry = RecordMapper.focusLog(from: record) else { continue }
                focus.append(entry)
                confirmShadow(type, record, hash: entry.contentHash)
            case .template:
                guard let template = RecordMapper.template(from: record) else { continue }
                fetchedTemplates.append(template)
                confirmShadow(type, record, hash: template.contentHash)
            case .activeTimer:
                applyFetchedTimer(record)
            }
        }

        var deletedTaskIDs: [UUID] = []
        var deletedCategoryNames: [String] = []
        var deletedTagNames: [String] = []
        var deletedFocusNames: [String] = []
        var deletedTemplateIDs: [UUID] = []

        for deletion in deletions {
            guard let type = SyncRecordType(rawValue: deletion.recordType) else { continue }
            let name = deletion.recordID.recordName
            let lastSynced = database?.loadShadow(recordType: type.rawValue)[name]?.contentHash
            let localHash = localContentHash(type, name)
            guard Self.shouldApplyRemoteDelete(localHash: localHash,
                                               lastSyncedHash: lastSynced) else {
                // Locally edited after the last sync: keep the record and drop
                // its shadow row, so the next diff re-uploads it as a create.
                database?.deleteShadow(recordType: type.rawValue, recordName: name)
                continue
            }
            switch type {
            case .task:
                if let id = UUID(uuidString: name) { deletedTaskIDs.append(id) }
            case .category:
                deletedCategoryNames.append(name)
            case .tag:
                deletedTagNames.append(name)
            case .focusLog:
                deletedFocusNames.append(name)
            case .template:
                if let id = UUID(uuidString: name) { deletedTemplateIDs.append(id) }
            case .activeTimer:
                remoteTimer = nil
            }
            database?.deleteShadow(recordType: type.rawValue, recordName: name)
            // The server already removed this record; any local .delete op for
            // it has nothing left to do.
            outbox.markSent(SyncOutbox.Key(recordType: type.rawValue, recordName: name))
        }

        if !tasks.isEmpty || !categories.isEmpty || !tags.isEmpty || !focus.isEmpty
            || !deletedTaskIDs.isEmpty || !deletedCategoryNames.isEmpty
            || !deletedTagNames.isEmpty || !deletedFocusNames.isEmpty {
            store.mergeRemote(tasks: tasks,
                              categories: categories,
                              tags: tags,
                              focusEntries: focus,
                              deletedTaskIDs: deletedTaskIDs,
                              deletedCategoryNames: deletedCategoryNames,
                              deletedTagNames: deletedTagNames,
                              deletedFocusRecordNames: deletedFocusNames)
        }
        if !fetchedTemplates.isEmpty || !deletedTemplateIDs.isEmpty {
            templates?.mergeRemote(templates: fetchedTemplates,
                                   deletedIDs: deletedTemplateIDs)
        }

        // Where the LOCAL copy won a merge it now differs from the shadow
        // (which reflects the server); diffing here re-enqueues exactly those
        // records so both sides converge on the local winner.
        enqueueLocalChanges()
    }

    private func localContentHash(_ type: SyncRecordType, _ name: String) -> String? {
        switch type {
        case .task:
            return store.tasks.first { $0.recordName == name }?.contentHash
        case .category:
            return store.customCategories.first { $0.recordName == name }?.contentHash
        case .tag:
            return store.customTags.contains(name) ? SyncableTag(name).contentHash : nil
        case .focusLog:
            return store.focusLog.first { $0.recordName == name }?.contentHash
        case .template:
            return templates?.templates.first { $0.recordName == name }?.contentHash
        case .activeTimer:
            return nil
        }
    }

    /// Writes the shadow for a record the server has CONFIRMED (fetched here,
    /// or acknowledged in handleSent) — the only two places the shadow may be
    /// written, per the design: never speculatively.
    private func confirmShadow(_ type: SyncRecordType, _ record: CKRecord, hash: String) {
        database?.upsertShadow(
            recordType: type.rawValue,
            entry: ShadowEntry(recordName: record.recordID.recordName,
                               contentHash: hash,
                               systemFields: RecordMapper.systemFields(of: record)))
    }

    // MARK: - Sent changes → shadow on confirmation

    private func handleSent(_ event: CKSyncEngine.Event.SentRecordZoneChanges) {
        for record in event.savedRecords {
            guard let type = SyncRecordType(rawValue: record.recordType) else { continue }
            // The server confirmed this push — the ONLY place a save op leaves
            // the queue on success.
            outbox.markSent(SyncOutbox.Key(recordType: type.rawValue,
                                           recordName: record.recordID.recordName))
            // The hash stored is of the payload the server acknowledged —
            // decoded back through the mapper so it is byte-for-byte the same
            // hash a later fetch of this record would produce.
            let hash: String?
            switch type {
            case .task:       hash = RecordMapper.task(from: record)?.contentHash
            case .category:   hash = RecordMapper.category(from: record)?.contentHash
            case .tag:        hash = RecordMapper.tag(from: record)?.contentHash
            case .focusLog:   hash = RecordMapper.focusLog(from: record)?.contentHash
            case .template:   hash = RecordMapper.template(from: record)?.contentHash
            case .activeTimer: hash = sentTimerHash(record)
            }
            if let hash { confirmShadow(type, record, hash: hash) }
        }
        for recordID in event.deletedRecordIDs {
            // The confirmation carries no record type; clearing the name from
            // every type's shadow and queue is safe (names are namespaced by
            // content — UUIDs, category names, focus-log triples).
            for type in SyncRecordType.allCases {
                database?.deleteShadow(recordType: type.rawValue,
                                       recordName: recordID.recordName)
                outbox.markSent(SyncOutbox.Key(recordType: type.rawValue,
                                               recordName: recordID.recordName))
            }
        }
        for failure in event.failedRecordSaves {
            handleFailedSave(failure)
        }
        for recordID in event.failedRecordDeletes.keys {
            // A delete that failed transiently must stay queued and back off,
            // or the tombstone is lost and the record returns on the next fetch.
            for type in SyncRecordType.allCases {
                outbox.markFailed(SyncOutbox.Key(recordType: type.rawValue,
                                                 recordName: recordID.recordName))
            }
        }
        if !event.failedRecordDeletes.isEmpty {
            log.error("sync: \(event.failedRecordDeletes.count) record deletes failed")
        }
    }

    private func handleFailedSave(
        _ failure: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave
    ) {
        let recordID = failure.record.recordID
        switch failure.error.code {
        case .serverRecordChanged:
            // Our save was stale. Adopt the server's system fields (so the
            // retry is an update against the CURRENT change tag), merge the
            // server's content through the normal fetched path, and let the
            // post-merge diff re-enqueue our copy if it won.
            guard let serverRecord = failure.error.serverRecord else { break }
            applyFetched(modifications: [serverRecord], deletions: [])
        case .zoneNotFound:
            // Zone vanished (fresh account, or the user purged iCloud data):
            // recreate it and retry; the shadow reset makes everything a create.
            database?.resetSyncState()
            engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
            enqueueLocalChanges()
        case .unknownItem:
            // The server has never seen (or has deleted) this record; drop the
            // stale system fields so the retry is a bare create.
            if let type = SyncRecordType(rawValue: failure.record.recordType) {
                database?.deleteShadow(recordType: type.rawValue,
                                       recordName: recordID.recordName)
            }
            engine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        default:
            // Transient errors (network, throttling, quota) are CKSyncEngine's
            // to retry; back the queue op off in step so a poison record cannot
            // re-enter every batch at full speed, and log the rest.
            if let type = SyncRecordType(rawValue: failure.record.recordType) {
                outbox.markFailed(SyncOutbox.Key(recordType: type.rawValue,
                                                 recordName: recordID.recordName))
            }
            log.error("sync: save failed for \(recordID.recordName, privacy: .public): \(failure.error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Silent push (Phase 3)

    /// One silent (content-available) subscription on the private database, so
    /// other Macs' pushes arrive without polling. Registered once per synced
    /// account — the sync_state flag is wiped with the rest of the bookkeeping
    /// on account change. Failure is harmless: the wake/foreground/15-minute
    /// fallbacks still converge.
    private func registerSubscriptionIfNeeded(in ckDatabase: CKDatabase) {
        guard database?.syncStateValue(StateKey.subscriptionSaved) == nil else { return }
        let subscription = CKDatabaseSubscription(subscriptionID: "sharingan-private-db")
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        Task { [weak self] in
            do {
                _ = try await ckDatabase.save(subscription)
                self?.database?.setSyncStateValue(StateKey.subscriptionSaved, Data([1]))
            } catch {
                self?.log.info("sync: subscription save failed (falling back to polling): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Active timer (Task 7)

    /// The other Mac's session, published for the coordinator to apply (when
    /// timer mirroring is on) and for the UI to describe. Only ever set to a
    /// state that passed `shouldApply` — echoes and stale records never land.
    @Published public private(set) var remoteTimer: ActiveTimerState?

    /// This Mac's latest timer snapshot, held for the record provider.
    private var localTimerState: ActiveTimerState?

    /// The freshest timer state known from either side — the `current` for
    /// the newest-wins rule.
    private var latestKnownTimer: ActiveTimerState?

    /// An echo of our own write must never surface as a "remote" timer.
    nonisolated public static func shouldSurface(remoteTimer: ActiveTimerState) -> Bool {
        remoteTimer.deviceID != DeviceIdentity.current
    }

    /// Whether a fetched ActiveTimer record should drive this Mac's timer.
    /// Pure — the three rejection rules, in order:
    ///   1. echo: our own deviceID (A starts → B applies → B publishes → A
    ///      must NOT re-apply forever);
    ///   2. stale: a RUNNING session whose deadline already passed is history,
    ///      not a command. A PAUSED session is never stale by clock — its
    ///      remaining time is frozen, not ticking;
    ///   3. newest wins: an older record than the freshest state we know
    ///      (either side) is out of date.
    nonisolated public static func shouldApply(remote: ActiveTimerState,
                                   now: Date,
                                   current: ActiveTimerState?) -> Bool {
        guard shouldSurface(remoteTimer: remote) else { return false }
        if !remote.isPaused, !remote.isIdle,
           let endsAt = remote.endsAt, endsAt <= now { return false }
        if let current, current.updatedAt > remote.updatedAt { return false }
        return true
    }

    /// Called by the coordinator on phase transitions (start/pause/resume/
    /// stop/complete) — never from the tick loop; a per-second write would
    /// burn quota and battery for no benefit.
    public func publishActiveTimer(_ state: ActiveTimerState) {
        localTimerState = state
        latestKnownTimer = MergePolicy.mergeTimer(local: latestKnownTimer,
                                                  remote: state)
        guard engine != nil else { return }
        engine?.state.add(pendingRecordZoneChanges:
            [.saveRecord(recordID(ActiveTimerState.recordName))])
    }

    private func applyFetchedTimer(_ record: CKRecord) {
        guard let state = RecordMapper.activeTimer(from: record) else { return }
        confirmShadow(.activeTimer, record, hash: state.contentHash)
        guard Self.shouldApply(remote: state, now: Date(),
                               current: latestKnownTimer) else { return }
        latestKnownTimer = state
        remoteTimer = state
    }

    private func timerRecord() -> CKRecord? {
        guard let state = localTimerState else { return nil }
        return RecordMapper.record(for: state, in: zoneID,
                                   systemFields: shadowFields(.activeTimer,
                                                              ActiveTimerState.recordName))
    }

    private func sentTimerHash(_ record: CKRecord) -> String? {
        RecordMapper.activeTimer(from: record)?.contentHash
    }

    // MARK: - Entitlement probe

    /// Whether this process was signed with the iCloud entitlement. Read from
    /// our own code signature via SecTask because CloudKit's failure mode for
    /// a missing entitlement is an Objective-C exception Swift cannot catch —
    /// the check must happen before ANY CKContainer call. A dev build, a
    /// `swift test` process, or a package built without the provisioning
    /// profile all land here and degrade to `.unavailable`.
    static var hasCloudKitEntitlement: Bool {
        let task = SecTaskCreateFromSelf(nil)
        guard let task else { return false }
        let value = SecTaskCopyValueForEntitlement(
            task, "com.apple.developer.icloud-services" as CFString, nil)
        return value != nil
    }

    // MARK: - Bookkeeping

    private func lastSyncedDate() -> Date? {
        guard let data = database?.syncStateValue(StateKey.lastSynced),
              let interval = try? JSONDecoder().decode(Double.self, from: data)
        else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    private func markSynced() {
        let now = Date()
        if let data = try? JSONEncoder().encode(now.timeIntervalSince1970) {
            database?.setSyncStateValue(StateKey.lastSynced, data)
        }
        status = .idle(lastSynced: now)
    }
}

// MARK: - CKSyncEngineDelegate

extension CloudSyncEngine: CKSyncEngineDelegate {
    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            // The engine's change tokens and pending-change bookkeeping;
            // persisting them is what lets the next launch resume instead of
            // re-fetching the world.
            if let data = try? JSONEncoder().encode(update.stateSerialization) {
                database?.setSyncStateValue(StateKey.engineState, data)
            }

        case .accountChange(let change):
            switch change.changeType {
            case .signIn:
                status = .idle(lastSynced: lastSyncedDate())
                enqueueLocalChanges()
            case .signOut:
                database?.resetSyncState()
                // Leaving one account for none is an account change too — the
                // queue must not carry this user's pushes into the next signer.
                outbox.reset()
                status = .unavailable("Signed out of iCloud")
            case .switchAccounts:
                // One person's shadow must never be merged into another's
                // database — reset and rebuild from scratch.
                accountChanged()
            @unknown default:
                break
            }

        case .fetchedRecordZoneChanges(let changes):
            applyFetched(modifications: changes.modifications.map(\.record),
                         deletions: changes.deletions)

        case .sentRecordZoneChanges(let sent):
            handleSent(sent)

        case .fetchedDatabaseChanges(let changes):
            // Our zone deleted server-side (user purged their iCloud data):
            // the shadow is now fiction. Reset it, recreate the zone, and let
            // the diff re-upload the local truth.
            if changes.deletions.contains(where: { $0.zoneID == zoneID }) {
                database?.resetSyncState()
                syncEngine.state.add(pendingDatabaseChanges:
                    [.saveZone(CKRecordZone(zoneID: zoneID))])
                enqueueLocalChanges()
            }

        case .willSendChanges, .willFetchChanges:
            status = .syncing

        case .didSendChanges, .didFetchChanges:
            markSynced()

        case .sentDatabaseChanges, .willFetchRecordZoneChanges,
             .didFetchRecordZoneChanges:
            break

        @unknown default:
            break
        }
    }

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges
            .filter { context.options.scope.contains($0) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) {
            [weak self] recordID in
            guard let self else { return nil }
            if recordID.recordName == ActiveTimerState.recordName {
                return await self.timerRecord()
            }
            return await self.record(for: recordID)
        }
    }
}
