import Foundation
import SQLite3

/// The last-seen snapshot of a Jira issue: every field Jira owns, exactly as it
/// was last fetched. This is the base of the three-way merge in
/// `JiraFieldMapper` — without it a local edit and a remote edit are
/// indistinguishable, and one of them always gets silently clobbered.
public struct CachedJiraIssue: Equatable, Sendable {
    public var issueID: String
    public var issueKey: String
    public var siteHost: String
    public var summary: String
    public var statusID: String?
    public var statusName: String?
    public var statusCategory: String?
    public var issueType: String?
    public var priorityName: String?
    public var assigneeName: String?
    public var labels: [String]
    public var components: [String]
    public var projectKey: String?
    /// Jira's `duedate`, kept in its wire form (`yyyy-MM-dd`, UTC).
    public var dueDate: String?
    /// Jira's `timeoriginalestimate`, in seconds.
    public var estimateSeconds: Int?
    /// The raw ADF description JSON, kept verbatim so nothing is lost until the
    /// user actually edits the description (see `ADF`).
    public var descriptionADF: String?
    /// Jira's own `updated` timestamp.
    public var jiraUpdated: Date?
    /// When *we* fetched this row.
    public var fetchedAt: Date

    public init(issueID: String,
                issueKey: String,
                siteHost: String,
                summary: String,
                statusID: String? = nil,
                statusName: String? = nil,
                statusCategory: String? = nil,
                issueType: String? = nil,
                priorityName: String? = nil,
                assigneeName: String? = nil,
                labels: [String] = [],
                components: [String] = [],
                projectKey: String? = nil,
                dueDate: String? = nil,
                estimateSeconds: Int? = nil,
                descriptionADF: String? = nil,
                jiraUpdated: Date? = nil,
                fetchedAt: Date = Date()) {
        self.issueID = issueID
        self.issueKey = issueKey
        self.siteHost = siteHost
        self.summary = summary
        self.statusID = statusID
        self.statusName = statusName
        self.statusCategory = statusCategory
        self.issueType = issueType
        self.priorityName = priorityName
        self.assigneeName = assigneeName
        self.labels = labels
        self.components = components
        self.projectKey = projectKey
        self.dueDate = dueDate
        self.estimateSeconds = estimateSeconds
        self.descriptionADF = descriptionADF
        self.jiraUpdated = jiraUpdated
        self.fetchedAt = fetchedAt
    }
}

/// What a queued outbox item asks Jira to do. Rows carrying an `op` this build
/// doesn't recognize are skipped on read rather than coerced: an unknown op can
/// only come from a newer Sharingan writing to the same file, and this build
/// couldn't execute it correctly anyway — dropping it from `dueItems` leaves
/// the row intact for the build that understands it.
public enum JiraOutboxOp: String, Equatable, Sendable {
    case worklog
    case fields
    case transition
    case comment
}

/// One pending write to Jira, durable across launches.
public struct OutboxItem: Equatable, Sendable {
    public var id: UUID
    public var issueKey: String
    public var op: JiraOutboxOp
    /// Op-specific JSON body (e.g. an encoded `JiraWorklogInput`).
    public var payload: String
    public var createdAt: Date
    public var attempts: Int
    /// Earliest time the sender may retry — the backoff clock.
    public var nextAttemptAt: Date
    /// Set once the item has exhausted retries; `dueItems` skips it and the UI
    /// surfaces it for manual retry or discard.
    public var failed: Bool
    public var lastError: String?

    public init(id: UUID = UUID(),
                issueKey: String,
                op: JiraOutboxOp = .worklog,
                payload: String,
                createdAt: Date = Date(),
                attempts: Int = 0,
                nextAttemptAt: Date = Date(timeIntervalSince1970: 0),
                failed: Bool = false,
                lastError: String? = nil) {
        self.id = id
        self.issueKey = issueKey
        self.op = op
        self.payload = payload
        self.createdAt = createdAt
        self.attempts = attempts
        self.nextAttemptAt = nextAttemptAt
        self.failed = failed
        self.lastError = lastError
    }
}

