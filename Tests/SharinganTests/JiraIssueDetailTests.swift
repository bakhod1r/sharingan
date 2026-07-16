import Foundation
import Testing
@testable import SharinganCore

/// Tests for `JiraIssueDetailModel` — the read-everything-without-opening-Jira
/// surface.
///
/// Harness rules inherited from `JiraIntegrationTests` (worth restating, because
/// breaking them produces a *green* run that proves nothing):
/// * The stub handler runs on URLSession's queue, off the test's task. An
///   `#expect` there is orphaned onto `Test «unknown»` and cannot fail anything.
///   Handlers only build responses; every assertion lives in the test body,
///   against `DetailStub.requests`.
/// * `URLRequest.bodyData` drains `httpBodyStream` — URLSession has already moved
///   `httpBody` there by the time a `URLProtocol` sees the request.
///
/// The stub/helpers below are deliberately this file's own (`private`), not
/// shared with `JiraIntegrationTests`.
@Suite("Jira issue detail", .serialized)
@MainActor
struct JiraIssueDetailTests {

    // MARK: - load()

    @Test("load() populates details, comments, history and worklogs")
    func loadPopulatesEverySection() async throws {
        defer { DetailStub.reset() }
        let session = DetailStub.session { request in
            try DetailStub.route(request, routes: DetailFixtures.happyRoutes)
        }
        let model = makeModel(session: session)

        await model.load()

        #expect(model.details.value?.key == "SHR-1")
        #expect(model.summaryText == "Ship the detail sheet")
        #expect(model.descriptionText == "Everything visible without opening Jira.")
        #expect(model.statusName == "In Progress")
        #expect(model.issueTypeName == "Story")

        #expect(model.comments.value?.count == 2)
        #expect(model.history.value?.count == 1)
        #expect(model.worklogs.value?.count == 1)
        #expect(model.worklogs.value?.first?.timeSpent == "1h 30m")

        // Nothing half-loaded, nothing failed.
        #expect(model.details.errorMessage == nil)
        #expect(model.comments.errorMessage == nil)
        #expect(model.history.errorMessage == nil)
        #expect(model.worklogs.errorMessage == nil)
        #expect(model.isLoading == false)

        // All four sections fetched, and against the linked key.
        let paths = DetailStub.requests.compactMap(\.url?.path)
        #expect(paths.contains("/ex/jira/cloud-1/rest/api/3/issue/SHR-1"))
        #expect(paths.contains("/ex/jira/cloud-1/rest/api/3/issue/SHR-1/comment"))
        #expect(paths.contains("/ex/jira/cloud-1/rest/api/3/issue/SHR-1/changelog"))
        #expect(paths.contains("/ex/jira/cloud-1/rest/api/3/issue/SHR-1/worklog"))
    }

    @Test("the browse URL is built from the site host and the key")
    func browseURLFromSiteHost() {
        let model = makeModel(session: DetailStub.session { request in
            (try DetailStub.jsonResponse(for: request, status: 200), Data("{}".utf8))
        })
        defer { DetailStub.reset() }

        #expect(model.browseURL?.absoluteString == "https://acme.atlassian.net/browse/SHR-1")
    }

    @Test("a site host stored with a scheme still yields one clean browse URL")
    func browseURLNormalizesSiteHost() {
        // JiraService stores a bare host, but the accessible resource it comes
        // from is a URL — a caller handing over "https://acme.atlassian.net/"
        // must not produce https://https://acme.atlassian.net//browse/SHR-1.
        let session = DetailStub.session { request in
            (try DetailStub.jsonResponse(for: request, status: 200), Data("{}".utf8))
        }
        defer { DetailStub.reset() }
        let model = JiraIssueDetailModel(client: DetailStub.client(session: session),
                                         issueKey: "SHR-1",
                                         siteHost: "https://acme.atlassian.net/")

        #expect(model.browseURL?.absoluteString == "https://acme.atlassian.net/browse/SHR-1")
    }

    // MARK: - ADF rendering

