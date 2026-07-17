import Foundation
import Testing
@testable import SharinganCore

@Suite("Jira OAuth", .serialized)
struct JiraOAuthTests {

    private static func makeConfig() -> JiraOAuthConfig {
        JiraOAuthConfig(clientID: "client-abc",
                        clientSecret: "secret-xyz",
                        redirectURI: "http://localhost:53682/callback",
                        scopes: ["read:jira-user", "read:jira-work", "write:jira-work", "offline_access"])
    }

    // MARK: - Authorization URL

    @Test("authorizationURL carries every parameter Atlassian requires")
    func authorizationURLParameters() throws {
        let oauth = JiraOAuth(config: Self.makeConfig())
        let url = oauth.authorizationURL(state: "state-123")

        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "https")
        #expect(components.host == "auth.atlassian.com")
        #expect(components.path == "/authorize")

        let items = try #require(components.queryItems)
        var query: [String: String] = [:]
        for item in items { query[item.name] = item.value }

        #expect(query["audience"] == "api.atlassian.com")
        #expect(query["client_id"] == "client-abc")
        #expect(query["scope"] == "read:jira-user read:jira-work write:jira-work offline_access")
        #expect(query["redirect_uri"] == "http://localhost:53682/callback")
        #expect(query["state"] == "state-123")
        #expect(query["response_type"] == "code")
        #expect(query["prompt"] == "consent")
    }

    @Test("authorizationURL percent-encodes the scope separator and redirect URI")
    func authorizationURLEncoding() throws {
        let oauth = JiraOAuth(config: Self.makeConfig())
        let raw = oauth.authorizationURL(state: "a+b/c=").absoluteString

        // Spaces between scopes must not survive as literal spaces.
        #expect(!raw.contains(" "))
        #expect(raw.contains("scope=read:jira-user%20read:jira-work%20write:jira-work%20offline_access"))
        #expect(raw.contains("redirect_uri=http://localhost:53682/callback"))
        // `+` in state must be encoded, or the server reads it back as a space.
        #expect(raw.contains("state=a%2Bb/c%3D"))
    }

    @Test("makeState produces unguessable, distinct, URL-safe values")
    func makeStateIsRandom() {
        let a = JiraOAuth.makeState()
        let b = JiraOAuth.makeState()
        #expect(a != b)
        #expect(a.count >= 32)
        #expect(!a.contains("+") && !a.contains("/") && !a.contains("="))
    }

    // MARK: - Code exchange

    @Test("exchange POSTs authorization_code and parses the token response")
    func exchangeSendsCorrectBody() async throws {
        defer { OAuthStubProtocol.reset() }
        let session = OAuthStubProtocol.session { request in
            (try OAuthStubProtocol.jsonResponse(for: request, status: 200), Data("""
            {"access_token":"at-1","expires_in":3600,"refresh_token":"rt-1",
             "scope":"read:jira-work offline_access","token_type":"Bearer"}
            """.utf8))
        }

        let oauth = JiraOAuth(config: Self.makeConfig(), session: session)
        let before = Date()
        let tokens = try await oauth.exchange(code: "code-42")

        let sent = try #require(OAuthStubProtocol.requests.last)
        #expect(sent.method == "POST")
        #expect(sent.url?.absoluteString == "https://auth.atlassian.com/oauth/token")
        #expect(sent.header("Content-Type") == "application/json")

        let body = try sent.jsonObject()
        #expect(body["grant_type"] as? String == "authorization_code")
        #expect(body["client_id"] as? String == "client-abc")
        #expect(body["client_secret"] as? String == "secret-xyz")
        #expect(body["code"] as? String == "code-42")
        #expect(body["redirect_uri"] as? String == "http://localhost:53682/callback")

        #expect(tokens.accessToken == "at-1")
        #expect(tokens.refreshToken == "rt-1")
        #expect(tokens.scopes == ["read:jira-work", "offline_access"])
        #expect(tokens.expiresAt.timeIntervalSince(before) >= 3599)
        #expect(tokens.expiresAt.timeIntervalSince(before) <= 3601)
    }

    @Test("with a token broker configured, tokens go through the broker and carry no client secret")
    func brokerRoutesTokenExchangeWithoutSecret() async throws {
        defer { OAuthStubProtocol.reset() }
        let session = OAuthStubProtocol.session { request in
            (try OAuthStubProtocol.jsonResponse(for: request, status: 200), Data("""
            {"access_token":"at-1","expires_in":3600,"refresh_token":"rt-1",
             "scope":"read:jira-work offline_access","token_type":"Bearer"}
            """.utf8))
        }
        let config = JiraOAuthConfig(clientID: "client-abc", clientSecret: "secret-xyz",
                                     redirectURI: "http://localhost:53682/callback",
                                     scopes: ["read:jira-work", "offline_access"],
                                     tokenBrokerURL: URL(string: "https://broker.example.com/token"))
        let oauth = JiraOAuth(config: config, session: session)

        _ = try await oauth.exchange(code: "code-42")

        let sent = try #require(OAuthStubProtocol.requests.last)
        #expect(sent.url?.absoluteString == "https://broker.example.com/token")
        let body = try sent.jsonObject()
        #expect(body["grant_type"] as? String == "authorization_code")
        #expect(body["client_id"] as? String == "client-abc")
        #expect(body["code"] as? String == "code-42")
        // The whole point: the secret never leaves the broker.
        #expect(body["client_secret"] == nil)
    }

    @Test("with a broker, refresh also omits the secret and hits the broker")
    func brokerRoutesRefreshWithoutSecret() async throws {
        defer { OAuthStubProtocol.reset() }
        let session = OAuthStubProtocol.session { request in
            (try OAuthStubProtocol.jsonResponse(for: request, status: 200), Data("""
            {"access_token":"at-2","expires_in":3600,"refresh_token":"rt-2","token_type":"Bearer"}
            """.utf8))
        }
        let config = JiraOAuthConfig(clientID: "client-abc", clientSecret: "secret-xyz",
                                     tokenBrokerURL: URL(string: "https://broker.example.com/token"))
        let oauth = JiraOAuth(config: config, session: session)

        _ = try await oauth.refresh(refreshToken: "rt-1")

        let sent = try #require(OAuthStubProtocol.requests.last)
        #expect(sent.url?.absoluteString == "https://broker.example.com/token")
        let body = try sent.jsonObject()
        #expect(body["grant_type"] as? String == "refresh_token")
        #expect(body["refresh_token"] as? String == "rt-1")
        #expect(body["client_secret"] == nil)
    }

    @Test("a token response without a refresh token fails rather than yielding a session that dies in an hour")
    func exchangeWithoutRefreshTokenThrows() async throws {
        defer { OAuthStubProtocol.reset() }
        let session = OAuthStubProtocol.session { request in
            (try OAuthStubProtocol.jsonResponse(for: request, status: 200), Data("""
            {"access_token":"at-1","expires_in":3600,"scope":"read:jira-work","token_type":"Bearer"}
            """.utf8))
        }
        let oauth = JiraOAuth(config: Self.makeConfig(), session: session)

        do {
            _ = try await oauth.exchange(code: "code-42")
            Issue.record("expected a failure when offline_access is missing")
        } catch let error as JiraError {
            guard case .decoding = error else {
                Issue.record("expected a decoding failure, got \(error)")
                return
            }
        }
    }

    // MARK: - Refresh

    @Test("refresh POSTs refresh_token grant with the current token")
    func refreshSendsCorrectBody() async throws {
        defer { OAuthStubProtocol.reset() }
        let session = OAuthStubProtocol.session { request in
            (try OAuthStubProtocol.jsonResponse(for: request, status: 200), Data("""
            {"access_token":"at-2","expires_in":3600,"refresh_token":"rt-2",
             "scope":"read:jira-work offline_access","token_type":"Bearer"}
            """.utf8))
        }

        let oauth = JiraOAuth(config: Self.makeConfig(), session: session)
        _ = try await oauth.refresh(refreshToken: "rt-1")

        let sent = try #require(OAuthStubProtocol.requests.last)
        #expect(sent.method == "POST")
        #expect(sent.url?.absoluteString == "https://auth.atlassian.com/oauth/token")

        let body = try sent.jsonObject()
        #expect(body["grant_type"] as? String == "refresh_token")
        #expect(body["refresh_token"] as? String == "rt-1")
        #expect(body["client_id"] as? String == "client-abc")
        #expect(body["client_secret"] as? String == "secret-xyz")
        // The refresh grant must not carry the authorization-code fields.
        #expect(body["code"] == nil)
        #expect(body["redirect_uri"] == nil)
    }

    @Test("refresh returns the ROTATED refresh token, and that is what gets persisted")
    func refreshRotationIsPersisted() async throws {
        // Atlassian invalidates the old refresh token on every refresh. If the
        // rotated one isn't stored, the user is silently logged out once the
        // current access token expires — days later, far from this code.
        defer { OAuthStubProtocol.reset() }
        let session = OAuthStubProtocol.session { request in
            (try OAuthStubProtocol.jsonResponse(for: request, status: 200), Data("""
            {"access_token":"at-2","expires_in":3600,"refresh_token":"rt-ROTATED",
             "scope":"read:jira-work offline_access","token_type":"Bearer"}
            """.utf8))
        }

        let keychain = FakeKeychain()
        let defaults = try #require(UserDefaults(suiteName: "JiraOAuthTests.rotation"))
        defaults.removePersistentDomain(forName: "JiraOAuthTests.rotation")
        let store = keychain.makeStore(defaults: defaults)

        try store.save(JiraOAuthSession(accessToken: "at-1",
                                        refreshToken: "rt-OLD",
                                        expiresAt: Date(),
                                        cloudID: "cloud-1",
                                        siteURL: "https://wayll.atlassian.net",
                                        scopes: ["read:jira-work", "offline_access"]))

        let oauth = JiraOAuth(config: Self.makeConfig(), session: session)
        let existing = try #require(store.load())
        let tokens = try await oauth.refresh(refreshToken: existing.refreshToken)

        #expect(tokens.refreshToken == "rt-ROTATED")
        #expect(tokens.refreshToken != existing.refreshToken)

        var updated = existing
        updated.accessToken = tokens.accessToken
        updated.refreshToken = tokens.refreshToken
        updated.expiresAt = tokens.expiresAt
        try store.save(updated)

        // The rotated token is what a later launch reads back.
        let reloaded = try #require(store.load())
        #expect(reloaded.refreshToken == "rt-ROTATED")
        #expect(reloaded.accessToken == "at-2")
        #expect(keychain.values[JiraTokenStore.refreshTokenAccount] == "rt-ROTATED")

        defaults.removePersistentDomain(forName: "JiraOAuthTests.rotation")
    }

    @Test("invalid_grant on refresh means the session is dead → unauthorized")
    func refreshInvalidGrantIsUnauthorized() async throws {
        defer { OAuthStubProtocol.reset() }
        let session = OAuthStubProtocol.session { request in
            (try OAuthStubProtocol.jsonResponse(for: request, status: 403), Data("""
            {"error":"invalid_grant","error_description":"Unknown or invalid refresh token."}
            """.utf8))
        }
        let oauth = JiraOAuth(config: Self.makeConfig(), session: session)

        do {
            _ = try await oauth.refresh(refreshToken: "rt-dead")
            Issue.record("expected invalid_grant to fail")
        } catch let error as JiraError {
            #expect(error == .unauthorized)
            // Dead session — retrying can't help, only re-consent can.
            #expect(!error.isRetryable)
        }
    }

    @Test("token endpoint 5xx stays retryable")
    func tokenServerErrorIsRetryable() async throws {
        defer { OAuthStubProtocol.reset() }
        let session = OAuthStubProtocol.session { request in
            (try OAuthStubProtocol.jsonResponse(for: request, status: 503), Data("{}".utf8))
        }
        let oauth = JiraOAuth(config: Self.makeConfig(), session: session)

        do {
            _ = try await oauth.refresh(refreshToken: "rt-1")
            Issue.record("expected a failure")
        } catch let error as JiraError {
            #expect(error == .server(status: 503))
            #expect(error.isRetryable)
        }
    }

    @Test("mapTokenError maps the OAuth error payload, not Jira's envelope")
    func tokenErrorMapping() {
        func map(_ status: Int, _ json: String) -> JiraError {
            JiraOAuth.mapTokenError(status: status, data: Data(json.utf8))
        }
        #expect(map(403, #"{"error":"invalid_grant"}"#) == .unauthorized)
        #expect(map(400, #"{"error":"invalid_grant"}"#) == .unauthorized)
        #expect(map(401, #"{"error":"invalid_client"}"#) == .unauthorized)
        #expect(map(429, "{}") == .rateLimited(retryAfter: nil))
        #expect(map(500, "{}") == .server(status: 500))
        #expect(map(400, #"{"error":"invalid_request","error_description":"bad redirect_uri"}"#)
                == .api(status: 400, messages: ["bad redirect_uri"]))
    }

    // MARK: - Expiry maths

    @Test("expiresAt comes from expires_in, and tokens go stale five minutes early")
    func expiryMathsLeavesSafetyMargin() async throws {
        defer { OAuthStubProtocol.reset() }
        let session = OAuthStubProtocol.session { request in
            (try OAuthStubProtocol.jsonResponse(for: request, status: 200), Data("""
            {"access_token":"at-1","expires_in":3600,"refresh_token":"rt-1",
             "scope":"read:jira-work offline_access","token_type":"Bearer"}
            """.utf8))
        }
        let oauth = JiraOAuth(config: Self.makeConfig(), session: session)
        let now = Date()
        let tokens = try await oauth.exchange(code: "c")

        // Wire expiry is exact — the margin is applied at check time, not baked in.
        #expect(abs(tokens.expiresAt.timeIntervalSince(now.addingTimeInterval(3600))) < 1)

        #expect(JiraOAuthSession.refreshMargin == 300)
        let sessionModel = JiraOAuthSession(accessToken: "at-1",
                                            refreshToken: "rt-1",
                                            expiresAt: tokens.expiresAt,
                                            cloudID: "c1",
                                            siteURL: "https://wayll.atlassian.net",
                                            scopes: tokens.scopes)

        #expect(!sessionModel.isExpired(asOf: now))
        // 301s before the wire expiry: still fresh.
        #expect(!sessionModel.isExpired(asOf: tokens.expiresAt.addingTimeInterval(-301)))
        // 299s before the wire expiry: already treated as stale.
        #expect(sessionModel.isExpired(asOf: tokens.expiresAt.addingTimeInterval(-299)))
        #expect(sessionModel.isExpired(asOf: tokens.expiresAt))
        #expect(sessionModel.isExpired(asOf: tokens.expiresAt.addingTimeInterval(60)))
    }

    // MARK: - Accessible resources

    @Test("accessibleResources sends the bearer token and parses the site list")
    func accessibleResourcesParsing() async throws {
        defer { OAuthStubProtocol.reset() }
        let session = OAuthStubProtocol.session { request in
            (try OAuthStubProtocol.jsonResponse(for: request, status: 200), Data("""
            [{"id":"cloud-1","url":"https://wayll.atlassian.net","name":"Wayll",
              "scopes":["read:jira-work"],"avatarUrl":"https://example.com/a.png"},
             {"id":"cloud-2","url":"https://other.atlassian.net","name":"Other"}]
            """.utf8))
        }

        let oauth = JiraOAuth(config: Self.makeConfig(), session: session)
        let resources = try await oauth.accessibleResources(accessToken: "at-1")

        let sent = try #require(OAuthStubProtocol.requests.last)
        #expect(sent.method == "GET")
        #expect(sent.url?.absoluteString == "https://api.atlassian.com/oauth/token/accessible-resources")
        #expect(sent.header("Authorization") == "Bearer at-1")

        #expect(resources.count == 2)
        #expect(resources[0].id == "cloud-1")
        #expect(resources[0].url == "https://wayll.atlassian.net")
        #expect(resources[0].name == "Wayll")
        #expect(resources[0].scopes == ["read:jira-work"])
        #expect(resources[0].avatarUrl == "https://example.com/a.png")
        // Optional fields absent — must still decode.
        #expect(resources[1].id == "cloud-2")
        #expect(resources[1].scopes.isEmpty)
        #expect(resources[1].avatarUrl == nil)
    }

    @Test("accessibleResources 401 → unauthorized")
    func accessibleResourcesUnauthorized() async throws {
        defer { OAuthStubProtocol.reset() }
        let session = OAuthStubProtocol.session { request in
            (try OAuthStubProtocol.jsonResponse(for: request, status: 401), Data("{}".utf8))
        }
        let oauth = JiraOAuth(config: Self.makeConfig(), session: session)

        do {
            _ = try await oauth.accessibleResources(accessToken: "stale")
            Issue.record("expected a 401 to fail")
        } catch let error as JiraError {
            #expect(error == .unauthorized)
        }
    }

    // MARK: - Callback parsing (hermetic — no port bound)

    @Test("a matching callback yields the code")
    func callbackHappyPath() throws {
        let outcome = LoopbackCallbackReceiver.callbackOutcome(
            requestText: "GET /callback?code=abc123&state=st-1 HTTP/1.1\r\nHost: localhost:53682\r\n\r\n",
            expectedState: "st-1")
        #expect(outcome == .code("abc123"))
    }

    @Test("a callback whose state doesn't match is rejected")
    func callbackStateMismatchIsRejected() throws {
        // Without this check an attacker could feed us their own code and bind
        // the user's Sharingan to the attacker's Jira account.
        let outcome = LoopbackCallbackReceiver.callbackOutcome(
            requestText: "GET /callback?code=abc123&state=ATTACKER HTTP/1.1\r\n\r\n",
            expectedState: "st-1")
        #expect(outcome == .failure(JiraOAuth.stateMismatchError))
    }

    @Test("a callback with no state at all is rejected")
    func callbackMissingStateIsRejected() throws {
        let outcome = LoopbackCallbackReceiver.callbackOutcome(
            requestText: "GET /callback?code=abc123 HTTP/1.1\r\n\r\n",
            expectedState: "st-1")
        #expect(outcome == .failure(JiraOAuth.stateMismatchError))
    }

    @Test("the user declining consent throws instead of hanging")
    func callbackAccessDenied() throws {
        let outcome = LoopbackCallbackReceiver.callbackOutcome(
            requestText: "GET /callback?error=access_denied&error_description=User%20denied&state=st-1 HTTP/1.1\r\n\r\n",
            expectedState: "st-1")
        #expect(outcome == .failure(.forbidden))
    }

    @Test("other Atlassian error redirects surface their description")
    func callbackOtherError() throws {
        let outcome = LoopbackCallbackReceiver.callbackOutcome(
            requestText: "GET /callback?error=invalid_scope&error_description=Bad%20scope&state=st-1 HTTP/1.1\r\n\r\n",
            expectedState: "st-1")
        #expect(outcome == .failure(.api(status: 400, messages: ["Bad scope"])))
    }

    @Test("a callback with neither code nor error is rejected")
    func callbackWithoutCode() throws {
        let outcome = LoopbackCallbackReceiver.callbackOutcome(
            requestText: "GET /callback?state=st-1 HTTP/1.1\r\n\r\n",
            expectedState: "st-1")
        #expect(outcome != nil)
        #expect(outcome != .code(""))
    }

    @Test("unrelated requests don't end the wait", arguments: [
        "GET /favicon.ico HTTP/1.1\r\n\r\n",
        "POST /callback?code=a&state=st-1 HTTP/1.1\r\n\r\n",
        "GET /other?code=a&state=st-1 HTTP/1.1\r\n\r\n",
        "garbage\r\n\r\n",
    ])
    func callbackIgnoresUnrelatedRequests(request: String) throws {
        // A browser prefetching /favicon.ico must not resume the continuation.
        #expect(LoopbackCallbackReceiver.callbackOutcome(requestText: request, expectedState: "st-1") == nil)
    }

    @Test("the listener times out and releases the port instead of hanging forever")
    func callbackTimesOutAndReleasesPort() async throws {
        let port = Self.randomEphemeralPort()
        let oauth = JiraOAuth(config: Self.makeConfig())

        do {
            _ = try await oauth.awaitCallback(state: "st-1", timeout: 0.4, port: port)
            Issue.record("expected a timeout")
        } catch let error as JiraError {
            #expect(error == JiraOAuth.timeoutError(port))
        }

        // The port must be free again — a leaked listener breaks every retry.
        // NWListener releases the socket asynchronously after cancel, so a
        // moment's grace here separates "still tearing down" (fine) from a real
        // leak (the assertion below) instead of racing the two.
        try? await Task.sleep(nanoseconds: 200_000_000)
        do {
            _ = try await oauth.awaitCallback(state: "st-1", timeout: 0.4, port: port)
            Issue.record("expected a timeout")
        } catch let error as JiraError {
            #expect(error == JiraOAuth.timeoutError(port), "port \(port) was not released")
        }
    }

    /// Ephemeral range, so a test run never fights the real 53682 listener or CI.
    private static func randomEphemeralPort() -> UInt16 {
        // Disjoint from JiraIntegrationTests' 57001...65500 — parallel suites
        // on one range collided on a port once; see the twin comment there.
        UInt16.random(in: 49152...57000)
    }

    // MARK: - Token store

    @Test("JiraTokenStore round-trips a session: save → load → clear")
    func tokenStoreRoundTrip() throws {
        let keychain = FakeKeychain()
        let defaults = try #require(UserDefaults(suiteName: "JiraOAuthTests.roundTrip"))
        defaults.removePersistentDomain(forName: "JiraOAuthTests.roundTrip")
        let store = keychain.makeStore(defaults: defaults)

        #expect(store.load() == nil)

        let expiresAt = Date(timeIntervalSince1970: 1_800_000_000)
        let session = JiraOAuthSession(accessToken: "at-1",
                                       refreshToken: "rt-1",
                                       expiresAt: expiresAt,
                                       cloudID: "cloud-1",
                                       siteURL: "https://wayll.atlassian.net",
                                       scopes: ["read:jira-work", "offline_access"])
        try store.save(session)

        let loaded = try #require(store.load())
        #expect(loaded == session)
        #expect(abs(loaded.expiresAt.timeIntervalSince(expiresAt)) < 0.001)

        store.clear()
        #expect(store.load() == nil)
        #expect(keychain.values.isEmpty)

        defaults.removePersistentDomain(forName: "JiraOAuthTests.roundTrip")
    }

    @Test("the refresh token lands in the keychain and NEVER in UserDefaults")
    func tokenStoreKeepsSecretsOutOfDefaults() throws {
        let keychain = FakeKeychain()
        let suite = "JiraOAuthTests.secrets"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let store = keychain.makeStore(defaults: defaults)

        try store.save(JiraOAuthSession(accessToken: "at-SECRET",
                                        refreshToken: "rt-SECRET",
                                        expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
                                        cloudID: "cloud-1",
                                        siteURL: "https://wayll.atlassian.net",
                                        scopes: ["offline_access"]))

        // Secrets: keychain only.
        #expect(keychain.values[JiraTokenStore.refreshTokenAccount] == "rt-SECRET")
        #expect(keychain.values[JiraTokenStore.accessTokenAccount] == "at-SECRET")

        // No value anywhere in the defaults domain may contain either token.
        let domain = defaults.persistentDomain(forName: suite) ?? [:]
        let dumped = String(describing: domain)
        #expect(!dumped.contains("rt-SECRET"), "refresh token leaked into UserDefaults: \(dumped)")
        #expect(!dumped.contains("at-SECRET"), "access token leaked into UserDefaults: \(dumped)")

        // The non-secret bookkeeping is there, though.
        #expect(defaults.string(forKey: JiraTokenStore.cloudIDDefaultsKey) == "cloud-1")
        #expect(defaults.string(forKey: JiraTokenStore.siteURLDefaultsKey) == "https://wayll.atlassian.net")

        defaults.removePersistentDomain(forName: suite)
    }

    @Test("a half-written session loads as no session rather than a broken one")
    func tokenStorePartialSessionLoadsNil() throws {
        let keychain = FakeKeychain()
        let defaults = try #require(UserDefaults(suiteName: "JiraOAuthTests.partial"))
        defaults.removePersistentDomain(forName: "JiraOAuthTests.partial")
        let store = keychain.makeStore(defaults: defaults)

        try store.save(JiraOAuthSession(accessToken: "at-1",
                                        refreshToken: "rt-1",
                                        expiresAt: Date(),
                                        cloudID: "cloud-1",
                                        siteURL: "https://wayll.atlassian.net",
                                        scopes: []))
        #expect(store.load() != nil)

        // Keychain wiped by the user (e.g. Keychain Access), defaults intact.
        keychain.values.removeValue(forKey: JiraTokenStore.refreshTokenAccount)
        #expect(store.load() == nil)

        defaults.removePersistentDomain(forName: "JiraOAuthTests.partial")
    }

    @Test("clear() removes both keychain accounts and every defaults key")
    func tokenStoreClearIsThorough() throws {
        let keychain = FakeKeychain()
        let suite = "JiraOAuthTests.clear"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let store = keychain.makeStore(defaults: defaults)

        try store.save(JiraOAuthSession(accessToken: "at-1",
                                        refreshToken: "rt-1",
                                        expiresAt: Date(),
                                        cloudID: "cloud-1",
                                        siteURL: "https://wayll.atlassian.net",
                                        scopes: ["offline_access"]))
        store.accountName = "Ada Lovelace"
        #expect(store.accountName == "Ada Lovelace")

        store.clear()

        #expect(keychain.values.isEmpty)
        #expect(store.accountName == nil)
        for key in [JiraTokenStore.expiresAtDefaultsKey,
                    JiraTokenStore.cloudIDDefaultsKey,
                    JiraTokenStore.siteURLDefaultsKey,
                    JiraTokenStore.scopesDefaultsKey] {
            #expect(defaults.object(forKey: key) == nil, "\(key) survived clear()")
        }

        defaults.removePersistentDomain(forName: suite)
    }

    @Test("a keychain that refuses the write surfaces the error")
    func tokenStorePropagatesKeychainFailure() throws {
        let keychain = FakeKeychain()
        keychain.failWrites = true
        let defaults = try #require(UserDefaults(suiteName: "JiraOAuthTests.failure"))
        defaults.removePersistentDomain(forName: "JiraOAuthTests.failure")
        let store = keychain.makeStore(defaults: defaults)

        #expect(throws: (any Error).self) {
            try store.save(JiraOAuthSession(accessToken: "at-1",
                                            refreshToken: "rt-1",
                                            expiresAt: Date(),
                                            cloudID: "cloud-1",
                                            siteURL: "https://wayll.atlassian.net",
                                            scopes: []))
        }
        #expect(store.load() == nil)

        defaults.removePersistentDomain(forName: "JiraOAuthTests.failure")
    }
}

