import Foundation
import Testing
@testable import SharinganCore

// Quick-add `jira SHRGN-5`: typing that into the composer must fetch and link
// the real issue, not create a local task literally titled "jira SHRGN-5".
@Suite("Jira quick-add", .serialized)
struct JiraQuickAddTests {

    // MARK: - Parsing

    @Test("`jira SHRGN-5` is recognized as an issue key, case-insensitively",
          arguments: [
            ("jira SHRGN-5", "SHRGN-5"),
            ("JIRA shrgn-12", "SHRGN-12"),
            ("  jira  WT-100  ", "WT-100"),
            ("Jira ab1-7", "AB1-7"),
          ])
    func parsesJiraQuickAdd(input: String, key: String) {
        #expect(TaskInputParser.parse(input).jiraIssueKey == key)
    }

    @Test("ordinary lines that merely mention jira stay ordinary tasks",
          arguments: [
            "jira meeting notes",
            "jira",
            "fix jira SHRGN-5",
            "jira SHRGN-",
            "jira -5",
            "jira S-5",
            "jira SHRGN-5 extra",
            "\\jira SHRGN-5",
          ])
    func doesNotClaimOrdinaryLines(input: String) {
        #expect(TaskInputParser.parse(input).jiraIssueKey == nil)
    }

    @Test("a plain task line leaves jiraIssueKey nil and parses as before")
    func plainLineUnaffected() {
        let parsed = TaskInputParser.parse("p1 #ish write report")
        #expect(parsed.jiraIssueKey == nil)
        #expect(parsed.title == "write report")
        #expect(parsed.priority == .high)
        #expect(parsed.tags == ["ish"])
    }

    // MARK: - Import

    @Test("importing a key fetches exactly that issue and links it as a task")
    @MainActor
    func importIssueLinksTheIssue() async throws {
        defer { QuickAddURLProtocol.reset() }
        let suite = "jira-quickadd-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("jira-quickadd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let tasks = TaskStore(fileURL: dir.appendingPathComponent("t.sqlite"))

        let port = UInt16.random(in: 57001...65500)
        let session = QuickAddURLProtocol.session(handler: Self.quickAddHandler())
        let service = JiraService(defaults: defaults,
                                  store: FakeQuickAddKeychain().makeStore(defaults: defaults),
                                  oauthConfig: Self.testConfig,
                                  oauthSession: session,
                                  apiSession: session,
                                  callbackPort: port,
                                  openURL: { simulateQuickAddCallback(authorizeURL: $0, port: port) },
                                  taskStore: tasks,
                                  restoreOnInit: false)
        #expect(await service.connect())

        #expect(await service.importIssue(key: "shrgn-5"))

        let task = try #require(tasks.tasks.first { $0.jiraKey == "SHRGN-5" })
        #expect(task.title == "Quick-added issue")
        #expect(task.jiraIssueID == "10005")
        #expect(task.jiraSiteHost == "wayll.atlassian.net")

        // Exactly that one issue was asked for — not the whole assigned filter.
        let searches = QuickAddURLProtocol.requests.filter {
            $0.url?.path.hasSuffix("/search/jql") == true
        }
        let body = try #require(searches.last?.body).map { String(data: $0, encoding: .utf8) } ?? nil
        let jql = try #require(body)
        #expect(jql.contains("key = \\\"SHRGN-5\\\"") || jql.contains("key = \"SHRGN-5\""))
        #expect(!jql.contains("currentUser"))
    }

    @Test("a key that matches no issue reports failure and creates nothing")
    @MainActor
    func importIssueUnknownKeyFails() async throws {
        defer { QuickAddURLProtocol.reset() }
        let suite = "jira-quickadd-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("jira-quickadd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let tasks = TaskStore(fileURL: dir.appendingPathComponent("t.sqlite"))

        let port = UInt16.random(in: 57001...65500)
        let session = QuickAddURLProtocol.session(handler: Self.quickAddHandler(found: false))
        let service = JiraService(defaults: defaults,
                                  store: FakeQuickAddKeychain().makeStore(defaults: defaults),
                                  oauthConfig: Self.testConfig,
                                  oauthSession: session,
                                  apiSession: session,
                                  callbackPort: port,
                                  openURL: { simulateQuickAddCallback(authorizeURL: $0, port: port) },
                                  taskStore: tasks,
                                  restoreOnInit: false)
        #expect(await service.connect())

        #expect(await service.importIssue(key: "SHRGN-404") == false)
        #expect(tasks.tasks.isEmpty)
        // The request itself succeeded — the key simply matched nothing.
        #expect(service.lastSync?.imported == 0)
    }

    @Test("importing while disconnected fails without a request")
    @MainActor
    func importIssueDisconnectedFails() async throws {
        defer { QuickAddURLProtocol.reset() }
        let suite = "jira-quickadd-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let session = QuickAddURLProtocol.session(handler: Self.quickAddHandler())
        let service = JiraService(defaults: defaults,
                                  store: FakeQuickAddKeychain().makeStore(defaults: defaults),
                                  oauthConfig: Self.testConfig,
                                  oauthSession: session,
                                  apiSession: session,
                                  restoreOnInit: false)

        #expect(await service.importIssue(key: "SHRGN-5") == false)
        #expect(QuickAddURLProtocol.requests.isEmpty)
    }

    // MARK: - Fixtures