    @Test("a comment with a mention and a bullet list renders as readable text")
    func commentRendersMentionAndBulletList() async throws {
        defer { DetailStub.reset() }
        let session = DetailStub.session { request in
            try DetailStub.route(request, routes: DetailFixtures.happyRoutes)
        }
        let model = makeModel(session: session)

        await model.load()

        let comments = try #require(model.comments.value)
        #expect(comments.first?.plainTextBody == "@Bakhodir please review\n- Details tab\n- History tab")
        #expect(comments.first?.author.displayName == "Bakhodir")
        #expect(comments.last?.plainTextBody == "Done — shipping it.")
    }

    // MARK: - History

    @Test("a changelog entry maps field, from → to, author and date")
    func changelogEntryMapsFields() async throws {
        defer { DetailStub.reset() }
        let session = DetailStub.session { request in
            try DetailStub.route(request, routes: DetailFixtures.happyRoutes)
        }
        let model = makeModel(session: session)

        await model.load()

        let entries = try #require(model.history.value)
        // The second fixture history carries no items — a group Jira kept for its
        // own bookkeeping. It is noise, not history, and must not render as a row.
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.field == "status")
        #expect(entry.from == "To Do")
        #expect(entry.to == "In Progress")
        #expect(entry.authorName == "Bakhodir")
        #expect(entry.date == ISO8601DateFormatter().date(from: "2026-07-14T09:00:00Z"))
    }

    @Test("a changelog entry whose previous value is empty reads as no value, not empty string")
    func changelogEmptyStringBecomesNil() async throws {
        defer { DetailStub.reset() }
        var routes = DetailFixtures.happyRoutes
        routes["/changelog"] = DetailFixtures.changelogAssigneeSetJSON
        let frozenRoutes = routes
        let session = DetailStub.session { request in
            try DetailStub.route(request, routes: frozenRoutes)
        }
        let model = makeModel(session: session)

        await model.load()

        let entry = try #require(model.history.value?.first)
        #expect(entry.field == "assignee")
        // Jira sends "" for "was unset". Rendering that verbatim is a blank gap.
        #expect(entry.from == nil)
        #expect(entry.to == "Bakhodir")
    }

    // MARK: - Empty vs. broken

    @Test("an empty section loads empty; a failed section carries an error instead")
    func emptySectionIsNotAFailedSection() async throws {
        defer { DetailStub.reset() }
        var routes = DetailFixtures.happyRoutes
        routes["/comment"] = nil          // 500s below
        routes["/worklog"] = DetailFixtures.emptyWorklogJSON
        let frozenRoutes = routes
        let session = DetailStub.session { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/comment") {
                return (try DetailStub.jsonResponse(for: request, status: 500), Data("{}".utf8))
            }
            return try DetailStub.route(request, routes: frozenRoutes)
        }
        let model = makeModel(session: session)

        await model.load()

        // Empty: loaded, no rows, no error. The UI says "No worklogs yet".
        #expect(model.worklogs.value?.isEmpty == true)
        #expect(model.worklogs.errorMessage == nil)
        #expect(model.worklogs.isFailed == false)

        // Broken: no value at all, and a reason. The UI must not say "no comments".
        #expect(model.comments.value == nil)
        #expect(model.comments.isFailed == true)
        #expect(model.comments.errorMessage == JiraError.server(status: 500).userMessage)

        // One section failing must not take the others down with it.
        #expect(model.details.value?.key == "SHR-1")
        #expect(model.history.value?.count == 1)
    }

    @Test("a failed issue fetch surfaces Jira's own reason")
    func failedIssueFetchSurfacesReason() async {
        defer { DetailStub.reset() }
        let session = DetailStub.session { request in
            (try DetailStub.jsonResponse(for: request, status: 404), Data("{}".utf8))
        }
        let model = makeModel(session: session)

        await model.load()

        #expect(model.details.isFailed == true)
        #expect(model.details.errorMessage == JiraError.notFound.userMessage)
        #expect(model.summaryText == "SHR-1")   // falls back to the key, never blank
    }

    // MARK: - addComment

    @Test("addComment posts an ADF doc and the new comment appears")
    func addCommentPostsADFAndRefreshes() async throws {
        defer { DetailStub.reset() }
        let session = DetailStub.session { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/comment"), request.httpMethod == "POST" {
                return (try DetailStub.jsonResponse(for: request, status: 201),
                        Data(DetailFixtures.createdCommentJSON.utf8))
            }
            if path.hasSuffix("/comment") {
                // The refresh after the POST sees three comments, not two.
                let body = DetailStub.requests.contains { $0.method == "POST" }
                    ? DetailFixtures.commentsAfterPostJSON
                    : DetailFixtures.commentsJSON
                return (try DetailStub.jsonResponse(for: request, status: 200), Data(body.utf8))
            }
            return try DetailStub.route(request, routes: DetailFixtures.happyRoutes)
        }
        let model = makeModel(session: session)
        await model.load()
        #expect(model.comments.value?.count == 2)
        DetailStub.clearRequests()

        await model.addComment("Looks good to me")

        let posted = try #require(DetailStub.requests.first { $0.method == "POST" })
        #expect(posted.url?.path == "/ex/jira/cloud-1/rest/api/3/issue/SHR-1/comment")
        let json = try posted.jsonObject()
        let body = try #require(json["body"] as? [String: Any], "comment body must be an ADF doc")
        #expect(body["type"] as? String == "doc")
        #expect(body["version"] as? Int == 1)
        let content = try #require(body["content"] as? [[String: Any]])
        #expect(content.first?["type"] as? String == "paragraph")
        let text = try #require(content.first?["content"] as? [[String: Any]])
        #expect(text.first?["text"] as? String == "Looks good to me")

        // Posting is not enough — the list has to show it.
        #expect(model.comments.value?.count == 3)
        #expect(model.comments.value?.last?.plainTextBody == "Looks good to me")
        #expect(model.isPostingComment == false)
        #expect(model.actionErrorMessage == nil)
    }

    @Test("addComment ignores blank text without touching the network")
    func addCommentIgnoresBlankText() async throws {
        defer { DetailStub.reset() }
        let session = DetailStub.session { request in
            try DetailStub.route(request, routes: DetailFixtures.happyRoutes)
        }
        let model = makeModel(session: session)
        await model.load()
        DetailStub.clearRequests()

        await model.addComment("   \n  ")

        #expect(DetailStub.requests.isEmpty)
    }

    @Test("a rejected comment reports why and leaves the list intact")
    func addCommentFailureSurfacesError() async throws {
        defer { DetailStub.reset() }
        let session = DetailStub.session { request in
            if request.httpMethod == "POST" {
                return (try DetailStub.jsonResponse(for: request, status: 403), Data("{}".utf8))
            }
            return try DetailStub.route(request, routes: DetailFixtures.happyRoutes)
        }
        let model = makeModel(session: session)
        await model.load()

        await model.addComment("Nope")

        #expect(model.actionErrorMessage == JiraError.forbidden.userMessage)
        // The failure belongs to the action, not the section — the comments we
        // already read are still good.
        #expect(model.comments.value?.count == 2)
        #expect(model.comments.isFailed == false)
        #expect(model.isPostingComment == false)
    }

    // MARK: - saveDescription

    @Test("saveDescription sends plain-text ADF through updateIssue")
    func saveDescriptionSendsPlainTextADF() async throws {
        defer { DetailStub.reset() }
        let session = DetailStub.session { request in
            let path = request.url?.path ?? ""
            if request.httpMethod == "PUT" {
                return (try DetailStub.jsonResponse(for: request, status: 204), Data())
            }
            if path == "/ex/jira/cloud-1/rest/api/3/issue/SHR-1" {
                // The re-read after the PUT reflects what was saved.
                let body = DetailStub.requests.contains { $0.method == "PUT" }
                    ? DetailFixtures.issueAfterSaveJSON
                    : DetailFixtures.issueJSON
                return (try DetailStub.jsonResponse(for: request, status: 200), Data(body.utf8))
            }
            return try DetailStub.route(request, routes: DetailFixtures.happyRoutes)
        }
        let model = makeModel(session: session)
        await model.load()
        DetailStub.clearRequests()

        await model.saveDescription("Rewritten\nfrom Sharingan")

        let put = try #require(DetailStub.requests.first { $0.method == "PUT" })
        #expect(put.url?.path == "/ex/jira/cloud-1/rest/api/3/issue/SHR-1")
        let fields = try #require(try put.jsonObject()["fields"] as? [String: Any])
        let description = try #require(fields["description"] as? [String: Any])
        #expect(description["type"] as? String == "doc")
        #expect(description["version"] as? Int == 1)
        let paragraphs = try #require(description["content"] as? [[String: Any]])
        #expect(paragraphs.count == 2)   // one paragraph per line
        #expect(((paragraphs[0]["content"] as? [[String: Any]])?.first?["text"] as? String) == "Rewritten")
        #expect(((paragraphs[1]["content"] as? [[String: Any]])?.first?["text"] as? String) == "from Sharingan")

        // Only the description travels. A nil summary here must stay off the wire
        // — sending it would blank the issue's summary in Jira.
        #expect(fields["summary"] == nil)
        #expect(fields.keys.sorted() == ["description"])

        #expect(model.descriptionText == "Rewritten\nfrom Sharingan")
        #expect(model.isSavingDescription == false)
        #expect(model.actionErrorMessage == nil)
    }

    @Test("a rejected description save reports why and keeps the old text")
    func saveDescriptionFailureSurfacesError() async throws {
        defer { DetailStub.reset() }
        let session = DetailStub.session { request in
            if request.httpMethod == "PUT" {
                return (try DetailStub.jsonResponse(for: request, status: 403), Data("{}".utf8))
            }
            return try DetailStub.route(request, routes: DetailFixtures.happyRoutes)
        }
        let model = makeModel(session: session)
        await model.load()

        await model.saveDescription("Nope")

        #expect(model.actionErrorMessage == JiraError.forbidden.userMessage)
        #expect(model.descriptionText == "Everything visible without opening Jira.")
        #expect(model.isSavingDescription == false)
    }

    // MARK: - Helpers

    private func makeModel(session: URLSession) -> JiraIssueDetailModel {
        JiraIssueDetailModel(client: DetailStub.client(session: session),
                             issueKey: "SHR-1",
                             siteHost: "acme.atlassian.net")
    }
}

