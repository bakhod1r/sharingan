import Foundation

/// Supplies the two things every OAuth 2.0 (3LO) request needs: a *currently
/// valid* access token and the cloudId of the site to talk to.
///
/// `accessToken()` is expected to refresh transparently and to be safe to call
/// concurrently — the client calls it on every request and again after a 401,
/// and must never end up driving two refreshes at once (Atlassian rotates
/// refresh tokens, so a double refresh logs the user out). Serializing that is
/// the provider's job, not the client's; see `JiraOAuthTokenProvider`.
public protocol JiraTokenProviding: Sendable {
    /// A valid access token, refreshing first if the current one is stale.
    func accessToken() async throws -> String
    /// The Atlassian cloudId resolved at connect time.
    func cloudID() async throws -> String
}

/// Thin Jira Cloud REST client, speaking OAuth 2.0 (3LO) through Atlassian's
/// gateway.
///
/// Under 3LO nothing is addressed at the customer's site host: every REST and
/// Agile call goes to `https://api.atlassian.com/ex/jira/{cloudId}/…` with a
/// bearer token. The client deliberately owns **no** credentials — no site, no
/// secret, no refresh logic. It asks `tokens` for a bearer token per request and
/// otherwise stays a dumb pipe.
public actor JiraClient {

    /// Atlassian's OAuth gateway. Every request path is prefixed with
    /// `/ex/jira/{cloudId}`.
    public static let gatewayBaseURL = URL(string: "https://api.atlassian.com")!

    private let session: URLSession
    private let tokens: JiraTokenProviding
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(tokens: JiraTokenProviding, session: URLSession = .shared) {
        self.tokens = tokens
        self.session = session
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    public func myself() async throws -> JiraMyself {
        try await request(path: "/rest/api/3/myself", method: "GET")
    }

    // MARK: - Search JQL (POST /rest/api/3/search/jql)

    public func searchJQL(jql: String,
                          maxResults: Int = 50,
                          nextPageToken: String? = nil,
                          fields: [String]? = nil,
                          expand: [String]? = nil) async throws -> JiraSearchResult {
        let requestBody = JiraSearchJQLRequest(
            jql: jql,
            maxResults: maxResults,
            nextPageToken: nextPageToken,
            fields: fields,
            expand: expand
        )
        let body = try encoder.encode(requestBody)
        return try await request(path: "/rest/api/3/search/jql", method: "POST", body: body)
    }

    // MARK: - Issue CRUD

    public func getIssue(key: String, fields: [String]? = nil, expand: [String]? = nil) async throws -> JiraIssue {
        var queryItems: [URLQueryItem] = []
        if let fields { queryItems.append(URLQueryItem(name: "fields", value: fields.joined(separator: ","))) }
        if let expand { queryItems.append(URLQueryItem(name: "expand", value: expand.joined(separator: ","))) }
        return try await request(path: "/rest/api/3/issue/\(key)", method: "GET", queryItems: queryItems)
    }

    public func updateIssue(key: String, fields: JiraIssueUpdateFields) async throws {
        let body = try encoder.encode(["fields": fields])
        _ = try await request(path: "/rest/api/3/issue/\(key)", method: "PUT", body: body) as EmptyResponse
    }

    /// Creates an issue. Unlike an update, Jira requires `project` and
    /// `issuetype` here — the old updateFields path omitted both and would 400.
    /// Returns the new issue's id and key.
    public func createIssue(fields: JiraIssueCreateFields) async throws -> JiraIssueRef {
        let body = try encoder.encode(["fields": fields])
        return try await request(path: "/rest/api/3/issue", method: "POST", body: body)
    }

    // MARK: - Transitions

    public func getTransitions(issueKey: String) async throws -> [JiraTransition] {
        let response: JiraTransitionsResponse = try await request(path: "/rest/api/3/issue/\(issueKey)/transitions", method: "GET")
        return response.transitions
    }

    public func doTransition(issueKey: String, transitionId: String) async throws {
        let input = JiraTransitionInput(transitionId: transitionId)
        let body = try encoder.encode(input)
        _ = try await request(path: "/rest/api/3/issue/\(issueKey)/transitions", method: "POST", body: body) as EmptyResponse
    }

    // MARK: - Comments

    public func addComment(issueKey: String, body: String) async throws -> JiraComment {
        let adf = ADF.document(fromPlainText: body)
        let input = JiraCommentInput(body: try decoder.decode(JiraADFDocument.self, from: adf))
        let bodyData = try encoder.encode(input)
        return try await request(path: "/rest/api/3/issue/\(issueKey)/comment", method: "POST", body: bodyData)
    }

    public func getComments(issueKey: String, startAt: Int = 0, maxResults: Int = 20) async throws -> JiraCommentsResponse {
        let queryItems = [
            URLQueryItem(name: "startAt", value: String(startAt)),
            URLQueryItem(name: "maxResults", value: String(maxResults))
        ]
        return try await request(path: "/rest/api/3/issue/\(issueKey)/comment", method: "GET", queryItems: queryItems)
    }

    // MARK: - Changelog

    public func getChangelog(issueKey: String, startAt: Int = 0, maxResults: Int = 100) async throws -> JiraChangelog {
        let queryItems = [
            URLQueryItem(name: "startAt", value: String(startAt)),
            URLQueryItem(name: "maxResults", value: String(maxResults))
        ]
        return try await request(path: "/rest/api/3/issue/\(issueKey)/changelog", method: "GET", queryItems: queryItems)
    }

    // MARK: - Worklog

    public func addWorklog(issueKey: String, timeSpentSeconds: Int, started: String, comment: String? = nil, adjustEstimate: String = "auto") async throws -> JiraWorklogCreated {
        let commentADF: JiraADFDocument?
        if let comment = comment, !comment.isEmpty {
            let data = ADF.document(fromPlainText: comment)
            commentADF = try decoder.decode(JiraADFDocument.self, from: data)
        } else {
            commentADF = nil
        }
        let input = JiraWorklogInput(timeSpentSeconds: timeSpentSeconds, started: started, comment: commentADF)
        let body = try encoder.encode(input)
        // Jira reads adjustEstimate off the query string here, not the body.
        return try await request(path: "/rest/api/3/issue/\(issueKey)/worklog",
                                 method: "POST",
                                 body: body,
                                 queryItems: [URLQueryItem(name: "adjustEstimate", value: adjustEstimate)])
    }

    public func getWorklogs(issueKey: String, startAt: Int = 0, maxResults: Int = 20) async throws -> JiraWorklogResponse {
        let queryItems = [
            URLQueryItem(name: "startAt", value: String(startAt)),
            URLQueryItem(name: "maxResults", value: String(maxResults))
        ]
        return try await request(path: "/rest/api/3/issue/\(issueKey)/worklog", method: "GET", queryItems: queryItems)
    }

    // MARK: - Projects & Issue Types

    public func getProjects(startAt: Int = 0, maxResults: Int = 50) async throws -> JiraProjectListResponse {
        let queryItems = [
            URLQueryItem(name: "startAt", value: String(startAt)),
            URLQueryItem(name: "maxResults", value: String(maxResults))
        ]
        return try await request(path: "/rest/api/3/project/search", method: "GET", queryItems: queryItems)
    }

    /// - Parameter projectId: Jira matches this endpoint on the numeric project
    ///   id only; a project key is rejected with a 400.
    public func getIssueTypes(projectId: String) async throws -> JiraIssueTypeListResponse {
        let queryItems = [
            URLQueryItem(name: "projectId", value: projectId)
        ]
        return try await request(path: "/rest/api/3/issuetype/project", method: "GET", queryItems: queryItems)
    }

    public func getEditMeta(issueKey: String) async throws -> JiraEditMeta {
        return try await request(path: "/rest/api/3/issue/\(issueKey)/editmeta", method: "GET")
    }

    // MARK: - Permissions

    /// The account's permissions, as a preflight after connect.
    ///
    /// This exists because Jira's search is silent about permission: a
    /// `POST /search/jql` naming a project the account cannot browse answers
    /// `200 {"issues":[],"isLast":true}` — identical to a project that simply has
    /// no matching issues. Without this call "you have no access" and "you have
    /// no issues" are the same screen, and the honest failure ("connected, but
    /// this account can't see any projects") is unreachable.
    public func getMyPermissions(permissions: [String] = JiraPermissionKey.preflight) async throws -> JiraPermissionsResponse {
        let queryItems = [
            URLQueryItem(name: "permissions", value: permissions.joined(separator: ","))
        ]
        return try await request(path: "/rest/api/3/mypermissions", method: "GET", queryItems: queryItems)
    }

    // MARK: - Agile API (Boards, Sprints)

    /// - Parameter projectKeyOrId: When set, the Agile API returns only the
    ///   boards scoped to that project — a board key ("SHR") or numeric id both
    ///   work. Left nil, it lists every board the account can see.
    public func getBoards(projectKeyOrId: String? = nil,
                          startAt: Int = 0,
                          maxResults: Int = 50) async throws -> JiraBoardListResponse {
        var queryItems = [
            URLQueryItem(name: "startAt", value: String(startAt)),
            URLQueryItem(name: "maxResults", value: String(maxResults))
        ]
        if let projectKeyOrId, !projectKeyOrId.isEmpty {
            queryItems.append(URLQueryItem(name: "projectKeyOrId", value: projectKeyOrId))
        }
        return try await request(path: "/rest/agile/1.0/board", method: "GET", queryItems: queryItems)
    }

    public func getBoardConfiguration(boardId: Int) async throws -> JiraBoardConfiguration {
        return try await request(path: "/rest/agile/1.0/board/\(boardId)/configuration", method: "GET")
    }

    public func getActiveSprint(boardId: Int) async throws -> JiraSprint? {
        let response: JiraSprintListResponse = try await request(path: "/rest/agile/1.0/board/\(boardId)/sprint", method: "GET", queryItems: [
            URLQueryItem(name: "state", value: "active")
        ])
        return response.values.first
    }

    public func getSprintIssues(sprintId: Int, startAt: Int = 0, maxResults: Int = 50) async throws -> JiraSprintIssuesResponse {
        let queryItems = [
            URLQueryItem(name: "startAt", value: String(startAt)),
            URLQueryItem(name: "maxResults", value: String(maxResults))
        ]
        return try await request(path: "/rest/agile/1.0/sprint/\(sprintId)/issue", method: "GET", queryItems: queryItems)
    }

    // MARK: - Private request machinery

    private struct EmptyResponse: Decodable, Sendable {}

    private func request<Response: Decodable>(path: String,
                                              method: String,
                                              body: Data? = nil,
                                              queryItems: [URLQueryItem] = []) async throws -> Response {
        let cloudID = try await tokens.cloudID()
        let url = try Self.gatewayURL(cloudID: cloudID, path: path, queryItems: queryItems)

        var (data, http) = try await send(url: url,
                                          method: method,
                                          body: body,
                                          token: try await tokens.accessToken())

        // One 401 can mean the token went stale a moment ago (clock skew, or a
        // token revoked server-side). Ask the provider once more — it may hand
        // back a freshly refreshed token — and retry exactly once. A second 401
        // is a real authorization failure; there is no loop here by design, the
        // refreshing lives entirely behind `tokens`.
        if http.statusCode == 401 {
            (data, http) = try await send(url: url,
                                          method: method,
                                          body: body,
                                          token: try await tokens.accessToken())
        }

        guard (200..<300).contains(http.statusCode) else {
            throw Self.mapError(statusCode: http.statusCode, data: data, headers: http.allHeaderFields)
        }

        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw JiraError.decoding(error.localizedDescription)
        }
    }

    private func send(url: URL,
                      method: String,
                      body: Data?,
                      token: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw JiraError.network("Invalid response from Jira.")
            }
            return (data, http)
        } catch let error as JiraError {
            throw error
        } catch {
            throw JiraError.network(error.localizedDescription)
        }
    }

    /// Builds `https://api.atlassian.com/ex/jira/{cloudId}{path}`.
    ///
    /// The prefix is *prepended to* `path`, never assigned over the base URL's
    /// path. An earlier version did `components.path = path`, which was harmless
    /// only because the old Basic-auth base URL had an empty path; doing that
    /// here would erase `/ex/jira/{cloudId}` and quietly aim every request at the
    /// gateway root.
    static func gatewayURL(cloudID: String, path: String, queryItems: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: gatewayBaseURL, resolvingAgainstBaseURL: false) else {
            throw JiraError.network("Invalid Jira URL.")
        }
        components.path = "\(gatewayBaseURL.path)/ex/jira/\(cloudID)\(path)"
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw JiraError.network("Invalid Jira URL.")
        }
        return url
    }

    private static func mapError(statusCode: Int,
                                 data: Data,
                                 headers: [AnyHashable: Any]) -> JiraError {
        let retryAfterHeader = headers.first { key, _ in
            String(describing: key).caseInsensitiveCompare("Retry-After") == .orderedSame
        }?.value
        let retryAfter = (retryAfterHeader as? String).flatMap(TimeInterval.init)

        let envelope = try? JSONDecoder().decode(JiraErrorEnvelope.self, from: data)
        let messages = envelope?.flattenedMessages ?? []

        switch statusCode {
        case 401:
            return .unauthorized
        case 403:
            return .forbidden
        case 404:
            return .notFound
        case 429:
            return .rateLimited(retryAfter: retryAfter)
        case 500...599:
            return .server(status: statusCode)
        default:
            if !messages.isEmpty {
                return .api(status: statusCode, messages: messages)
            }
            return .api(status: statusCode, messages: ["Jira request failed (\(statusCode))."])
        }
    }
}

