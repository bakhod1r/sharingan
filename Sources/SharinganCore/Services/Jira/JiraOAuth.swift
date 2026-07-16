import Foundation
import Network

/// Static configuration for the Atlassian OAuth 2.0 (3LO) app.
///
/// `clientSecret` ships inside the app. Atlassian's 3LO does not support PKCE,
/// and the token endpoint requires the secret, so a desktop app either embeds it
/// or proxies token calls through a server the developer runs. This app embeds
/// it: a determined user can extract the secret, but it only lets them start
/// *their own* consent flow — it grants no access to anyone else's Jira data.
/// See the note at `tokenEndpoint` for what a future proxy would change.
public struct JiraOAuthConfig: Sendable {
    public var clientID: String
    public var clientSecret: String
    /// Must exactly match a callback registered in the Atlassian developer
    /// console: `http://localhost:53682/callback`.
    public var redirectURI: String
    public var scopes: [String]
    /// When set, token exchange and refresh POST to this URL **without**
    /// `client_secret`; the broker holds the secret and forwards to Atlassian.
    /// This is the real fix for the embedded-secret problem — with it, the app
    /// can ship with an empty `clientSecret` and nothing sensitive is extractable
    /// from the bundle. Nil keeps the direct (secret-in-app) flow.
    public var tokenBrokerURL: URL?

    public init(clientID: String,
                clientSecret: String,
                redirectURI: String = JiraOAuth.defaultRedirectURI,
                scopes: [String] = JiraOAuth.defaultScopes,
                tokenBrokerURL: URL? = nil) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
        self.scopes = scopes
        self.tokenBrokerURL = tokenBrokerURL
    }
}

/// One Atlassian site the token can reach. `id` is the cloudId.
public struct JiraAccessibleResource: Sendable, Equatable, Decodable {
    public let id: String
    public let url: String
    public let name: String
    public let scopes: [String]
    public let avatarUrl: String?

    public init(id: String, url: String, name: String, scopes: [String] = [], avatarUrl: String? = nil) {
        self.id = id
        self.url = url
        self.name = name
        self.scopes = scopes
        self.avatarUrl = avatarUrl
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        url = try c.decode(String.self, forKey: .url)
        name = try c.decode(String.self, forKey: .name)
        scopes = try c.decodeIfPresent([String].self, forKey: .scopes) ?? []
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
    }

    private enum CodingKeys: String, CodingKey {
        case id, url, name, scopes, avatarUrl
    }
}