// MARK: - Fixtures

private enum DetailFixtures {

    /// Keyed by the path suffix the client hits; "" is the issue itself.
    static var happyRoutes: [String: String] {
        [
            "": issueJSON,
            "/comment": commentsJSON,
            "/changelog": changelogJSON,
            "/worklog": worklogJSON,
        ]
    }

    static let issueJSON = """
    {
      "id": "10001",
      "key": "SHR-1",
      "self": "https://acme.atlassian.net/rest/api/3/issue/10001",
      "fields": {
        "summary": "Ship the detail sheet",
        "status": { "name": "In Progress", "statusCategory": { "key": "indeterminate", "name": "In Progress", "colorName": "yellow" } },
        "issuetype": { "id": "10002", "name": "Story", "iconUrl": null, "subtask": false },
        "assignee": { "accountId": "u1", "displayName": "Bakhodir" },
        "description": {
          "type": "doc",
          "version": 1,
          "content": [
            { "type": "paragraph", "content": [{ "type": "text", "text": "Everything visible without opening Jira." }] }
          ]
        }
      }
    }
    """

    static let issueAfterSaveJSON = """
    {
      "id": "10001",
      "key": "SHR-1",
      "self": "https://acme.atlassian.net/rest/api/3/issue/10001",
      "fields": {
        "summary": "Ship the detail sheet",
        "status": { "name": "In Progress", "statusCategory": { "key": "indeterminate", "name": "In Progress", "colorName": "yellow" } },
        "issuetype": { "id": "10002", "name": "Story", "iconUrl": null, "subtask": false },
        "description": {
          "type": "doc",
          "version": 1,
          "content": [
            { "type": "paragraph", "content": [{ "type": "text", "text": "Rewritten" }] },
            { "type": "paragraph", "content": [{ "type": "text", "text": "from Sharingan" }] }
          ]
        }
      }
    }
    """

