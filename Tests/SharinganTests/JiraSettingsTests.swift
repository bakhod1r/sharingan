import Foundation
import Testing
@testable import SharinganCore

// MARK: - Jira settings that change what gets queried

/// Covers the settings whose whole point is to alter a request Sharingan makes:
/// the custom JQL that replaces the built-in "assigned to me" filter.
///
/// Harness rules, honoured from JiraIntegrationTests: assertions inside the
/// stub's `startLoading()` run off the test's task and cannot fail a test — the
/// handler only builds responses, and the test body asserts on the recorded
/// requests after the `await`.
@Suite("Jira settings", .serialized)
@MainActor
struct JiraSettingsTests {

    private static let testConfig = JiraOAuthConfig(clientID: "client-1", clientSecret: "secret-1")

    /// A connected service pointed at the stub. Restores from a saved session
    /// rather than driving the browser flow — this suite is about what a sync
    /// *asks for*, not about how consent is obtained.
    private func makeConnectedService(defaults: UserDefaults,
                                      session: URLSession) async throws -> JiraService {
        let store = InMemoryTokens().makeStore(defaults: defaults)
        try store.save(JiraOAuthSession(accessToken: "at-1",
                                        refreshToken: "rt-1",
                                        expiresAt: Date().addingTimeInterval(3600),
                                        cloudID: "cloud-1",
                                        siteURL: "https://wayll.atlassian.net",
                                        scopes: ["read:jira-work", "offline_access"]))
        let service = JiraService(defaults: defaults,
                                  store: store,
                                  oauthConfig: Self.testConfig,
                                  oauthSession: session,
                                  apiSession: session,
                                  taskStore: TaskStore(fileURL: Self.throwawayStoreURL()),
                                  restoreOnInit: false)
        await service.restore()
        #expect(service.hasProjectAccess)
        return service
    }

    private static func throwawayStoreURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("jira-settings-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("t.sqlite")
    }

    private func sentJQL() throws -> String {
        let search = try #require(SettingsStub.requests.last { $0.url?.path.hasSuffix("/search/jql") == true })
        return try #require(search.jsonObject()["jql"] as? String)
    }

    private func withDefaults(_ body: (UserDefaults) async throws -> Void) async throws {
        let suite = "jira-settings-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        try await body(defaults)
    }

    // MARK: - Custom JQL

    @Test("a custom JQL replaces the built-in filter, even with a space selected")
    func customJQLReplacesDefault() async throws {
        defer { SettingsStub.reset() }
        try await withDefaults { defaults in
            let session = SettingsStub.session(handler: SettingsFixtures.handler())
            let service = try await makeConnectedService(defaults: defaults, session: session)
            // A selected space would normally decide the query — the custom JQL
            // is the user saying "no, ask exactly this".
            service.selectedProjectKey = "SHR"
            service.customJQL = "labels = urgent ORDER BY created DESC"

            await service.syncAssignedIssues()

            #expect(try sentJQL() == "labels = urgent ORDER BY created DESC")
            #expect(defaults.string(forKey: JiraService.customJQLDefaultsKey)
                    == "labels = urgent ORDER BY created DESC")
        }
    }

    @Test("a whitespace-only custom JQL is not a query — the default filter stands")
    func whitespaceCustomJQLFallsBackToDefault() async throws {
        defer { SettingsStub.reset() }
        try await withDefaults { defaults in
            let session = SettingsStub.session(handler: SettingsFixtures.handler())
            let service = try await makeConnectedService(defaults: defaults, session: session)
            service.customJQL = "   \n "

            await service.syncAssignedIssues()

            #expect(try sentJQL() == JiraService.assignedOpenJQL)
            // Blank is stored as "unset", so the field reads back empty rather
            // than as a cosmetic pile of spaces.
            #expect(service.customJQL.isEmpty)
        }
    }

    @Test("an explicit jql: argument beats the saved custom JQL")
    func explicitJQLBeatsCustomJQL() async throws {
        defer { SettingsStub.reset() }
        try await withDefaults { defaults in
            let session = SettingsStub.session(handler: SettingsFixtures.handler())
            let service = try await makeConnectedService(defaults: defaults, session: session)
            service.customJQL = "labels = urgent"

            await service.syncAssignedIssues(jql: "key = SHR-1")

            #expect(try sentJQL() == "key = SHR-1")
        }
    }

    @Test("with no custom JQL a selected space still scopes the default filter")
    func noCustomJQLKeepsProjectScoping() async throws {
        defer { SettingsStub.reset() }
        try await withDefaults { defaults in
            let session = SettingsStub.session(handler: SettingsFixtures.handler())
            let service = try await makeConnectedService(defaults: defaults, session: session)
            service.selectedProjectKey = "SHR"

            await service.syncAssignedIssues()

            #expect(try sentJQL() == JiraService.assignedOpenJQL(project: "SHR"))
        }
    }
}

