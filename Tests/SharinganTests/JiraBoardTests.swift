import Foundation
import Testing
@testable import SharinganCore

// MARK: - JiraBoardModel

/// Drives `JiraBoardModel` against a stubbed `URLSession`. The model is the mini
/// sprint board: it loads the active sprint's cards (mine only), maps each to a
/// column by *status id*, and turns a drag into a Jira transition.
///
/// Harness rules, honoured from JiraIntegrationTests: assertions inside the
/// stub's `startLoading()` run off the test's task and file as `«unknown»` —
/// they cannot fail a test. So the handler only *builds* responses; every
/// request is recorded and asserted in the test body, after the `await`.
@Suite("Jira board", .serialized)
@MainActor
struct JiraBoardTests {

    private typealias Fx = BoardFixtures

    private func makeModel(session: URLSession, siteHost: String = "wayll.atlassian.net") -> JiraBoardModel {
        JiraBoardModel(client: JiraClient(tokens: StubBoardTokens(), session: session),
                       siteHost: siteHost)
    }

    // MARK: - Load & column mapping

    @Test("cards map to columns by status id; an unmapped status lands in Other")
    func mapsByStatusIdWithOtherFallback() async throws {
        defer { TestStub.reset() }
        let session = TestStub.session(handler: Fx.boardHandler())
        let model = makeModel(session: session)

        await model.load(projectKey: "SHR")

        #expect(model.phase == .loaded)
        #expect(model.sprintName == "Sprint 7")
        #expect(model.columns.map(\.name) == ["To Do", "In Progress", "Done", "Other"])
        #expect(model.columns[0].cards.map(\.key) == ["SHR-1"])
        #expect(model.columns[1].cards.map(\.key) == ["SHR-2"])   // matched on the 2nd status id
        #expect(model.columns[2].cards.isEmpty)
        let other = try #require(model.columns.first { $0.isOther })
        #expect(other.cards.map(\.key) == ["SHR-9"])              // status 99 → Other, not vanished

        // A card carries what the UI draws.
        let card = try #require(model.columns[0].cards.first)
        #expect(card.summary == "SHR-1 summary")
        #expect(card.priorityName == "High")
        #expect(card.estimateSeconds == 7200)
        #expect(card.issueType == "Task")
    }

    @Test("no Other column appears when every card maps")
    func noOtherColumnWhenAllMapped() async throws {
        defer { TestStub.reset() }
        let session = TestStub.session { request in
            let path = request.url?.path ?? ""
            let body: String
            if path.hasSuffix("/rest/agile/1.0/board") { body = Fx.boardListJSON([(1, "b")]) }
            else if path.hasSuffix("/configuration") { body = Fx.configJSON }
            else if path.hasSuffix("/sprint") { body = Fx.activeSprintJSON }
            else if path.hasSuffix("/search/jql") {
                body = Fx.searchJSON([Fx.issueJSON(key: "SHR-1", id: "1", statusId: "10")])
            } else { body = "{}" }
            return (try TestStub.json(request), Data(body.utf8))
        }
        let model = makeModel(session: session)

        await model.load(projectKey: "SHR")

        #expect(model.columns.map(\.name) == ["To Do", "In Progress", "Done"])
        #expect(!model.columns.contains { $0.isOther })
    }

    // MARK: - Board selection

    @Test("getBoards is filtered by projectKeyOrId, and a single board auto-selects")
    func singleBoardAutoSelectsAndFilters() async throws {
        defer { TestStub.reset() }
        let session = TestStub.session(handler: Fx.boardHandler())
        let model = makeModel(session: session)

        await model.load(projectKey: "SHR")

        let boardReq = try #require(TestStub.requests.first { $0.url?.path.hasSuffix("/rest/agile/1.0/board") == true })
        #expect(boardReq.url?.query?.contains("projectKeyOrId=SHR") == true)
        #expect(model.phase == .loaded)
        #expect(model.availableBoards.isEmpty)   // nothing to pick — it chose
    }

    @Test("multiple boards are surfaced for a picker instead of guessing")
    func multipleBoardsSurfaced() async throws {
        defer { TestStub.reset() }
        let session = TestStub.session { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/rest/agile/1.0/board") {
                return (try TestStub.json(request), Data(Fx.boardListJSON([(1, "Alpha"), (2, "Beta")]).utf8))
            }
            return (try TestStub.json(request), Data("{}".utf8))
        }
        let model = makeModel(session: session)

        await model.load(projectKey: "SHR")

        #expect(model.phase == .chooseBoard)
        #expect(model.availableBoards.map(\.name) == ["Alpha", "Beta"])
        #expect(model.columns.isEmpty)
        // No configuration/sprint call was made — it stopped to ask.
        #expect(!TestStub.requests.contains { $0.url?.path.hasSuffix("/configuration") == true })