    static let commentsJSON = """
    {
      "startAt": 0, "maxResults": 20, "total": 2,
      "comments": [
        {
          "id": "1", "self": "https://acme.atlassian.net/rest/api/3/issue/10001/comment/1",
          "author": { "accountId": "u1", "displayName": "Bakhodir" },
          "created": "2026-07-14T09:05:00.000+0000", "updated": "2026-07-14T09:05:00.000+0000",
          "body": {
            "type": "doc", "version": 1,
            "content": [
              { "type": "paragraph", "content": [
                  { "type": "mention", "attrs": { "text": "Bakhodir" } },
                  { "type": "text", "text": " please review" }
              ] },
              { "type": "bulletList", "content": [
                  { "type": "listItem", "content": [{ "type": "paragraph", "content": [{ "type": "text", "text": "Details tab" }] }] },
                  { "type": "listItem", "content": [{ "type": "paragraph", "content": [{ "type": "text", "text": "History tab" }] }] }
              ] }
            ]
          }
        },
        {
          "id": "2", "self": "https://acme.atlassian.net/rest/api/3/issue/10001/comment/2",
          "author": { "accountId": "u2", "displayName": "Dev User" },
          "created": "2026-07-14T10:00:00.000+0000", "updated": "2026-07-14T10:00:00.000+0000",
          "body": { "type": "doc", "version": 1, "content": [{ "type": "paragraph", "content": [{ "type": "text", "text": "Done — shipping it." }] }] }
        }
      ]
    }
    """

