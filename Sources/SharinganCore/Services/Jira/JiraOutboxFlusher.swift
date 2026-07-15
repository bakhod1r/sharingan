import Foundation

/// Drains the Jira write queue.
///
/// A local edit to a linked task never hits the network on the spot — it lands
/// in `jira_outbox` and this flusher sends it when it runs (launch, the poll
/// timer, or a manual "Push now"). Keeping sends off the edit path means a
/// flaky connection or a rate limit degrades to "pending" instead of a failed
/// keystroke, and several quick edits coalesce into one write.
///
/// Standalone (takes a `JiraClient` and `JiraStorage`) so it tests against the
/// URLProtocol stub without dragging in `JiraService`.
public actor JiraOutboxFlusher {
    private let client: JiraClient
    private let storage: JiraStorage

    public init(client: JiraClient, storage: JiraStorage) {
        self.client = client
        self.storage = storage
    }

    /// Backoff schedule by attempt count: 30s, 2m, 10m, 1h, then hourly.
    static func backoff(afterAttempts attempts: Int) -> TimeInterval {
        switch attempts {
        case ...1: return 30
        case 2:    return 120
        case 3:    return 600
        default:   return 3600
        }
    }

    /// Sends every item whose retry time has arrived. Returns how many were
    /// delivered and how many hit a permanent error this pass.
    @discardableResult
    public func flush(now: Date = Date()) async -> (sent: Int, failed: Int) {
        var sent = 0, failed = 0
        for var item in storage.dueItems(now: now) {
            do {
                try await execute(item)
                storage.delete(id: item.id)
                sent += 1
            } catch let error as JiraError where !error.isRetryable {
                item.failed = true
                item.attempts += 1
                item.lastError = error.userMessage
                storage.update(item)
                failed += 1
            } catch {
                // Transient (network, 5xx, 429) — keep it and back the clock off
                // so an immediate re-flush doesn't spin.
                item.attempts += 1
                item.nextAttemptAt = now.addingTimeInterval(Self.backoff(afterAttempts: item.attempts))
                item.lastError = (error as? JiraError)?.userMessage ?? error.localizedDescription
                storage.update(item)
            }
        }
        return (sent, failed)
    }

    private func execute(_ item: OutboxItem) async throws {
        switch item.op {
        case .fields:
            let push = try JSONDecoder().decode(JiraPushFields.self,
                                                from: Data(item.payload.utf8))
            try await client.updateIssue(key: item.issueKey, fields: push.asUpdateFields)
        case .worklog, .transition, .comment:
            // Wired in the worklog/transition milestone; until then the row
            // stays queued rather than being dropped or failed.
            throw JiraError.network("op \(item.op.rawValue) not yet supported")
        }
    }
}

extension JiraPushFields {
    /// The Jira REST update payload for a queued field change. Priority is sent
    /// by name (Jira accepts either id or name); a nil member is omitted.
    var asUpdateFields: JiraIssueUpdateFields {
        JiraIssueUpdateFields(
            summary: summary,
            priority: nil,
            labels: labels,
            duedate: duedate,
            timeoriginalestimate: timeoriginalestimate)
    }
}
