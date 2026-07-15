import Foundation

/// Thin Jira Cloud REST client.
///
/// The actor owns the current credentials so every request can be made with a
/// simple `await client.myself()` call from UI code.
public actor JiraClient {

    public struct Configuration: Equatable, Sendable {
        public let siteURL: URL
        public let email: String
        public let apiToken: String

        public init(siteURL: URL, email: String, apiToken: String) {
            self.siteURL = siteURL
            self.email = email
            self.apiToken = apiToken
        }

        public var host: String {
            siteURL.host?.lowercased() ?? siteURL.absoluteString.lowercased()
        }
    }

    private let session: URLSession
    private var configuration: Configuration?
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(session: URLSession = .shared, configuration: Configuration? = nil) {
        self.session = session
        self.configuration = configuration
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    public func configure(siteURL: URL, email: String, apiToken: String) {
        configuration = Configuration(siteURL: siteURL, email: email, apiToken: apiToken)
    }

    public func clearConfiguration() {
        configuration = nil
    }

    public func currentConfiguration() -> Configuration? {
        configuration
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

    public func createIssue(fields: JiraIssueUpdateFields) async throws -> JiraIssue {
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

    // MARK: - Agile API (Boards, Sprints)

    public func getBoards(startAt: Int = 0, maxResults: Int = 50) async throws -> JiraBoardListResponse {
        let queryItems = [
            URLQueryItem(name: "startAt", value: String(startAt)),
            URLQueryItem(name: "maxResults", value: String(maxResults))
        ]
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
        guard let configuration else { throw JiraError.notConfigured }

        var components = URLComponents(url: configuration.siteURL, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else {
            throw JiraError.network("Invalid Jira URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue(Self.basicAuth(email: configuration.email,
                                        token: configuration.apiToken),
                         forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw JiraError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw JiraError.network("Invalid response from Jira.")
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

    private static func basicAuth(email: String, token: String) -> String {
        let raw = "\(email):\(token)"
        let encoded = Data(raw.utf8).base64EncodedString()
        return "Basic \(encoded)"
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