    static let createdCommentJSON = """
    {
      "id": "3", "self": "https://acme.atlassian.net/rest/api/3/issue/10001/comment/3",
      "author": { "accountId": "u1", "displayName": "Bakhodir" },
      "created": "2026-07-15T09:00:00.000+0000", "updated": "2026-07-15T09:00:00.000+0000",
      "body": { "type": "doc", "version": 1, "content": [{ "type": "paragraph", "content": [{ "type": "text", "text": "Looks good to me" }] }] }
    }
    """

    static let commentsAfterPostJSON = """
    {
      "startAt": 0, "maxResults": 20, "total": 3,
      "comments": [
        {
          "id": "1", "self": "s", "author": { "accountId": "u1", "displayName": "Bakhodir" },
          "created": "2026-07-14T09:05:00.000+0000", "updated": "2026-07-14T09:05:00.000+0000",
          "body": { "type": "doc", "version": 1, "content": [{ "type": "paragraph", "content": [{ "type": "text", "text": "first" }] }] }
        },
        {
          "id": "2", "self": "s", "author": { "accountId": "u2", "displayName": "Dev User" },
          "created": "2026-07-14T10:00:00.000+0000", "updated": "2026-07-14T10:00:00.000+0000",
          "body": { "type": "doc", "version": 1, "content": [{ "type": "paragraph", "content": [{ "type": "text", "text": "second" }] }] }
        },
        {
          "id": "3", "self": "s", "author": { "accountId": "u1", "displayName": "Bakhodir" },
          "created": "2026-07-15T09:00:00.000+0000", "updated": "2026-07-15T09:00:00.000+0000",
          "body": { "type": "doc", "version": 1, "content": [{ "type": "paragraph", "content": [{ "type": "text", "text": "Looks good to me" }] }] }
        }
      ]
    }
    """

    static let changelogJSON = """
    {
      "startAt": 0, "maxResults": 100, "total": 2,
      "histories": [
        {
          "id": "9001",
          "author": { "accountId": "u1", "displayName": "Bakhodir" },
          "created": "2026-07-14T09:00:00.000+0000",
          "items": [
            { "field": "status", "fieldtype": "jira", "from": "10000", "fromString": "To Do", "to": "3", "toString": "In Progress" }
          ]
        },
        {
          "id": "9002",
          "author": { "accountId": "u2", "displayName": "Dev User" },
          "created": "2026-07-14T11:00:00.000+0000",
          "items": []
        }
      ]
    }
    """

    static let changelogAssigneeSetJSON = """
    {
      "startAt": 0, "maxResults": 100, "total": 1,
      "histories": [
        {
          "id": "9003",
          "author": { "accountId": "u1", "displayName": "Bakhodir" },
          "created": "2026-07-14T09:00:00.000+0000",
          "items": [
            { "field": "assignee", "fieldtype": "jira", "from": null, "fromString": "", "to": "u1", "toString": "Bakhodir" }
          ]
        }
      ]
    }
    """