/// The Atlassian 3LO engine: authorize URL, loopback callback, code exchange,
/// refresh, and cloudId lookup. Everything else (persistence, UI) lives outside.
public actor JiraOAuth {

    /// Tokens minted by the authorization server. `refreshToken` is *always* the
    /// newest one — see `refresh(refreshToken:)`.
    public typealias Tokens = (accessToken: String, refreshToken: String, expiresAt: Date, scopes: [String])

    public static let authorizeEndpoint = URL(string: "https://auth.atlassian.com/authorize")!
    /// The one place the client secret goes on the wire. A backend proxy would
    /// replace this URL with its own and drop `clientSecret` from the body.
    public static let tokenEndpoint = URL(string: "https://auth.atlassian.com/oauth/token")!
    public static let accessibleResourcesEndpoint = URL(string: "https://api.atlassian.com/oauth/token/accessible-resources")!

    /// Registered loopback callback. Atlassian does not endorse custom URL
    /// schemes, so the app listens on a fixed port instead.
    public static let callbackPort: UInt16 = 53682
    public static let defaultRedirectURI = "http://localhost:53682/callback"
    /// `offline_access` is mandatory: without it Atlassian returns no refresh
    /// token and the user re-consents every hour.
    ///
    /// The `*:jira-software` scopes cover the Agile REST API the sprint board
    /// uses (`/rest/agile/1.0/board`, `/sprint`) — the classic `read:jira-work`
    /// scope does NOT, so without these the board 401s while task sync (the
    /// platform API) works. **The OAuth app must also have the "Jira Software
    /// API" added with these scopes selected in the Atlassian developer
    /// console**, otherwise authorization fails with an invalid-scope error.
    public static let defaultScopes = [
        "read:jira-user", "read:jira-work", "write:jira-work",
        "read:board-scope:jira-software",
        "read:sprint:jira-software",
        "write:sprint:jira-software",
        "offline_access",
    ]

    private let config: JiraOAuthConfig
    private let session: URLSession

    public init(config: JiraOAuthConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    // MARK: - Authorization

    /// The URL to open in the user's browser. `state` must be a fresh
    /// unguessable value and must be handed to `awaitCallback(state:...)`.
    public nonisolated func authorizationURL(state: String) -> URL {
        var components = URLComponents(url: Self.authorizeEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "audience", value: "api.atlassian.com"),
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        // URLComponents leaves a literal `+` alone in a query value, and a
        // server decoding `application/x-www-form-urlencoded` reads it back as a
        // space — which would corrupt a caller-supplied `state` and make the
        // callback's state check fail. Nothing else encodes *into* `+`, so
        // escaping it here is safe and complete.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }

    /// A cryptographically random `state` value.
    public static func makeState() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Token exchange

    public func exchange(code: String) async throws -> Tokens {
        try await postToken([
            "grant_type": "authorization_code",
            "client_id": config.clientID,
            "code": code,
            "redirect_uri": config.redirectURI,
        ])
    }

    /// Exchanges a refresh token for a new access token **and a new refresh
    /// token**.
    ///
    /// Atlassian rotates refresh tokens: the token passed in is invalidated and
    /// the returned `refreshToken` is the only one that will work next time.
    /// Callers must persist the whole result before doing anything else —
    /// dropping it on the floor logs the user out whenever the current access
    /// token expires. (Atlassian keeps the old token usable for ~10 minutes to
    /// cover a lost response; that is a safety net, not a licence to ignore the
    /// new one.) Inactivity expiry is 90 days.
    public func refresh(refreshToken: String) async throws -> Tokens {
        try await postToken([
            "grant_type": "refresh_token",
            "client_id": config.clientID,
            "refresh_token": refreshToken,
        ])
    }

    private func postToken(_ body: [String: String]) async throws -> Tokens {
        // With a broker, POST to it and let it add the secret server-side; only
        // the direct flow puts the secret on the wire from the app.
        var body = body
        let endpoint: URL
        if let broker = config.tokenBrokerURL {
            endpoint = broker
        } else {
            endpoint = Self.tokenEndpoint
            body["client_secret"] = config.clientSecret
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])

        let (data, response) = try await perform(request)
        guard (200..<300).contains(response.statusCode) else {
            throw Self.mapTokenError(status: response.statusCode, data: data)
        }

        let payload: TokenResponse
        do {
            payload = try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw JiraError.decoding(error.localizedDescription)
        }
        guard let newRefresh = payload.refresh_token else {
            // No refresh token means `offline_access` was not granted — the
            // session would silently die in an hour. Fail loudly now.
            throw JiraError.decoding("Atlassian returned no refresh token — the offline_access scope is missing.")
        }
        return (accessToken: payload.access_token,
                refreshToken: newRefresh,
                expiresAt: Date().addingTimeInterval(TimeInterval(payload.expires_in)),
                scopes: payload.scope?.split(separator: " ").map(String.init) ?? [])
    }

    // MARK: - Accessible resources (cloudId lookup)

    public func accessibleResources(accessToken: String) async throws -> [JiraAccessibleResource] {
        var request = URLRequest(url: Self.accessibleResourcesEndpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await perform(request)
        guard (200..<300).contains(response.statusCode) else {
            throw Self.mapStatusError(status: response.statusCode, data: data)
        }
        do {
            return try JSONDecoder().decode([JiraAccessibleResource].self, from: data)
        } catch {
            throw JiraError.decoding(error.localizedDescription)
        }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw JiraError.network("Invalid response from Atlassian.")
            }
            return (data, http)
        } catch let error as JiraError {
            throw error
        } catch {
            throw JiraError.network(error.localizedDescription)
        }
    }

    // MARK: - Loopback callback receiver

    /// Runs a one-shot HTTP listener on the loopback callback port and returns
    /// the authorization `code` once the browser redirects to it.
    ///
    /// - Parameters:
    ///   - state: the value passed to `authorizationURL(state:)`. A response
    ///     carrying any other state is rejected — that check is the whole reason
    ///     `state` exists (CSRF: an attacker feeding us *their* code would
    ///     otherwise link the user's Sharingan to the attacker's Jira account).
    ///   - timeout: gives up and releases the port. A leaked listener makes the
    ///     next attempt fail with "address in use".
    ///   - port: overridable so tests can bind an ephemeral port.
    /// - Returns: the authorization code.
    public func awaitCallback(state: String,
                              timeout: TimeInterval = 180,
                              port: UInt16 = JiraOAuth.callbackPort) async throws -> String {
        let receiver = LoopbackCallbackReceiver(expectedState: state, port: port)
        return try await receiver.run(timeout: timeout)
    }

    // MARK: - Errors

    public static func portInUseError(_ port: UInt16) -> JiraError {
        .network("Port \(port) is already in use, so Sharingan can't receive the Jira sign-in response. Quit whatever is using port \(port) and try again.")
    }

    public static let stateMismatchError = JiraError.api(
        status: 400,
        messages: ["The Jira sign-in response didn't match this request (state mismatch). Start the connection again."]
    )

    public static func timeoutError(_ port: UInt16) -> JiraError {
        .network("Timed out waiting for the Jira sign-in response on port \(port).")
    }

    /// The OAuth token endpoint speaks `{"error": ..., "error_description": ...}`,
    /// not Jira's error envelope.
    static func mapTokenError(status: Int, data: Data) -> JiraError {
        let payload = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data)
        let message = payload?.error_description ?? payload?.error

        // `invalid_grant` means the refresh token is spent, revoked, or 90 days
        // idle — the session is dead and only re-consent fixes it.
        if payload?.error == "invalid_grant" { return .unauthorized }
        if payload?.error == "unauthorized_client" || payload?.error == "invalid_client" { return .unauthorized }

        switch status {
        case 401, 403: return .unauthorized
        case 429: return .rateLimited(retryAfter: nil)
        case 500...599: return .server(status: status)
        default:
            return .api(status: status, messages: [message ?? "Atlassian rejected the sign-in (\(status))."])
        }
    }

    static func mapStatusError(status: Int, data: Data) -> JiraError {
        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 429: return .rateLimited(retryAfter: nil)
        case 500...599: return .server(status: status)
        default:
            let payload = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data)
            let message = payload?.error_description ?? payload?.error
            return .api(status: status, messages: [message ?? "Atlassian request failed (\(status))."])
        }
    }

    // MARK: - Wire shapes

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Int
        let refresh_token: String?
        let scope: String?
        let token_type: String?
    }

    struct OAuthErrorResponse: Decodable {
        let error: String?
        let error_description: String?
    }
}