// MARK: - Permission models

/// The permission keys the connect preflight asks about.
public enum JiraPermissionKey {
    /// Without this the account sees no projects at all — everything else is moot.
    public static let browseProjects = "BROWSE_PROJECTS"
    public static let createIssues = "CREATE_ISSUES"
    public static let workOnIssues = "WORK_ON_ISSUES"

    public static let preflight = [browseProjects, createIssues, workOnIssues]
}

/// One entry of `GET /rest/api/3/mypermissions`.
public struct JiraPermission: Decodable, Equatable, Sendable {
    public let id: String?
    public let key: String?
    public let name: String?
    public let havePermission: Bool

    public init(id: String? = nil, key: String? = nil, name: String? = nil, havePermission: Bool) {
        self.id = id
        self.key = key
        self.name = name
        self.havePermission = havePermission
    }
}

public struct JiraPermissionsResponse: Decodable, Equatable, Sendable {
    /// Keyed by permission key, e.g. `BROWSE_PROJECTS`.
    public let permissions: [String: JiraPermission]

    public init(permissions: [String: JiraPermission]) {
        self.permissions = permissions
    }

    public func has(_ key: String) -> Bool {
        permissions[key]?.havePermission == true
    }

    /// The one that decides whether this account can see anything at all.
    public var canBrowseProjects: Bool { has(JiraPermissionKey.browseProjects) }
}
