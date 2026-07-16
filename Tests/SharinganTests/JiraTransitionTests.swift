import Foundation
import Testing
@testable import SharinganCore

// Moving an issue's status from Sharingan — the "shift the card on the board
// without opening Jira" ask. Transitions are interactive: they go straight to
// Jira (not the queue), and on success the cache and the linked task's title
// stay accurate so the row's chip updates.
@Suite("Jira transitions", .serialized)
struct JiraTransitionTests {

    @MainActor
    private func makeService(_ handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data))
    throws -> (JiraService, JiraStorage, TaskStore) {
        let suite = "jira-transition-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("jira-transition-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storage = try #require(JiraStorage(path: dir.appendingPathComponent("t.sqlite").path))
        let tasks = TaskStore(fileURL: dir.appendingPathComponent("tasks.sqlite"))

        // Seed a live (non-expired) session so the client vends a token without
        // touching the network — the transition calls actually reach the stub.
        defaults.set(Date().addingTimeInterval(3600).timeIntervalSince1970,
                     forKey: JiraTokenStore.expiresAtDefaultsKey)
        defaults.set("test-cloud", forKey: JiraTokenStore.cloudIDDefaultsKey)
        defaults.set("https://wayll.atlassian.net", forKey: JiraTokenStore.siteURLDefaultsKey)
        defaults.set(["read:jira-work"], forKey: JiraTokenStore.scopesDefaultsKey)
        let store = JiraTokenStore(defaults: defaults,
                                   readToken: { _, account in
                                       account == JiraTokenStore.accessTokenAccount ? "acc" : "ref"
                                   },
                                   writeToken: { _, _, _ in },
                                   deleteToken: { _, _ in })

        TransitionStubProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TransitionStubProtocol.self]
        let session = URLSession(configuration: config)
        let service = JiraService(defaults: defaults,
                                  store: store,
                                  oauthConfig: nil, oauthSession: session, apiSession: session,
                                  issueCache: storage, taskStore: tasks, restoreOnInit: false)
        return (service, storage, tasks)
    }

    @Test("transitions are fetched for the issue")
    @MainActor
    func fetchesTransitions() async throws {
        defer { TransitionStubProtocol.handler = nil }
        let (service, _, _) = try makeService { request in
            let json = Data("""
            { "transitions": [
                { "id": "31", "name": "Code review", "hasScreen": false,
                  "to": { "id": "10002", "name": "Code review",
                          "statusCategory": { "key": "indeterminate" } } }
            ] }
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!, json)
        }
        let transitions = await service.transitions(forIssueKey: "WT-689")
        #expect(transitions.map(\.name) == ["Code review"])
    }

    @Test("applying a transition succeeds and updates the cached status")
    @MainActor
    func applyUpdatesCache() async throws {
        defer { TransitionStubProtocol.handler = nil }
        let (service, storage, _) = try makeService { request in
            let status = request.httpMethod == "POST" ? 204 : 200
            return (HTTPURLResponse(url: request.url!, statusCode: status,
                                    httpVersion: nil, headerFields: nil)!, Data())
        }
        storage.upsertIssue(CachedJiraIssue(issueID: "1", issueKey: "WT-689",
                                            siteHost: "wayll.atlassian.net", summary: "T",
                                            statusName: "In Progress",
                                            statusCategory: "indeterminate"))

        let ok = await service.applyTransition(
            issueKey: "WT-689",
            transition: JiraTransition(id: "31", name: "Code review",
                                       to: JiraStatus(id: "10002", name: "Code review",
                                                      statusCategory: JiraStatusCategory(
                                                        key: "indeterminate", name: "", colorName: nil))))
        #expect(ok)
        #expect(storage.issue(id: "1")?.statusName == "Code review")
    }

    @Test("a failed transition reports failure and leaves the cache untouched")
    @MainActor
    func failureLeavesCache() async throws {
        defer { TransitionStubProtocol.handler = nil }
        let (service, storage, _) = try makeService { request in
            (HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil,
                             headerFields: nil)!, Data(#"{"errorMessages":["Nope"]}"#.utf8))
        }
        storage.upsertIssue(CachedJiraIssue(issueID: "1", issueKey: "WT-689",
                                            siteHost: "wayll.atlassian.net", summary: "T",
                                            statusName: "In Progress",
                                            statusCategory: "indeterminate"))
        let ok = await service.applyTransition(
            issueKey: "WT-689",
            transition: JiraTransition(id: "31", name: "X",
                                       to: JiraStatus(name: "Y", statusCategory: JiraStatusCategory(
                                        key: "done", name: "", colorName: nil))))
        #expect(!ok)
        #expect(storage.issue(id: "1")?.statusName == "In Progress")
    }
}

private final class TransitionStubProtocol: URLProtocol, @unchecked Sendable {
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