// MARK: - Fixtures (nonisolated, so `@Sendable` handlers can build responses)

private enum SettingsFixtures {
    /// A connected account with browse access and an empty issue page — these
    /// tests are about the query that goes out, not what comes back.
    static func handler() -> @Sendable (URLRequest) throws -> (HTTPURLResponse, Data) {
        { request in
            let path = request.url?.path ?? ""
            let body: String
            switch true {
            case path.hasSuffix("/rest/api/3/myself"):
                body = #"{"accountId":"abc123","displayName":"Dev User","emailAddress":"dev@example.com","active":true}"#
            case path.hasSuffix("/rest/api/3/mypermissions"):
                body = """
                {"permissions":{
                  "BROWSE_PROJECTS":{"id":"10","key":"BROWSE_PROJECTS","name":"Browse Projects","havePermission":true},
                  "CREATE_ISSUES":{"id":"11","key":"CREATE_ISSUES","name":"Create Issues","havePermission":true},
                  "WORK_ON_ISSUES":{"id":"12","key":"WORK_ON_ISSUES","name":"Work On Issues","havePermission":true}
                }}
                """
            case path == "/oauth/token/accessible-resources":
                body = #"[{"id":"cloud-1","url":"https://wayll.atlassian.net","name":"Wayll","scopes":["read:jira-work"]}]"#
            case path.hasSuffix("/search/jql"):
                body = #"{"issues":[]}"#
            default:
                body = "{}"
            }
            return (try SettingsStub.json(request), Data(body.utf8))
        }
    }
}

// MARK: - Private stubs (disjoint from the other Jira suites' harnesses)

/// In-memory stand-in for the login keychain, so the suite never prompts and
/// never leaks a token between runs.
private final class InMemoryTokens: @unchecked Sendable {
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

/// One request as it reached the stub — recorded so the *test body* asserts on
/// it, never the off-task `startLoading()` callback.
private struct StubRequest: @unchecked Sendable {
    let request: URLRequest
    let body: Data?
    var url: URL? { request.url }
    func jsonObject() throws -> [String: Any] {
        let data = try #require(body, "request had no body")
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private final class SettingsStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var _handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    private static var _requests: [StubRequest] = []

    static var requests: [StubRequest] {
        lock.lock(); defer { lock.unlock() }; return _requests
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        _handler = nil; _requests = []
    }

    private static func record(_ recorded: StubRequest) {
        lock.lock(); defer { lock.unlock() }; _requests.append(recorded)
    }

    static func json(_ request: URLRequest, status: Int = 200) throws -> HTTPURLResponse {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                             headerFields: ["Content-Type": "application/json"]) else {
            throw URLError(.badServerResponse)
        }
        return response
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self._handler
        Self.lock.unlock()
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        // `httpBody` reads back nil inside a URLProtocol — drain the stream now,
        // it is single-pass.
        Self.record(StubRequest(request: request, body: request.bodyData))
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
        lock.lock(); _handler = handler; lock.unlock()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Self.self]
        return URLSession(configuration: configuration)
    }
}