    static let testConfig = JiraOAuthConfig(clientID: "client-abc", clientSecret: "secret-xyz")

    static let tokenPayload = Data("""
    {"access_token":"at-1","expires_in":3600,"refresh_token":"rt-1",
     "scope":"read:jira-user read:jira-work write:jira-work offline_access","token_type":"Bearer"}
    """.utf8)

    /// The 3LO stub plus a `search/jql` endpoint that answers with one issue
    /// (or none, when `found` is false).
    static func quickAddHandler(found: Bool = true)
    -> @Sendable (URLRequest) throws -> (HTTPURLResponse, Data) {
        { request in
            switch request.url?.path {
            case "/oauth/token":
                return (try QuickAddURLProtocol.jsonResponse(for: request, status: 200), tokenPayload)
            case "/oauth/token/accessible-resources":
                return (try QuickAddURLProtocol.jsonResponse(for: request, status: 200), Data("""
                [{"id":"cloud-1","url":"https://wayll.atlassian.net","name":"Wayll",
                  "scopes":["read:jira-work"]}]
                """.utf8))
            case "/ex/jira/cloud-1/rest/api/3/myself":
                return (try QuickAddURLProtocol.jsonResponse(for: request, status: 200), Data("""
                {"accountId":"abc123","displayName":"Dev User","emailAddress":"dev@example.com","active":true}
                """.utf8))
            case "/ex/jira/cloud-1/rest/api/3/mypermissions":
                return (try QuickAddURLProtocol.jsonResponse(for: request, status: 200), Data("""
                {"permissions":{
                  "BROWSE_PROJECTS":{"id":"10","key":"BROWSE_PROJECTS","name":"Browse Projects","havePermission":true},
                  "CREATE_ISSUES":{"id":"11","key":"CREATE_ISSUES","name":"Create Issues","havePermission":true},
                  "WORK_ON_ISSUES":{"id":"12","key":"WORK_ON_ISSUES","name":"Work On Issues","havePermission":true}
                }}
                """.utf8))
            case "/ex/jira/cloud-1/rest/api/3/search/jql":
                guard found else {
                    return (try QuickAddURLProtocol.jsonResponse(for: request, status: 200),
                            Data(#"{"issues": []}"#.utf8))
                }
                return (try QuickAddURLProtocol.jsonResponse(for: request, status: 200), Data("""
                {"issues": [
                  {"id":"10005","key":"SHRGN-5","fields":{
                    "summary":"Quick-added issue","issuetype":{"name":"Task","subtask":false},
                    "status":{"name":"To Do","statusCategory":{"key":"new"}}}}
                ]}
                """.utf8))
            default:
                return (try QuickAddURLProtocol.response(for: request, status: 404), Data())
            }
        }
    }
}

// MARK: - Test doubles
//
// Deliberate copies of JiraIntegrationTests' doubles: those are file-private
// there, and the URLProtocol keeps global mutable state that two suites must
// not share.

private func simulateQuickAddCallback(authorizeURL: URL, port: UInt16, code: String = "auth-code-1") {
    let state = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)?
        .queryItems?.first { $0.name == "state" }?.value ?? ""
    let encoded = state.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? state
    guard let callback = URL(string: "http://localhost:\(port)/callback?code=\(code)&state=\(encoded)") else {
        return
    }
    Task.detached {
        let browser = URLSession(configuration: .ephemeral)
        for _ in 0..<60 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if (try? await browser.data(from: callback)) != nil { return }
        }
    }
}

private final class FakeQuickAddKeychain: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]

    func makeStore(defaults: UserDefaults) -> JiraTokenStore {
        JiraTokenStore(defaults: defaults,
                       keychainService: "test.service",
                       readToken: { [self] _, account in
                           lock.lock(); defer { lock.unlock() }
                           return storage[account]
                       },
                       writeToken: { [self] value, _, account in
                           lock.lock(); defer { lock.unlock() }
                           storage[account] = value
                       },
                       deleteToken: { [self] _, account in
                           lock.lock(); defer { lock.unlock() }
                           storage.removeValue(forKey: account)
                       })
    }
}

private struct QuickAddRequest: @unchecked Sendable {
    let request: URLRequest
    let body: Data?
    var url: URL? { request.url }
}

private final class QuickAddURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var _handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    private static var _requests: [QuickAddRequest] = []

    static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { lock.lock(); defer { lock.unlock() }; return _handler }
        set { lock.lock(); defer { lock.unlock() }; _handler = newValue }
    }

    static var requests: [QuickAddRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        _handler = nil
        _requests = []
    }

    static func response(for request: URLRequest,
                         status: Int,
                         headers: [String: String] = [:]) throws -> HTTPURLResponse {
        guard let url = request.url else { throw URLError(.badURL) }
        guard let response = HTTPURLResponse(url: url, statusCode: status,
                                             httpVersion: nil, headerFields: headers) else {
            throw URLError(.badServerResponse)
        }
        return response
    }

    static func jsonResponse(for request: URLRequest, status: Int) throws -> HTTPURLResponse {
        try response(for: request, status: status, headers: ["Content-Type": "application/json"])
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let drained = QuickAddRequest(request: request, body: request.bodyData)
        Self.lock.lock(); Self._requests.append(drained); Self.lock.unlock()

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

    static func session(handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) -> URLSession {
        reset()
        Self.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Self.self]
        return URLSession(configuration: configuration)
    }
}