/// Jira's local cache and write queue.
///
/// Opens its **own** connection to the same `blink.sqlite` file `TaskDatabase`
/// uses — WAL lets a second connection read and write alongside the first, and
/// keeping the Jira tables here means the task layer never grows a Jira
/// dependency. Style follows `TaskDatabase`: raw SQLite3 C API, prepared
/// statements, `ALTER TABLE ADD COLUMN` migrations.
///
/// **Neither table ever syncs to CloudKit.** `jira_issues` is a cache that can
/// be refetched from Jira at any time, and `jira_outbox` is strictly per-Mac:
/// syncing pending writes would let two Macs replay the same worklog, double
/// logging the user's time. Only the *task* rows sync; these are local.
public final class JiraStorage {
    private var db: OpaquePointer?

    /// SQLite needs to copy bound strings/blobs (they're freed after the call).
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// `path` is the SQLite database file; tests pass a temp file, the app
    /// passes `Application Support/Sharingan/blink.sqlite`.
    public init?(path: String) {
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            sqlite3_close(db); db = nil; return nil
        }
        exec("PRAGMA journal_mode=WAL;")
        exec("PRAGMA busy_timeout=3000;")
        createTables()
    }

    deinit { sqlite3_close(db) }

    /// The database the app uses — the same file `TaskStore` opens.
    public static func defaultDatabaseURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Sharingan", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("blink.sqlite")
    }

    // MARK: - Schema

    private func createTables() {
        exec("""
        CREATE TABLE IF NOT EXISTS jira_issues (
            issue_id TEXT PRIMARY KEY,
            issue_key TEXT NOT NULL,
            site_host TEXT NOT NULL,
            summary TEXT NOT NULL,
            status_id TEXT,
            status_name TEXT,
            status_category TEXT,
            issue_type TEXT,
            priority_name TEXT,
            assignee_name TEXT,
            labels TEXT,
            components TEXT,
            project_key TEXT,
            duedate TEXT,
            estimate_seconds INTEGER,
            description_adf TEXT,
            jira_updated REAL,
            fetched_at REAL NOT NULL
        );
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS jira_outbox (
            id TEXT PRIMARY KEY,
            issue_key TEXT NOT NULL,
            op TEXT NOT NULL DEFAULT 'worklog',
            payload TEXT NOT NULL,
            created_at REAL NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            next_attempt_at REAL NOT NULL DEFAULT 0,
            failed INTEGER NOT NULL DEFAULT 0,
            last_error TEXT
        );
        """)
        // Lookup by key is the hot path (tasks store `jiraKey`, not the ID).
        exec("CREATE INDEX IF NOT EXISTS jira_issues_key ON jira_issues (issue_key);")
        exec("CREATE INDEX IF NOT EXISTS jira_outbox_due ON jira_outbox (failed, next_attempt_at);")
    }

    // MARK: - Issue cache

    public func upsertIssue(_ cached: CachedJiraIssue) {
        let sql = """
        INSERT INTO jira_issues (issue_id, issue_key, site_host, summary, status_id, status_name,
        status_category, issue_type, priority_name, assignee_name, labels, components, project_key,
        duedate, estimate_seconds, description_adf, jira_updated, fetched_at)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(issue_id) DO UPDATE SET
            issue_key = excluded.issue_key,
            site_host = excluded.site_host,
            summary = excluded.summary,
            status_id = excluded.status_id,
            status_name = excluded.status_name,
            status_category = excluded.status_category,
            issue_type = excluded.issue_type,
            priority_name = excluded.priority_name,
            assignee_name = excluded.assignee_name,
            labels = excluded.labels,
            components = excluded.components,
            project_key = excluded.project_key,
            duedate = excluded.duedate,
            estimate_seconds = excluded.estimate_seconds,
            description_adf = excluded.description_adf,
            jira_updated = excluded.jira_updated,
            fetched_at = excluded.fetched_at;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, cached.issueID)
        bindText(stmt, 2, cached.issueKey)
        bindText(stmt, 3, cached.siteHost)
        bindText(stmt, 4, cached.summary)
        bindOptionalText(stmt, 5, cached.statusID)
        bindOptionalText(stmt, 6, cached.statusName)
        bindOptionalText(stmt, 7, cached.statusCategory)
        bindOptionalText(stmt, 8, cached.issueType)
        bindOptionalText(stmt, 9, cached.priorityName)
        bindOptionalText(stmt, 10, cached.assigneeName)
        bindText(stmt, 11, encodeJSON(cached.labels) ?? "[]")
        bindText(stmt, 12, encodeJSON(cached.components) ?? "[]")
        bindOptionalText(stmt, 13, cached.projectKey)
        bindOptionalText(stmt, 14, cached.dueDate)
        if let seconds = cached.estimateSeconds { sqlite3_bind_int64(stmt, 15, Int64(seconds)) }
        else { sqlite3_bind_null(stmt, 15) }
        bindOptionalText(stmt, 16, cached.descriptionADF)
        bindDate(stmt, 17, cached.jiraUpdated)
        sqlite3_bind_double(stmt, 18, cached.fetchedAt.timeIntervalSince1970)
        _ = sqlite3_step(stmt)
    }

    public func issue(id: String) -> CachedJiraIssue? {
        firstIssue(where: "issue_id = ?", value: id)
    }

    /// Issue keys move when an issue is moved between projects, so the ID is the
    /// identity — but tasks carry the key, so this lookup has to exist too.
    public func issue(key: String) -> CachedJiraIssue? {
        firstIssue(where: "issue_key = ?", value: key)
    }

    public func allIssues() -> [CachedJiraIssue] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, Self.issueSelect + ";", -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [CachedJiraIssue] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cached = readIssue(stmt) { out.append(cached) }
        }
        return out
    }

    public func deleteIssue(id: String) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM jira_issues WHERE issue_id = ?;", -1, &stmt, nil) == SQLITE_OK
        else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, id)
        _ = sqlite3_step(stmt)
    }

    private static let issueSelect = """
    SELECT issue_id, issue_key, site_host, summary, status_id, status_name, status_category, \
    issue_type, priority_name, assignee_name, labels, components, project_key, duedate, \
    estimate_seconds, description_adf, jira_updated, fetched_at FROM jira_issues
    """

    private func firstIssue(where clause: String, value: String) -> CachedJiraIssue? {
        var stmt: OpaquePointer?
        let sql = "\(Self.issueSelect) WHERE \(clause) LIMIT 1;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, value)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return readIssue(stmt)
    }

    private func readIssue(_ stmt: OpaquePointer?) -> CachedJiraIssue? {
        guard let issueID = text(stmt, 0), let issueKey = text(stmt, 1) else { return nil }
        return CachedJiraIssue(
            issueID: issueID,
            issueKey: issueKey,
            siteHost: text(stmt, 2) ?? "",
            summary: text(stmt, 3) ?? "",
            statusID: text(stmt, 4),
            statusName: text(stmt, 5),
            statusCategory: text(stmt, 6),
            issueType: text(stmt, 7),
            priorityName: text(stmt, 8),
            assigneeName: text(stmt, 9),
            labels: decodeJSON([String].self, text(stmt, 10)) ?? [],
            components: decodeJSON([String].self, text(stmt, 11)) ?? [],
            projectKey: text(stmt, 12),
            dueDate: text(stmt, 13),
            estimateSeconds: isNull(stmt, 14) ? nil : Int(int(stmt, 14)),
            descriptionADF: text(stmt, 15),
            jiraUpdated: date(stmt, 16),
            fetchedAt: Date(timeIntervalSince1970: double(stmt, 17)))
    }

    // MARK: - Outbox

    public func enqueue(_ item: OutboxItem) {
        let sql = """
        INSERT INTO jira_outbox (id, issue_key, op, payload, created_at, attempts,
        next_attempt_at, failed, last_error)
        VALUES (?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET
            issue_key = excluded.issue_key,
            op = excluded.op,
            payload = excluded.payload,
            attempts = excluded.attempts,
            next_attempt_at = excluded.next_attempt_at,
            failed = excluded.failed,
            last_error = excluded.last_error;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindItem(stmt, item)
        _ = sqlite3_step(stmt)
    }

    /// Queued items whose backoff has elapsed, oldest first. Skips failed items.
    public func dueItems(now: Date = Date()) -> [OutboxItem] {
        var stmt: OpaquePointer?
        let sql = "\(Self.outboxSelect) WHERE failed = 0 AND next_attempt_at <= ? ORDER BY created_at;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, now.timeIntervalSince1970)
        return readItems(stmt)
    }

    /// Writes back attempt count, backoff and error after a send attempt.
    public func update(_ item: OutboxItem) {
        let sql = """
        UPDATE jira_outbox SET issue_key = ?, op = ?, payload = ?, attempts = ?,
        next_attempt_at = ?, failed = ?, last_error = ? WHERE id = ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, item.issueKey)
        bindText(stmt, 2, item.op.rawValue)
        bindText(stmt, 3, item.payload)
        sqlite3_bind_int64(stmt, 4, Int64(item.attempts))
        sqlite3_bind_double(stmt, 5, item.nextAttemptAt.timeIntervalSince1970)
        sqlite3_bind_int(stmt, 6, item.failed ? 1 : 0)
        bindOptionalText(stmt, 7, item.lastError)
        bindText(stmt, 8, item.id.uuidString)
        _ = sqlite3_step(stmt)
    }

    public func delete(id: UUID) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM jira_outbox WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK
        else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, id.uuidString)
        _ = sqlite3_step(stmt)
    }

    /// Everything still queued, failed or not — the badge count.
    public func pendingCount() -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM jira_outbox;", -1, &stmt, nil) == SQLITE_OK
        else { return 0 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(int(stmt, 0))
    }

    public func failedItems() -> [OutboxItem] {
        var stmt: OpaquePointer?
        let sql = "\(Self.outboxSelect) WHERE failed = 1 ORDER BY created_at;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        return readItems(stmt)
    }

    private static let outboxSelect = """
    SELECT id, issue_key, op, payload, created_at, attempts, next_attempt_at, failed, last_error \
    FROM jira_outbox
    """

    private func bindItem(_ stmt: OpaquePointer?, _ item: OutboxItem) {
        bindText(stmt, 1, item.id.uuidString)
        bindText(stmt, 2, item.issueKey)
        bindText(stmt, 3, item.op.rawValue)
        bindText(stmt, 4, item.payload)
        sqlite3_bind_double(stmt, 5, item.createdAt.timeIntervalSince1970)
        sqlite3_bind_int64(stmt, 6, Int64(item.attempts))
        sqlite3_bind_double(stmt, 7, item.nextAttemptAt.timeIntervalSince1970)
        sqlite3_bind_int(stmt, 8, item.failed ? 1 : 0)
        bindOptionalText(stmt, 9, item.lastError)
    }

    private func readItems(_ stmt: OpaquePointer?) -> [OutboxItem] {
        var out: [OutboxItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idText = text(stmt, 0), let id = UUID(uuidString: idText),
                  let issueKey = text(stmt, 1),
                  let op = text(stmt, 2).flatMap(JiraOutboxOp.init(rawValue:)),
                  let payload = text(stmt, 3)
            else { continue }
            out.append(OutboxItem(id: id,
                                  issueKey: issueKey,
                                  op: op,
                                  payload: payload,
                                  createdAt: Date(timeIntervalSince1970: double(stmt, 4)),
                                  attempts: Int(int(stmt, 5)),
                                  nextAttemptAt: Date(timeIntervalSince1970: double(stmt, 6)),
                                  failed: int(stmt, 7) != 0,
                                  lastError: text(stmt, 8)))
        }
        return out
    }

    // MARK: - Low-level helpers

    @discardableResult
    private func exec(_ sql: String) -> Bool { sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK }

    private func bindText(_ stmt: OpaquePointer?, _ i: Int32, _ value: String) {
        sqlite3_bind_text(stmt, i, value, -1, Self.transient)
    }
    private func bindOptionalText(_ stmt: OpaquePointer?, _ i: Int32, _ value: String?) {
        if let value { bindText(stmt, i, value) } else { sqlite3_bind_null(stmt, i) }
    }
    private func bindDate(_ stmt: OpaquePointer?, _ i: Int32, _ date: Date?) {
        if let d = date { sqlite3_bind_double(stmt, i, d.timeIntervalSince1970) }
        else { sqlite3_bind_null(stmt, i) }
    }

    private func text(_ stmt: OpaquePointer?, _ i: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, i) else { return nil }
        return String(cString: c)
    }
    private func int(_ stmt: OpaquePointer?, _ i: Int32) -> Int64 { sqlite3_column_int64(stmt, i) }
    private func double(_ stmt: OpaquePointer?, _ i: Int32) -> Double { sqlite3_column_double(stmt, i) }
    private func isNull(_ stmt: OpaquePointer?, _ i: Int32) -> Bool {
        sqlite3_column_type(stmt, i) == SQLITE_NULL
    }
    private func date(_ stmt: OpaquePointer?, _ i: Int32) -> Date? {
        isNull(stmt, i) ? nil : Date(timeIntervalSince1970: double(stmt, i))
    }

    private func encodeJSON<T: Encodable>(_ value: T) -> String? {
        (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) }
    }
    private func decodeJSON<T: Decodable>(_ type: T.Type, _ json: String?) -> T? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? decoder.decode(type, from: data)
    }
}
