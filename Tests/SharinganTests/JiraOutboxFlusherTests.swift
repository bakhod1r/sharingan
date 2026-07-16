import Foundation
import Testing
@testable import SharinganCore

// The outbox flusher drains queued writes to Jira. A local edit to a linked
// task doesn't hit the network immediately — it lands in the queue and the
// flusher sends it when it runs (launch, poll, "Push now"). This isolates the
// send/backoff/permanent-fail logic from the network with a stub client.
@Suite("Jira outbox flusher", .serialized)
struct JiraOutboxFlusherTests {

    private func tempStorage() throws -> (JiraStorage, String) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("jira-flush-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("t.sqlite").path
        return (try #require(JiraStorage(path: path)), path)
    }

    private func stubClient(_ handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) -> JiraClient {
        FlushStubProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FlushStubProtocol.self]
        return JiraClient(tokens: FlushStubTokens(), session: URLSession(configuration: config))
    }

    @Test("a fields op sends a PUT and is deleted on success")
    func fieldsOpSendsAndClears() async throws {
        let (storage, _) = try tempStorage()
        defer { FlushStubProtocol.handler = nil }
        let push = JiraPushFields(summary: "Renamed locally", priorityName: "High")
        let payload = String(data: try JSONEncoder().encode(push), encoding: .utf8)!
        storage.enqueue(OutboxItem(issueKey: "WT-689", op: .fields, payload: payload))

        let recorder = RequestRecorder()
        let client = stubClient { request in
            recorder.record(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 204,
                                           httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let flusher = JiraOutboxFlusher(client: client, storage: storage)

        let result = await flusher.flush()

        #expect(result.sent == 1)
        #expect(result.failed == 0)
        let sent = recorder.last
        #expect(sent?.method == "PUT")
        #expect(sent?.path == "/ex/jira/test-cloud/rest/api/3/issue/WT-689")
        let body = try JSONSerialization.jsonObject(with: try #require(sent?.body)) as? [String: Any]
        let fields = body?["fields"] as? [String: Any]
        #expect(fields?["summary"] as? String == "Renamed locally")
        #expect(storage.pendingCount() == 0)
    }

    @Test("a transient failure keeps the item and pushes its retry into the future")
    func transientFailureBacksOff() async throws {
        let (storage, _) = try tempStorage()
        defer { FlushStubProtocol.handler = nil }
        storage.enqueue(OutboxItem(issueKey: "WT-1", op: .fields, payload: "{}"))
        let client = stubClient { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 503,
                                           httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }
        let flusher = JiraOutboxFlusher(client: client, storage: storage)

        let result = await flusher.flush()

        #expect(result.sent == 0)
        #expect(result.failed == 0)          // not permanently failed — will retry
        #expect(storage.pendingCount() == 1)
        // Its next attempt is now in the future, so an immediate re-flush is a
        // no-op rather than a hot loop.
        let again = await flusher.flush()
        #expect(again.sent == 0)
        let items = storage.dueItems(now: Date())
        #expect(items.isEmpty)               // backed off — not yet due
    }

    @Test("a worklog op posts to the issue's worklog endpoint with adjustEstimate")
    func worklogOpSends() async throws {
        let (storage, _) = try tempStorage()
        defer { FlushStubProtocol.handler = nil }
        let payload = String(data: try JSONEncoder().encode(
            JiraWorklogPayload(timeSpentSeconds: 1500,
                               started: "2026-07-16T09:00:00.000+0000",
                               comment: "Focus session from Sharingan 🍅")),
                             encoding: .utf8)!
        storage.enqueue(OutboxItem(issueKey: "WT-702", op: .worklog, payload: payload))

        let recorder = RequestRecorder()
        let client = stubClient { request in
            recorder.record(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 201,
                                           httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"id":"90001","self":"https://x/worklog/90001","timeSpent":"25m","timeSpentSeconds":1500}"#.utf8))
        }
        let flusher = JiraOutboxFlusher(client: client, storage: storage)

        let result = await flusher.flush()

        #expect(result.sent == 1)
        let sent = recorder.last
        #expect(sent?.method == "POST")
        #expect(sent?.path == "/ex/jira/test-cloud/rest/api/3/issue/WT-702/worklog")
        let body = try JSONSerialization.jsonObject(with: try #require(sent?.body)) as? [String: Any]
        #expect(body?["timeSpentSeconds"] as? Int == 1500)
        #expect(storage.pendingCount() == 0)
    }

    @Test("a permanent failure marks the item failed and stops retrying")
    func permanentFailureMarksFailed() async throws {
        let (storage, _) = try tempStorage()
        defer { FlushStubProtocol.handler = nil }
        storage.enqueue(OutboxItem(issueKey: "WT-1", op: .fields, payload: "{}"))
        let client = stubClient { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 400,
                                           httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"errorMessages":["Field 'summary' is required."]}"#.utf8))
        }
        let flusher = JiraOutboxFlusher(client: client, storage: storage)

        let result = await flusher.flush()

        #expect(result.failed == 1)
        #expect(storage.dueItems(now: Date()).isEmpty)   // no longer retried…
        let failed = storage.failedItems()
        #expect(failed.count == 1)                        // …it's in the failed set
        #expect(failed.first?.lastError?.contains("summary") == true)
    }
}

// MARK: - Test doubles

private struct FlushStubTokens: JiraTokenProviding {
    func accessToken() async throws -> String { "test-token" }
    func cloudID() async throws -> String { "test-cloud" }
}

/// Captures requests from the stub handler (which runs off the test's task)
/// without a mutable capture the Swift 6 concurrency checker rejects.
private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [(path: String?, method: String?, body: Data?)] = []
    func record(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        requests.append((request.url?.path, request.httpMethod, request.bodyData))
    }
    var last: (path: String?, method: String?, body: Data?)? {
        lock.lock(); defer { lock.unlock() }
        return requests.last
    }
}

private final class FlushStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}
// `URLRequest.bodyData` (drains httpBodyStream) is defined module-wide in
// JiraIntegrationTests.swift — reused here.