        // Choosing one drives the rest of the load.
        TestStub.setHandler(Fx.boardHandler())
        await model.selectBoard(try #require(model.availableBoards.first))
        #expect(model.phase == .loaded)
        #expect(model.columns.first?.name == "To Do")
    }

    // MARK: - No-active-sprint fallback

    @Test("with no active sprint the query falls back to the whole project")
    func noActiveSprintFallsBackToProject() async throws {
        defer { TestStub.reset() }
        let session = TestStub.session { request in
            let path = request.url?.path ?? ""
            let body: String
            if path.hasSuffix("/rest/agile/1.0/board") { body = Fx.boardListJSON([(1, "b")]) }
            else if path.hasSuffix("/configuration") { body = Fx.configJSON }
            else if path.hasSuffix("/sprint") { body = Fx.noSprintJSON }   // kanban / no sprint
            else if path.hasSuffix("/search/jql") {
                body = Fx.searchJSON([Fx.issueJSON(key: "SHR-1", id: "1", statusId: "10")])
            } else { body = "{}" }
            return (try TestStub.json(request), Data(body.utf8))
        }
        let model = makeModel(session: session)

        await model.load(projectKey: "SHR")

        #expect(model.phase == .loaded)
        #expect(model.sprintName == nil)
        let search = try #require(TestStub.requests.first { $0.url?.path.hasSuffix("/search/jql") == true })
        let jql = try #require((search.jsonObject()["jql"] as? String))
        #expect(jql.contains("project = \"SHR\""))
        #expect(jql.contains("assignee = currentUser()"))
        #expect(!jql.contains("sprint ="))
    }

    @Test("an active sprint queries by sprint id and includes Done")
    func activeSprintQueriesBySprintId() async throws {
        defer { TestStub.reset() }
        let session = TestStub.session(handler: Fx.boardHandler())
        let model = makeModel(session: session)

        await model.load(projectKey: "SHR")

        let search = try #require(TestStub.requests.first { $0.url?.path.hasSuffix("/search/jql") == true })
        let jql = try #require((search.jsonObject()["jql"] as? String))
        #expect(jql.contains("sprint = 42"))
        #expect(jql.contains("assignee = currentUser()"))
    }

    // MARK: - Drag = transition

