import Foundation
import Testing
@testable import SharinganCore

// Sharingan → Jira, the create direction: a local task becomes a Jira issue in
// the mapped project and links back. The create payload must carry project +
// issuetype (Jira 400s without them) — the old updateFields path couldn't.
@Suite("Jira create issue", .serialized)
struct JiraCreateIssueTests {

    private func stubClient(_ handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) -> JiraClient {
        CreateStubProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CreateStubProtocol.self]
        return JiraClient(tokens: CreateStubTokens(), session: URLSession(configuration: config))
    }

    @Test("createIssue posts project, issuetype, summary and priority")
    func createIssuePostsRequiredFields() async throws {
        defer { CreateStubProtocol.handler = nil }
        let recorder = RequestRecorder()
        let client = stubClient { request in
            recorder.record(request)
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"id":"10500","key":"SHRGN-8"}"#.utf8))
        }

        let created = try await client.createIssue(fields: JiraIssueCreateFields(
            projectKey: "SHRGN", issueTypeName: "Task",
            summary: "Ship the thing", priorityName: "High"))

        #expect(created.key == "SHRGN-8")
        let sent = recorder.last
        #expect(sent?.method == "POST")
        #expect(sent?.path == "/ex/jira/test-cloud/rest/api/3/issue")
        let body = try JSONSerialization.jsonObject(with: try #require(sent?.body)) as? [String: Any]
        let fields = body?["fields"] as? [String: Any]
        #expect((fields?["project"] as? [String: Any])?["key"] as? String == "SHRGN")
        #expect((fields?["issuetype"] as? [String: Any])?["name"] as? String == "Task")
        #expect(fields?["summary"] as? String == "Ship the thing")
        #expect((fields?["priority"] as? [String: Any])?["name"] as? String == "High")
    }

    @MainActor
    private func makeService(_ handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data))
    throws -> (JiraService, TaskStore) {
        let suite = "jira-create-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set(Date().addingTimeInterval(3600).timeIntervalSince1970,
                     forKey: JiraTokenStore.expiresAtDefaultsKey)
        defaults.set("test-cloud", forKey: JiraTokenStore.cloudIDDefaultsKey)
        defaults.set("https://wayll.atlassian.net", forKey: JiraTokenStore.siteURLDefaultsKey)
        defaults.set(["read:jira-work"], forKey: JiraTokenStore.scopesDefaultsKey)
        let store = JiraTokenStore(defaults: defaults,
                                   readToken: { _, a in a == JiraTokenStore.accessTokenAccount ? "acc" : "ref" },
                                   writeToken: { _, _, _ in }, deleteToken: { _, _ in })
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("jira-create-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storage = try #require(JiraStorage(path: dir.appendingPathComponent("t.sqlite").path))
        let tasks = TaskStore(fileURL: dir.appendingPathComponent("tasks.sqlite"))
        CreateStubProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CreateStubProtocol.self]
        let session = URLSession(configuration: config)
        let service = JiraService(defaults: defaults, store: store, oauthConfig: nil,
                                  oauthSession: session, apiSession: session,
                                  issueCache: storage, taskStore: tasks, restoreOnInit: false)
        return (service, tasks)
    }

    @Test("creating from a task links the returned key back onto the task")
    @MainActor
    func createFromTaskLinksBack() async throws {
        defer { CreateStubProtocol.handler = nil }
        let (service, tasks) = try makeService { request in
            (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!,
             Data(#"{"id":"10500","key":"SHRGN-8"}"#.utf8))
        }
        tasks.add(title: "Ship the thing", priority: .high)
        let task = try #require(tasks.tasks.first { $0.title == "Ship the thing" })

        let ok = await service.createIssue(from: task, projectKey: "SHRGN")

        #expect(ok)
        let linked = try #require(tasks.tasks.first { $0.id == task.id })
        #expect(linked.jiraKey == "SHRGN-8")
        #expect(linked.jiraIssueID == "10500")
        #expect(linked.jiraSiteHost == "wayll.atlassian.net")
    }
}

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

private struct CreateStubTokens: JiraTokenProviding {
    func accessToken() async throws -> String { "t" }
    func cloudID() async throws -> String { "test-cloud" }
}

private final class CreateStubProtocol: URLProtocol, @unchecked Sendable {
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
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
