import Foundation
import Combine

// MARK: - Section state

/// One independently-fetched section of the issue detail sheet.
///
/// The distinction that matters is `loaded([])` vs `failed`: an issue with no
/// comments and a comments fetch that 500'd must never render the same. The UI
/// says "No comments yet" only for the former.
public enum JiraDetailSection<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value)
    case failed(JiraError)

    public var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    public var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    public var errorMessage: String? {
        if case .failed(let error) = self { return error.userMessage }
        return nil
    }
}

extension JiraDetailSection: Equatable where Value: Equatable {}

// MARK: - History entry

/// One rendered row of the History tab: a single field change, flattened out of
/// Jira's `histories[].items[]` nesting. Groups with no items (Jira's own
/// bookkeeping) never become entries.
public struct JiraHistoryEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let field: String
    /// The previous human-readable value. Jira sends `""` for "was unset";
    /// that is normalized to nil so the UI can say "None" instead of a blank.
    public let from: String?
    public let to: String?
    public let authorName: String
    public let date: Date?

    public init(id: String, field: String, from: String?, to: String?, authorName: String, date: Date?) {
        self.id = id
        self.field = field
        self.from = from
        self.to = to
        self.authorName = authorName
        self.date = date
    }
}

// MARK: - Model

/// View model for the issue detail sheet — description, comments, change
/// history and worklogs, all readable without opening Jira.
///
/// Each section loads, succeeds or fails independently; one broken fetch never
/// takes down the rest. Rich text goes through the plain-text ADF bridge
/// (`ADF.plainText` / `ADF.document(fromPlainText:)`): reads render read-only
/// as text, writes replace formatting with plain paragraphs — the view carries
/// a caption saying so.
@MainActor
public final class JiraIssueDetailModel: ObservableObject {

    public let issueKey: String
    public let siteHost: String
    private let client: JiraClient

    @Published public private(set) var details: JiraDetailSection<JiraIssue> = .idle
    @Published public private(set) var comments: JiraDetailSection<[JiraComment]> = .idle
    @Published public private(set) var history: JiraDetailSection<[JiraHistoryEntry]> = .idle
    @Published public private(set) var worklogs: JiraDetailSection<[JiraWorklog]> = .idle

    @Published public private(set) var isPostingComment = false
    @Published public private(set) var isSavingDescription = false
    /// A failure of a user *action* (post comment, save description) — distinct
    /// from a section failing to load.
    @Published public private(set) var actionErrorMessage: String?

    public init(client: JiraClient, issueKey: String, siteHost: String) {
        self.client = client
        self.issueKey = issueKey
        self.siteHost = siteHost
    }

    // MARK: Derived

    /// The issue summary, falling back to the key so the header is never blank.
    public var summaryText: String {
        let summary = details.value?.fields.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let summary, !summary.isEmpty { return summary }
        return issueKey
    }

    /// The description rendered through the plain-text ADF bridge.
    public var descriptionText: String {
        guard let document = details.value?.fields.description,
              let data = try? JSONEncoder().encode(document) else { return "" }
        return ADF.plainText(from: data)
    }

    public var statusName: String? { details.value?.fields.status?.name }
    public var issueTypeName: String? { details.value?.fields.issuetype?.name }

    public var isLoading: Bool {
        details.isLoading || comments.isLoading || history.isLoading || worklogs.isLoading
    }

    /// `https://{siteHost}/browse/{key}`, tolerant of a site host stored with a
    /// scheme or trailing slash.
    public var browseURL: URL? {
        var host = siteHost
        if let range = host.range(of: "://") {
            host = String(host[range.upperBound...])
        }
        host = host.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !host.isEmpty else { return nil }
        return URL(string: "https://\(host)/browse/\(issueKey)")
    }

    // MARK: Loading

    /// Fetches all four sections concurrently. Each lands in its own state;
    /// a failure in one leaves the others intact.
    public func load() async {
        details = .loading
        comments = .loading
        history = .loading
        worklogs = .loading

        let client = self.client
        let key = self.issueKey

        async let issueResult = Self.capture { try await client.getIssue(key: key) }
        async let commentsResult = Self.capture { try await client.getComments(issueKey: key, maxResults: 100).comments }
        async let changelogResult = Self.capture { try await client.getChangelog(issueKey: key).histories }
        async let worklogsResult = Self.capture { try await client.getWorklogs(issueKey: key, maxResults: 100).worklogs }

        details = Self.section(from: await issueResult)
        comments = Self.section(from: await commentsResult)
        history = Self.section(from: await changelogResult.map(Self.entries(from:)))
        worklogs = Self.section(from: await worklogsResult)
    }

    // MARK: Actions

    /// Posts `text` as a plain-text ADF comment and refreshes the list.
    /// Blank input is ignored without touching the network.
    public func addComment(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isPostingComment = true
        actionErrorMessage = nil
        defer { isPostingComment = false }

        do {
            _ = try await client.addComment(issueKey: issueKey, body: trimmed)
            let refreshed = try await client.getComments(issueKey: issueKey, maxResults: 100)
            comments = .loaded(refreshed.comments)
        } catch {
            actionErrorMessage = Self.jiraError(from: error).userMessage
        }
    }

    /// Saves `text` as the issue description — plain-text ADF, one paragraph
    /// per line — then re-reads the issue so the sheet reflects what Jira kept.
    /// Only the description travels; no other field is sent.
    public func saveDescription(_ text: String) async {
        isSavingDescription = true
        actionErrorMessage = nil
        defer { isSavingDescription = false }

        do {
            let data = ADF.document(fromPlainText: text)
            let document = try JSONDecoder().decode(JiraADFDocument.self, from: data)
            try await client.updateIssue(key: issueKey, fields: JiraIssueUpdateFields(description: document))
            let issue = try await client.getIssue(key: issueKey)
            details = .loaded(issue)
        } catch {
            actionErrorMessage = Self.jiraError(from: error).userMessage
        }
    }

    // MARK: Mapping helpers

    /// Flattens changelog groups into one entry per changed field, dropping
    /// groups with no items and normalizing Jira's `""`-means-unset values.
    static func entries(from histories: [JiraChangelogHistory]) -> [JiraHistoryEntry] {
        histories.flatMap { history in
            history.items.enumerated().map { index, item in
                JiraHistoryEntry(id: "\(history.id)-\(index)",
                                 field: item.field,
                                 from: Self.nonEmpty(item.fromString),
                                 to: Self.nonEmpty(item.toString),
                                 authorName: history.author.displayName,
                                 date: Self.date(from: history.created))
            }
        }
    }

    /// Parses Jira's REST timestamp format (`2026-07-14T09:00:00.000+0000`).
    public static func date(from string: String) -> Date? {
        jiraDateFormatter.date(from: string)
    }

    private static let jiraDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return formatter
    }()

    private static func nonEmpty(_ string: String?) -> String? {
        guard let string, !string.isEmpty else { return nil }
        return string
    }

    private static func capture<T: Sendable>(_ operation: @Sendable () async throws -> T) async -> Result<T, JiraError> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(jiraError(from: error))
        }
    }

    private static func section<T>(from result: Result<T, JiraError>) -> JiraDetailSection<T> {
        switch result {
        case .success(let value): return .loaded(value)
        case .failure(let error): return .failed(error)
        }
    }

    private static func jiraError(from error: Error) -> JiraError {
        (error as? JiraError) ?? .network(error.localizedDescription)
    }
}