    @Test("dragging a card picks the transition landing in the target column and posts it")
    func moveSelectsTransitionByTargetStatus() async throws {
        defer { TestStub.reset() }
        // Two transitions; only #22 lands on a status (20) inside "In Progress".
        let transitions = #"""
        {"transitions":[
          {"id":"11","name":"Reopen","to":{"name":"To Do","statusCategory":{"key":"new"}},"hasScreen":false},
          {"id":"22","name":"Start","to":{"id":"20","name":"In Progress","statusCategory":{"key":"indeterminate"}},"hasScreen":false}
        ]}
        """#
        let session = TestStub.session(handler: BoardFixtures.moveHandler(transitionsJSON: transitions))
        let model = makeModel(session: session)
        await model.load(projectKey: "SHR")
        #expect(model.columns[0].cards.map(\.key) == ["SHR-1"])

        await model.move(issueKey: "SHR-1", toColumnID: model.columns[1].id)

        // Card moved To Do → In Progress and stuck.
        #expect(model.columns[0].cards.isEmpty)
        #expect(model.columns[1].cards.map(\.key) == ["SHR-1"])
        #expect(model.errorMessage == nil)
        // The chosen transition id was posted.
        let post = try #require(TestStub.requests.last { $0.url?.path.hasSuffix("/transitions") == true && $0.method == "POST" })
        let transition = try #require(post.jsonObject()["transition"] as? [String: Any])
        #expect(transition["id"] as? String == "22")
    }

    @Test("a transition needing a field screen is refused and the card snaps back")
    func moveRefusesHasScreenTransition() async throws {
        defer { TestStub.reset() }
        let transitions = #"""
        {"transitions":[
          {"id":"22","name":"Start","to":{"id":"20","name":"In Progress","statusCategory":{"key":"indeterminate"}},"hasScreen":true}
        ]}
        """#
        let session = TestStub.session(handler: BoardFixtures.moveHandler(transitionsJSON: transitions))
        let model = makeModel(session: session)
        await model.load(projectKey: "SHR")

        await model.move(issueKey: "SHR-1", toColumnID: model.columns[1].id)

        // Snapped back.
        #expect(model.columns[0].cards.map(\.key) == ["SHR-1"])
        #expect(model.columns[1].cards.isEmpty)
        let message = try #require(model.errorMessage)
        #expect(message.localizedCaseInsensitiveContains("Jira"))
        // We never POSTed a transition we can't complete.
        #expect(!TestStub.requests.contains { $0.url?.path.hasSuffix("/transitions") == true && $0.method == "POST" })
    }

    @Test("no transition into the target column snaps the card back")
    func moveWithNoMatchingTransitionSnapsBack() async throws {
        defer { TestStub.reset() }
        // Only a transition to status 10 (To Do) — nothing reaches In Progress.
        let transitions = #"""
        {"transitions":[
          {"id":"11","name":"Reopen","to":{"id":"10","name":"To Do","statusCategory":{"key":"new"}},"hasScreen":false}
        ]}
        """#
        let session = TestStub.session(handler: BoardFixtures.moveHandler(transitionsJSON: transitions))
        let model = makeModel(session: session)
        await model.load(projectKey: "SHR")

        await model.move(issueKey: "SHR-1", toColumnID: model.columns[1].id)

        #expect(model.columns[0].cards.map(\.key) == ["SHR-1"])
        #expect(model.columns[1].cards.isEmpty)
        #expect(model.errorMessage != nil)
        #expect(!TestStub.requests.contains { $0.url?.path.hasSuffix("/transitions") == true && $0.method == "POST" })
    }

    @Test("a failed transition POST snaps the card back and reports the error")
    func moveSnapsBackOnTransitionFailure() async throws {
        defer { TestStub.reset() }
        let transitions = #"""
        {"transitions":[
          {"id":"22","name":"Start","to":{"id":"20","name":"In Progress","statusCategory":{"key":"indeterminate"}},"hasScreen":false}
        ]}
        """#
        let session = TestStub.session(handler: BoardFixtures.moveHandler(transitionsJSON: transitions, transitionStatus: 500))
        let model = makeModel(session: session)
        await model.load(projectKey: "SHR")

        await model.move(issueKey: "SHR-1", toColumnID: model.columns[1].id)

        #expect(model.columns[0].cards.map(\.key) == ["SHR-1"])
        #expect(model.columns[1].cards.isEmpty)
        #expect(model.errorMessage != nil)
    }
}

// MARK: - Fixtures (nonisolated, so `@Sendable` handlers can build responses)

/// JSON bodies and canned handlers for the board tests. A plain enum namespace,
/// deliberately *not* nested in the `@MainActor` suite — the stub's handler runs
/// off the main actor and must be able to call these synchronously.
private enum BoardFixtures {
    // A three-column workflow with real status ids, matching the user's custom
    // flow shape (never keyed by name).
    static let configJSON = """
    {
      "columnConfig": {
        "columns": [
          { "name": "To Do",       "statuses": [{ "id": "10" }] },
          { "name": "In Progress", "statuses": [{ "id": "20" }, { "id": "21" }] },
          { "name": "Done",        "statuses": [{ "id": "30" }] }
        ]
      }
    }
    """

    static func boardListJSON(_ boards: [(Int, String)]) -> String {
        let values = boards.map { id, name in
            #"{"id":\#(id),"name":"\#(name)","type":"scrum","location":{"projectKey":"SHR","projectId":100}}"#
        }.joined(separator: ",")
        return #"{"values":[\#(values)],"startAt":0,"maxResults":50,"total":\#(boards.count),"isLast":true}"#
    }

    static let activeSprintJSON = #"""
    {"values":[{"id":42,"name":"Sprint 7","state":"active","startDate":null,"endDate":null,"completeDate":null,"originBoardId":1}],"startAt":0,"maxResults":50,"total":1,"isLast":true}
    """#

    static let noSprintJSON = #"{"values":[],"startAt":0,"maxResults":50,"total":0,"isLast":true}"#

    /// One issue with the given status id/category, for a search page.
    static func issueJSON(key: String, id: String, statusId: String,
                          category: String = "indeterminate") -> String {
        #"""
        {"id":"\#(id)","key":"\#(key)","fields":{"summary":"\#(key) summary","status":{"id":"\#(statusId)","name":"S\#(statusId)","statusCategory":{"key":"\#(category)"}},"priority":{"id":"3","name":"High"},"issuetype":{"name":"Task"},"timeoriginalestimate":7200}}
        """#
    }

    static func searchJSON(_ issues: [String]) -> String {
        #"{"issues":[\#(issues.joined(separator: ","))]}"#
    }

    /// The default happy-path handler: one board, active sprint, three cards —
    /// one To Do (10), one In Progress (21, the second id of that column), and
    /// one whose status (99) maps to no column, so it must land in "Other".
    static func boardHandler() -> @Sendable (URLRequest) throws -> (HTTPURLResponse, Data) {
        { request in
            let path = request.url?.path ?? ""
            let body: String
            switch true {
            case path.hasSuffix("/rest/agile/1.0/board"):
                body = boardListJSON([(1, "SHR board")])
            case path.hasSuffix("/configuration"):
                body = configJSON
            case path.hasSuffix("/sprint"):
                body = activeSprintJSON
            case path.hasSuffix("/search/jql"):
                body = searchJSON([
                    issueJSON(key: "SHR-1", id: "1", statusId: "10", category: "new"),
                    issueJSON(key: "SHR-2", id: "2", statusId: "21"),
                    issueJSON(key: "SHR-9", id: "9", statusId: "99")
                ])
            default:
                body = "{}"
            }
            return (try TestStub.json(request), Data(body.utf8))
        }
    }

    /// Loads a single-board active sprint with one To Do card, then answers
    /// transitions (GET) and doTransition (POST).
    static func moveHandler(transitionsJSON: String,
                            transitionStatus: Int = 204) -> @Sendable (URLRequest) throws -> (HTTPURLResponse, Data) {
        { request in
            let path = request.url?.path ?? ""
            let method = request.httpMethod ?? "GET"
            if path.hasSuffix("/rest/agile/1.0/board") { return (try TestStub.json(request), Data(boardListJSON([(1, "b")]).utf8)) }
            if path.hasSuffix("/configuration") { return (try TestStub.json(request), Data(configJSON.utf8)) }
            if path.hasSuffix("/sprint") { return (try TestStub.json(request), Data(activeSprintJSON.utf8)) }
            if path.hasSuffix("/search/jql") {
                return (try TestStub.json(request), Data(searchJSON([
                    issueJSON(key: "SHR-1", id: "1", statusId: "10", category: "new")
                ]).utf8))
            }
            if path.hasSuffix("/transitions") && method == "GET" {
                return (try TestStub.json(request), Data(transitionsJSON.utf8))
            }
            if path.hasSuffix("/transitions") && method == "POST" {
                return (try TestStub.response(request, status: transitionStatus), Data())
            }
            return (try TestStub.json(request), Data("{}".utf8))
        }
    }
}

// MARK: - Private stubs (disjoint from JiraIntegrationTests' own harness)

/// A `JiraTokenProviding` that hands back a constant bearer/cloudId. The board
/// model never touches auth, so nothing here needs to vary.
private struct StubBoardTokens: JiraTokenProviding {
    var token = "at-board"
    var cloud = "cloud-1"
    func accessToken() async throws -> String { token }
    func cloudID() async throws -> String { cloud }
}

/// One request as it reached the stub — recorded so the *test body* asserts on
/// it, never the off-task `startLoading()` callback (whose `#expect`s would file
/// as `«unknown»` and silently pass).
private struct StubRequest: @unchecked Sendable {
    let request: URLRequest
    let body: Data?
    var method: String? { request.httpMethod }
    var url: URL? { request.url }
    func header(_ name: String) -> String? { request.value(forHTTPHeaderField: name) }
    func jsonObject() throws -> [String: Any] {
        let data = try #require(body, "request had no body")
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

/// A private `URLProtocol` stub, separate from JiraIntegrationTests' copy so the
/// two suites never share mutable state. Serialized suite + `reset()` keeps the
/// static log per-test.
private final class TestStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var _handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    private static var _requests: [StubRequest] = []

    static var requests: [StubRequest] {
        lock.lock(); defer { lock.unlock() }; return _requests
    }

    static func setHandler(_ handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) {
        lock.lock(); defer { lock.unlock() }; _handler = handler
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        _handler = nil; _requests = []
    }

    private static func record(_ recorded: StubRequest) {
        lock.lock(); defer { lock.unlock() }; _requests.append(recorded)
    }

    static func response(_ request: URLRequest, status: Int, headers: [String: String] = [:]) throws -> HTTPURLResponse {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers) else {
            throw URLError(.badServerResponse)
        }
        return response
    }

    static func json(_ request: URLRequest, status: Int = 200) throws -> HTTPURLResponse {
        try response(request, status: status, headers: ["Content-Type": "application/json"])
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
        // Drain the body stream now — it is single-pass, and URLSession has moved
        // httpBody into httpBodyStream before a URLProtocol ever sees it.
        Self.record(StubRequest(request: request, body: request.drainedBody))
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
        setHandler(handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Self.self]
        return URLSession(configuration: configuration)
    }
}

private extension URLRequest {
    /// The body as a `URLProtocol` sees it: `httpBody` is nil by then, moved into
    /// `httpBodyStream`, so drain the stream.
    var drainedBody: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data()
        let size = 4096
        var buffer = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