    static let worklogJSON = """
    {
      "startAt": 0, "maxResults": 20, "total": 1,
      "worklogs": [
        {
          "id": "5001", "self": "https://acme.atlassian.net/rest/api/3/issue/10001/worklog/5001",
          "author": { "accountId": "u1", "displayName": "Bakhodir" },
          "started": "2026-07-14T08:00:00.000+0000",
          "timeSpent": "1h 30m", "timeSpentSeconds": 5400,
          "created": "2026-07-14T09:30:00.000+0000", "updated": "2026-07-14T09:30:00.000+0000"
        }
      ]
    }
    """

    static let emptyWorklogJSON = """
    { "startAt": 0, "maxResults": 20, "total": 0, "worklogs": [] }
    """
}

// MARK: - Stub

/// A `JiraTokenProviding` that hands out one canned token — this file's tests
/// exercise the detail model, not the refresh path.
private final class DetailStubTokens: JiraTokenProviding, @unchecked Sendable {
    func accessToken() async throws -> String { "at-1" }
    func cloudID() async throws -> String { "cloud-1" }
}

/// One request as it reached the stub, recorded so the *test body* can assert on
/// it. `startLoading()` runs on URLSession's queue, outside the test's task-local
/// context, so an `#expect` there is filed against `Test «unknown»` and cannot
/// fail the test.
private struct DetailRecordedRequest: @unchecked Sendable {
    let request: URLRequest
    /// Drained at record time — the body stream is single-pass.
    let body: Data?

    var method: String? { request.httpMethod }
    var url: URL? { request.url }

    func header(_ name: String) -> String? { request.value(forHTTPHeaderField: name) }

    func jsonObject() throws -> [String: Any] {
        let data = try #require(body, "request had no body")
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any],
                            "request body was not a JSON object")
    }
}

private final class DetailStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var _handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    private static var _requests: [DetailRecordedRequest] = []

    static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { lock.lock(); defer { lock.unlock() }; return _handler }
        set { lock.lock(); defer { lock.unlock() }; _handler = newValue }
    }

    static var requests: [DetailRecordedRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        _handler = nil
        _requests = []
    }

    /// Empties the log but keeps the handler, so a test can assert on only the
    /// traffic from the step it is exercising.
    static func clearRequests() {
        lock.lock(); defer { lock.unlock() }
        _requests = []
    }

    private static func record(_ recorded: DetailRecordedRequest) {
        lock.lock(); defer { lock.unlock() }
        _requests.append(recorded)
    }

    // MARK: Response builders (no assertions — these run off-test)

    static func jsonResponse(for request: URLRequest, status: Int) throws -> HTTPURLResponse {
        guard let url = request.url else { throw URLError(.badURL) }
        guard let response = HTTPURLResponse(url: url,
                                             statusCode: status,
                                             httpVersion: nil,
                                             headerFields: ["Content-Type": "application/json"]) else {
            throw URLError(.badServerResponse)
        }
        return response
    }

    /// Routes on the suffix after `/issue/{key}`: "" is the issue, "/comment",
    /// "/changelog", "/worklog" are its sections. An unrouted path 404s rather
    /// than silently answering the wrong fixture.
    static func route(_ request: URLRequest, routes: [String: String]) throws -> (HTTPURLResponse, Data) {
        let path = request.url?.path ?? ""
        let suffix: String
        if let range = path.range(of: "/rest/api/3/issue/SHR-1") {
            suffix = String(path[range.upperBound...])
        } else {
            suffix = path
        }
        guard let body = routes[suffix] else {
            return (try jsonResponse(for: request, status: 404), Data("{}".utf8))
        }
        return (try jsonResponse(for: request, status: 200), Data(body.utf8))
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        Self.record(DetailRecordedRequest(request: request, body: request.detailBodyData))
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

    static func client(session: URLSession) -> JiraClient {
        JiraClient(tokens: DetailStubTokens(), session: session)
    }
}

private extension URLRequest {
    /// The request body as seen from inside a `URLProtocol`.
    ///
    /// URLSession moves `httpBody` into `httpBodyStream` before a custom protocol
    /// sees the request, so `httpBody` always reads back nil here — assertions
    /// must drain the stream instead.
    var detailBodyData: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