// MARK: - Test doubles

/// In-memory stand-in for `KeychainStore`, keyed by account. Keeps tests off the
/// real login keychain (which would prompt, and would leak between runs).
private final class FakeKeychain: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]
    var failWrites = false

    var values: [String: String] {
        get { lock.lock(); defer { lock.unlock() }; return storage }
        set { lock.lock(); defer { lock.unlock() }; storage = newValue }
    }

    struct WriteRefused: Error {}

    func makeStore(defaults: UserDefaults) -> JiraTokenStore {
        JiraTokenStore(defaults: defaults,
                       keychainService: "test.service",
                       readToken: { [self] _, account in
                           lock.lock(); defer { lock.unlock() }
                           return storage[account]
                       },
                       writeToken: { [self] value, _, account in
                           lock.lock(); defer { lock.unlock() }
                           if failWrites { throw WriteRefused() }
                           storage[account] = value
                       },
                       deleteToken: { [self] _, account in
                           lock.lock(); defer { lock.unlock() }
                           storage.removeValue(forKey: account)
                       })
    }
}

/// The request body as seen from inside a `URLProtocol`.
///
/// URLSession moves `httpBody` into `httpBodyStream` before a custom protocol
/// sees the request, so `httpBody` reads back nil there — the stream must be
/// drained instead, and only once.
private func drainBody(of request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
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

/// One request as it reached the stub, recorded so the test body — not the
/// `URLProtocol` callback — can assert on it.
///
/// `startLoading()` runs on URLSession's queue, outside the test's task-local
/// context, so any `#expect` there is orphaned onto `Test «unknown»` and cannot
/// fail the test. Handlers build responses only; assertions go after the `await`.
private struct RecordedOAuthRequest: @unchecked Sendable {
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

private final class OAuthStubProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var _handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    private static var _requests: [RecordedOAuthRequest] = []

    static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { lock.lock(); defer { lock.unlock() }; return _handler }
        set { lock.lock(); defer { lock.unlock() }; _handler = newValue }
    }

    static var requests: [RecordedOAuthRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        _handler = nil
        _requests = []
    }

    private static func record(_ recorded: RecordedOAuthRequest) {
        lock.lock(); defer { lock.unlock() }
        _requests.append(recorded)
    }

    static func response(for request: URLRequest,
                         status: Int,
                         headers: [String: String] = [:]) throws -> HTTPURLResponse {
        guard let url = request.url else { throw URLError(.badURL) }
        guard let response = HTTPURLResponse(url: url,
                                             statusCode: status,
                                             httpVersion: nil,
                                             headerFields: headers) else {
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

        Self.record(RecordedOAuthRequest(request: request, body: drainBody(of: request)))

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
        configuration.protocolClasses = [OAuthStubProtocol.self]
        return URLSession(configuration: configuration)
    }
}