// MARK: - Loopback receiver

/// One-shot `NWListener` that waits for `GET /callback?code=…&state=…`.
///
/// Owns exactly one continuation and tears everything down on the first outcome,
/// whichever arrives first: a matching callback, an error redirect, a listener
/// failure, or the timeout. `finish` is idempotent — the port is always released.
final class LoopbackCallbackReceiver: @unchecked Sendable {
    /// What a parsed HTTP request means. `nil` (not a case here) is modelled by
    /// `callbackOutcome` returning nil: an unrelated request, e.g. /favicon.ico.
    enum Outcome: Equatable {
        case code(String)
        case failure(JiraError)
    }

    private let lock = NSLock()
    private let expectedState: String
    private let port: UInt16
    private var continuation: CheckedContinuation<String, Error>?
    private var listener: NWListener?
    private var timeoutTask: Task<Void, Never>?
    private var isFinished = false

    init(expectedState: String, port: UInt16) {
        self.expectedState = expectedState
        self.port = port
    }

    func run(timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            start(timeout: timeout)
        }
    }

    private func start(timeout: TimeInterval) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            finish(.failure(JiraOAuth.portInUseError(port)))
            return
        }

        let parameters = NWParameters.tcp
        // A crashed previous run can leave the port in TIME_WAIT; reuse keeps
        // the next sign-in from failing for a minute for no good reason.
        parameters.allowLocalEndpointReuse = true

        let newListener: NWListener
        do {
            newListener = try NWListener(using: parameters, on: nwPort)
        } catch {
            finish(.failure(JiraOAuth.portInUseError(port)))
            return
        }

        lock.lock()
        listener = newListener
        lock.unlock()

        // "Address in use" surfaces here, asynchronously, not from the
        // initializer — so this handler, not a `try`, is what reports it.
        newListener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .failed = state {
                self.finish(.failure(JiraOAuth.portInUseError(self.port)))
            }
        }
        newListener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        newListener.start(queue: .global(qos: .userInitiated))

        let deadline = timeout
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, deadline) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.finish(.failure(JiraOAuth.timeoutError(self.port)))
        }
        lock.lock()
        timeoutTask = task
        lock.unlock()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        // The request line is in the first segment for any real browser GET;
        // 64 KiB is far more than a redirect ever needs.
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, error in
            guard let self else { connection.cancel(); return }
            guard error == nil,
                  let data,
                  let text = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            let outcome = Self.callbackOutcome(requestText: text, expectedState: self.expectedState)
            let response = Self.httpResponse(for: outcome)
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
            if let outcome { self.finish(outcome) }
        }
    }

    /// Parses a raw HTTP request into an outcome.
    ///
    /// Pure and static so it can be tested without binding a port.
    /// Returns `nil` for anything that isn't the callback (e.g. /favicon.ico),
    /// which must not end the wait.
    static func callbackOutcome(requestText: String, expectedState: String) -> Outcome? {
        guard let requestLine = requestText.split(separator: "\r\n", omittingEmptySubsequences: false).first
                ?? requestText.split(separator: "\n").first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return nil }

        guard let components = URLComponents(string: "http://localhost\(parts[1])"),
              components.path == "/callback" else { return nil }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        // State first: a mismatched response is untrusted, whatever else it says.
        guard let state = value("state"), state == expectedState else {
            return .failure(JiraOAuth.stateMismatchError)
        }

        if let error = value("error") {
            let description = value("error_description") ?? error
            if error == "access_denied" {
                return .failure(.forbidden)
            }
            return .failure(.api(status: 400, messages: [description]))
        }

        guard let code = value("code"), !code.isEmpty else {
            return .failure(.api(status: 400, messages: ["Atlassian's response contained no authorization code."]))
        }
        return .code(code)
    }

    private static func httpResponse(for outcome: Outcome?) -> String {
        guard let outcome else {
            return "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        }
        let (status, heading, detail): (String, String, String)
        switch outcome {
        case .code:
            (status, heading, detail) = ("200 OK", "Jira connected", "You can close this tab and return to Sharingan.")
        case .failure(let error):
            (status, heading, detail) = ("400 Bad Request", "Couldn't connect Jira", error.userMessage)
        }
        let body = """
        <!doctype html><html><head><meta charset="utf-8"><title>Sharingan</title>\
        <style>body{font:16px -apple-system,system-ui,sans-serif;display:flex;height:100vh;margin:0;\
        align-items:center;justify-content:center;background:#111;color:#eee}\
        div{text-align:center}h1{font-size:20px;margin:0 0 8px}p{opacity:.7;margin:0}</style></head>\
        <body><div><h1>\(heading)</h1><p>\(detail)</p></div></body></html>
        """
        return """
        HTTP/1.1 \(status)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
    }

    /// Resumes the continuation at most once and always releases the port.
    private func finish(_ outcome: Outcome) {
        lock.lock()
        if isFinished {
            lock.unlock()
            return
        }
        isFinished = true
        let continuation = self.continuation
        let listener = self.listener
        let timeoutTask = self.timeoutTask
        self.continuation = nil
        self.listener = nil
        self.timeoutTask = nil
        lock.unlock()

        timeoutTask?.cancel()
        listener?.cancel()

        switch outcome {
        case .code(let code): continuation?.resume(returning: code)
        case .failure(let error): continuation?.resume(throwing: error)
        }
    }
}
