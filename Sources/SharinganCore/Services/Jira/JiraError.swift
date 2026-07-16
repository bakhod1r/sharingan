import Foundation

/// Failure taxonomy for every Jira REST call. `isRetryable` decides whether the
/// worklog outbox keeps a queued item alive (network / 5xx / 429) or marks it
/// permanently failed (auth / not-found / validation).
public enum JiraError: Error, Equatable, Sendable {
    /// No credentials configured — the client was used before `connect`.
    case notConfigured
    /// 401 — bad email/token pair.
    case unauthorized
    /// 403 — authenticated but not permitted (project/issue permissions).
    case forbidden
    /// 404 — issue/resource does not exist or isn't visible.
    case notFound
    /// 429 — rate limited; honor `Retry-After` when Jira supplies it.
    case rateLimited(retryAfter: TimeInterval?)
    /// 400 and other client errors with a parseable Jira error payload.
    case api(status: Int, messages: [String])
    /// 5xx.
    case server(status: Int)
    /// Transport failure (offline, DNS, TLS, timeout).
    case network(String)
    /// Response body could not be decoded into the expected shape.
    case decoding(String)

    /// Whether the outbox should keep retrying an operation that hit this error.
    public var isRetryable: Bool {
        switch self {
        case .network, .server, .rateLimited:
            return true
        case .notConfigured, .unauthorized, .forbidden, .notFound, .api, .decoding:
            return false
        }
    }

    /// A short, user-facing description for Settings and toasts.
    public var userMessage: String {
        switch self {
        case .notConfigured:      return "Jira isn't connected."
        case .unauthorized:       return "Your Jira session expired — reconnect to continue."
        case .forbidden:          return "You don't have permission for that in Jira."
        case .notFound:           return "That Jira issue no longer exists."
        case .rateLimited:        return "Jira is rate limiting requests — will retry."
        case .api(_, let msgs):   return msgs.first ?? "Jira rejected the request."
        case .server(let status): return "Jira server error (\(status)) — will retry."
        case .network(let why):   return "Network error: \(why)"
        case .decoding:           return "Unexpected response from Jira."
        }
    }
}
