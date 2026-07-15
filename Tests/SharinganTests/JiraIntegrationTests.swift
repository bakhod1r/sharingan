import Foundation
import Testing
@testable import SharinganCore

@Suite("Jira integration", .serialized)
struct JiraIntegrationTests {

    @Test("ADF round-trips plain text paragraphs")
    func adfRoundTrip() {
        let text = "First line\n\nSecond line"
        let data = ADF.document(fromPlainText: text)
        #expect(ADF.plainText(from: data) == text)
    }

    @Test("ADF renders mentions and bullet lists")
    func adfRendersRichNodes() throws {
        let payload = """
        {
          "type": "doc",
          "version": 1,
          "content": [
            {
              "type": "paragraph",
              "content": [
                { "type": "mention", "attrs": { "text": "Bakhodir" } },
                { "type": "text", "text": " reviewed this" }
              ]
            },
            {
              "type": "bulletList",
              "content": [
                { "type": "listItem", "content": [{ "type": "paragraph", "content": [{ "type": "text", "text": "One" }] }] },
                { "type": "listItem", "content": [{ "type": "paragraph", "content": [{ "type": "text", "text": "Two" }] }] }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        #expect(ADF.plainText(from: payload) == "@Bakhodir reviewed this\n- One\n- Two")
    }

    // MARK: - Gateway addressing & auth

    @Test("every REST call goes through the OAuth gateway with a bearer token")
    func jiraClientUsesGatewayForREST() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let body = Data(#"{"accountId":"abc123","displayName":"Dev User"}"#.utf8)
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), body)
        }
        let client = JiraClient(tokens: StubTokens(tokens: ["at-1"], cloudId: "cloud-9"),
                                session: session)

        _ = try await client.myself()

        let sent = try #require(TestURLProtocol.requests.last)
        // Under 3LO nothing is addressed at the customer's site host.
        #expect(sent.url?.absoluteString == "https://api.atlassian.com/ex/jira/cloud-9/rest/api/3/myself")
        #expect(sent.header("Authorization") == "Bearer at-1")
        #expect(sent.header("Authorization")?.hasPrefix("Basic") != true)
    }

    @Test("Agile calls go through the gateway too, not the site host")
    func jiraClientUsesGatewayForAgile() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let body = Data(#"{"maxResults":50,"startAt":0,"total":0,"isLast":true,"values":[]}"#.utf8)
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), body)
        }
        let client = JiraClient(tokens: StubTokens(tokens: ["at-1"], cloudId: "cloud-9"),
                                session: session)

        _ = try await client.getBoards()

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.url?.path == "/ex/jira/cloud-9/rest/agile/1.0/board")
        #expect(sent.url?.host == "api.atlassian.com")
        #expect(sent.header("Authorization") == "Bearer at-1")
    }

    @Test("the cloudId prefix is prepended to the path, never assigned over it")
    func gatewayURLPrependsCloudIDPrefix() throws {
        // Regression: `components.path = path` used to overwrite the base URL's
        // path. Harmless when the base had none; here it would silently erase
        // /ex/jira/{cloudId} and aim the request at the gateway root.
        let url = try JiraClient.gatewayURL(cloudID: "cloud-9",
                                            path: "/rest/api/3/issue/SHR-1",
                                            queryItems: [URLQueryItem(name: "fields", value: "summary")])
        #expect(url.absoluteString == "https://api.atlassian.com/ex/jira/cloud-9/rest/api/3/issue/SHR-1?fields=summary")
        #expect(url.path.hasPrefix("/ex/jira/cloud-9/"))
    }

    @Test("a 401 is retried once with a re-fetched token, then gives up")
    func jiraClient401RetriesExactlyOnce() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            (try TestURLProtocol.jsonResponse(for: request, status: 401), Data("{}".utf8))
        }
        let tokens = StubTokens(tokens: ["at-stale", "at-fresh"], cloudId: "cloud-1")
        let client = JiraClient(tokens: tokens, session: session)

        do {
            _ = try await client.myself()
            Issue.record("Expected unauthorized")
        } catch let error as JiraError {
            #expect(error == .unauthorized)
        }

        // Exactly two attempts: one retry, and no refresh loop inside the client.
        #expect(TestURLProtocol.requests.count == 2)
        #expect(tokens.accessTokenCalls == 2)
        #expect(TestURLProtocol.requests.first?.header("Authorization") == "Bearer at-stale")
        #expect(TestURLProtocol.requests.last?.header("Authorization") == "Bearer at-fresh")
    }

    @Test("a 401 that the retry survives returns the retried response")
    func jiraClient401RetrySucceeds() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            if TestURLProtocol.requestCount <= 1 {
                return (try TestURLProtocol.jsonResponse(for: request, status: 401), Data("{}".utf8))
            }
            let body = Data(#"{"accountId":"abc123","displayName":"Dev User"}"#.utf8)
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), body)
        }
        let tokens = StubTokens(tokens: ["at-stale", "at-fresh"], cloudId: "cloud-1")
        let client = JiraClient(tokens: tokens, session: session)

        let myself = try await client.myself()

        #expect(myself.displayName == "Dev User")
        #expect(TestURLProtocol.requests.count == 2)
        #expect(TestURLProtocol.requests.last?.header("Authorization") == "Bearer at-fresh")
    }

    // MARK: - Permission preflight

    @Test("getMyPermissions asks for the preflight keys and reads BROWSE_PROJECTS")
    func jiraClientGetMyPermissions() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let body = Data("""
            {
              "permissions": {
                "BROWSE_PROJECTS": { "id": "10", "key": "BROWSE_PROJECTS", "name": "Browse Projects", "havePermission": true },
                "CREATE_ISSUES": { "id": "11", "key": "CREATE_ISSUES", "name": "Create Issues", "havePermission": false },
                "WORK_ON_ISSUES": { "id": "12", "key": "WORK_ON_ISSUES", "name": "Work On Issues", "havePermission": true }
              }
            }
            """.utf8)
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), body)
        }
        let client = JiraClient(tokens: StubTokens(), session: session)

        let permissions = try await client.getMyPermissions()

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "GET")
        #expect(sent.url?.path == "/ex/jira/cloud-1/rest/api/3/mypermissions")
        let query = try #require(sent.url?.query)
        #expect(query.contains("BROWSE_PROJECTS"))
        #expect(query.contains("CREATE_ISSUES"))
        #expect(query.contains("WORK_ON_ISSUES"))

        #expect(permissions.canBrowseProjects)
        #expect(permissions.has("WORK_ON_ISSUES"))
        #expect(!permissions.has("CREATE_ISSUES"))
        #expect(!permissions.has("ADMINISTER"))
    }

    // MARK: - JiraService: the OAuth flow

    @Test("JiraService connect runs the 3LO flow and stores the session")
    @MainActor
    func jiraServiceConnects() async throws {
        // This test used to assert a Basic header and a site-host URL. Both are
        // wrong facts under 3LO: the token is a bearer, and the site host only
        // survives as a display string.
        defer { TestURLProtocol.reset() }
        let suite = "jira-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let keychain = FakeKeychain()
        let store = keychain.makeStore(defaults: defaults)
        let port = Self.randomEphemeralPort()
        let session = TestURLProtocol.session(handler: Self.oauthFlowHandler(canBrowseProjects: true))

        let opened = URLBox()
        let service = JiraService(defaults: defaults,
                                  store: store,
                                  oauthConfig: Self.testConfig,
                                  oauthSession: session,
                                  apiSession: session,
                                  callbackPort: port,
                                  openURL: { url in
                                      opened.value = url
                                      simulateBrowserCallback(authorizeURL: url, port: port)
                                  },
                                  restoreOnInit: false)

        let success = await service.connect()

        // 1. The consent page the user was sent to.
        let authorizeURL = try #require(opened.value)
        let authorizeComponents = try #require(URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false))
        #expect(authorizeComponents.host == "auth.atlassian.com")
        #expect(authorizeComponents.path == "/authorize")
        let authorizeQuery = try #require(authorizeComponents.queryItems)
        #expect(authorizeQuery.first { $0.name == "client_id" }?.value == "client-abc")
        #expect(authorizeQuery.first { $0.name == "response_type" }?.value == "code")
        #expect(authorizeQuery.first { $0.name == "scope" }?.value?.contains("offline_access") == true)

        // 2. The code exchange.
        let exchange = try #require(TestURLProtocol.requests.first { $0.url?.path == "/oauth/token" })
        #expect(exchange.method == "POST")
        let exchangeBody = try exchange.jsonObject()
        #expect(exchangeBody["grant_type"] as? String == "authorization_code")
        #expect(exchangeBody["code"] as? String == "auth-code-1")
        #expect(exchangeBody["client_secret"] as? String == "secret-xyz")

        // 3. cloudId lookup, then every REST call through the gateway.
        let resources = try #require(TestURLProtocol.requests.first { $0.url?.path == "/oauth/token/accessible-resources" })
        #expect(resources.header("Authorization") == "Bearer at-1")

        let myself = try #require(TestURLProtocol.requests.first { $0.url?.path.hasSuffix("/rest/api/3/myself") == true })
        #expect(myself.url?.absoluteString == "https://api.atlassian.com/ex/jira/cloud-1/rest/api/3/myself")
        #expect(myself.header("Authorization") == "Bearer at-1")

        // Nothing anywhere in the flow speaks Basic any more.
        #expect(TestURLProtocol.requests.allSatisfy { $0.header("Authorization")?.hasPrefix("Basic") != true })

        #expect(success)
        #expect(service.isConnected)
        #expect(service.hasProjectAccess)
        #expect(service.siteHost == "wayll.atlassian.net")
        #expect(service.currentUser?.displayName == "Dev User")
        #expect(service.status == .connected(site: "wayll.atlassian.net",
                                             user: JiraUserIdentity(accountId: "abc123",
                                                                    displayName: "Dev User",
                                                                    emailAddress: "dev@example.com")))

        let saved = try #require(store.load())
        #expect(saved.cloudID == "cloud-1")
        #expect(saved.siteURL == "https://wayll.atlassian.net")
        #expect(saved.refreshToken == "rt-1")
        #expect(keychain.values[JiraTokenStore.refreshTokenAccount] == "rt-1")

        service.disconnect()
        #expect(store.load() == nil)
        #expect(keychain.values[JiraTokenStore.refreshTokenAccount] == nil)
        #expect(service.status == .disconnected)
    }

    @Test("connect surfaces the no-project-access account instead of a cheerful lie")
    @MainActor
    func jiraServiceConnectWithoutBrowsePermission() async throws {
        // Live finding: POST /search/jql for a project the account can't see
        // answers 200 with {"issues":[],"isLast":true}. So without this preflight
        // "connected ✓" plus an empty list is indistinguishable from a bug — and
        // that is exactly what a permissionless user reported.
        defer { TestURLProtocol.reset() }
        let suite = "jira-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = FakeKeychain().makeStore(defaults: defaults)
        let port = Self.randomEphemeralPort()
        let session = TestURLProtocol.session(handler: Self.oauthFlowHandler(canBrowseProjects: false))

        let service = JiraService(defaults: defaults,
                                  store: store,
                                  oauthConfig: Self.testConfig,
                                  oauthSession: session,
                                  apiSession: session,
                                  callbackPort: port,
                                  openURL: { simulateBrowserCallback(authorizeURL: $0, port: port) },
                                  restoreOnInit: false)

        let success = await service.connect()

        #expect(TestURLProtocol.requests.contains { $0.url?.path.hasSuffix("/rest/api/3/mypermissions") == true })
        // The session is real, so this is not a failure…
        #expect(success)
        #expect(service.isConnected)
        // …but it is emphatically not the same state as a working connection.
        #expect(!service.hasProjectAccess)
        #expect(service.status == .noProjectAccess(site: "wayll.atlassian.net",
                                                   user: JiraUserIdentity(accountId: "abc123",
                                                                          displayName: "Dev User",
                                                                          emailAddress: "dev@example.com")))
        #expect(service.status.label == "No project access")
    }

    @Test("connect fails immediately when the build has no OAuth credentials")
    @MainActor
    func jiraServiceConnectWithoutCredentials() async throws {
        defer { TestURLProtocol.reset() }
        let suite = "jira-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let session = TestURLProtocol.session { request in
            (try TestURLProtocol.jsonResponse(for: request, status: 200), Data("{}".utf8))
        }
        let service = JiraService(defaults: defaults,
                                  store: FakeKeychain().makeStore(defaults: defaults),
                                  oauthConfig: nil,
                                  oauthSession: session,
                                  apiSession: session,
                                  openURL: { _ in Issue.record("browser must not open") },
                                  restoreOnInit: false)

        #expect(service.status == .notConfigured)
        #expect(!service.isConfigured)

        let success = await service.connect()

        #expect(!success)
        #expect(service.status == .notConfigured)
        // Fails here, not with a 400 from Atlassian about an unknown client_id.
        #expect(TestURLProtocol.requests.isEmpty)
    }

    @Test("connect surfaces multiple sites instead of guessing one")
    @MainActor
    func jiraServiceConnectWithMultipleSites() async throws {
        defer { TestURLProtocol.reset() }
        let suite = "jira-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = FakeKeychain().makeStore(defaults: defaults)
        let port = Self.randomEphemeralPort()
        let session = TestURLProtocol.session { request in
            switch request.url?.path {
            case "/oauth/token":
                return (try TestURLProtocol.jsonResponse(for: request, status: 200), Self.tokenPayload)
            case "/oauth/token/accessible-resources":
                return (try TestURLProtocol.jsonResponse(for: request, status: 200), Data("""
                [{"id":"cloud-1","url":"https://wayll.atlassian.net","name":"Wayll"},
                 {"id":"cloud-2","url":"https://other.atlassian.net","name":"Other"}]
                """.utf8))
            default:
                return (try TestURLProtocol.response(for: request, status: 404), Data())
            }
        }

        let service = JiraService(defaults: defaults,
                                  store: store,
                                  oauthConfig: Self.testConfig,
                                  oauthSession: session,
                                  apiSession: session,
                                  callbackPort: port,
                                  openURL: { simulateBrowserCallback(authorizeURL: $0, port: port) },
                                  restoreOnInit: false)

        let success = await service.connect()

        // Not connected yet — picking the wrong site silently syncs against
        // someone else's project, so the user chooses.
        #expect(!success)
        #expect(!service.isConnected)
        #expect(store.load() == nil)
        guard case .chooseSite(let resources) = service.status else {
            Issue.record("expected a site choice, got \(service.status)")
            return
        }
        #expect(resources.map(\.id) == ["cloud-1", "cloud-2"])
        #expect(resources.map(\.name) == ["Wayll", "Other"])
        // The same list is what Settings offers later, while connected.
        #expect(service.availableSites.map(\.id) == ["cloud-1", "cloud-2"])
    }

    // MARK: - Switching site while connected

    @Test("switchSite re-aims subsequent requests at the new cloudId, with no re-auth")
    @MainActor
    func jiraServiceSwitchSiteChangesCloudID() async throws {
        defer { TestURLProtocol.reset() }
        let suite = "jira-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = FakeKeychain().makeStore(defaults: defaults)
        let port = Self.randomEphemeralPort()
        let session = TestURLProtocol.session(handler: Self.multiSiteHandler())
        let service = JiraService(defaults: defaults,
                                  store: store,
                                  oauthConfig: Self.testConfig,
                                  oauthSession: session,
                                  apiSession: session,
                                  callbackPort: port,
                                  openURL: { simulateBrowserCallback(authorizeURL: $0, port: port) },
                                  restoreOnInit: false)

        _ = await service.connect()
        let sites = service.availableSites
        #expect(await service.selectSite(try #require(sites.first)))
        #expect(service.siteHost == "wayll.atlassian.net")
        #expect(service.activeSiteID == "cloud-1")

        TestURLProtocol.clearRequests()
        let switched = await service.switchSite(try #require(sites.last))

        #expect(switched)
        #expect(service.hasProjectAccess)
        // The real behaviour: the wire, not just a property.
        let myself = try #require(TestURLProtocol.requests.first { $0.url?.path.hasSuffix("/rest/api/3/myself") == true })
        #expect(myself.url?.absoluteString == "https://api.atlassian.com/ex/jira/cloud-2/rest/api/3/myself")
        #expect(TestURLProtocol.requests.allSatisfy { $0.url?.path.hasPrefix("/ex/jira/cloud-1/") != true })
        // Permissions are per-site, so the preflight has to run again.
        #expect(TestURLProtocol.requests.contains {
            $0.url?.host == "api.atlassian.com"
                && $0.url?.path == "/ex/jira/cloud-2/rest/api/3/mypermissions"
        })
        // One grant covers every site: switching must cost neither a refresh nor
        // a trip back to the consent page.
        #expect(!TestURLProtocol.requests.contains { $0.url?.path == "/oauth/token" })

        // Display follows the active session.
        #expect(service.siteHost == "other.atlassian.net")
        #expect(service.activeSiteID == "cloud-2")

        // Persisted, and the same after a cold restore.
        let saved = try #require(store.load())
        #expect(saved.cloudID == "cloud-2")
        #expect(saved.siteURL == "https://other.atlassian.net")
        #expect(saved.refreshToken == "rt-1")

        let restored = JiraService(defaults: defaults,
                                   store: store,
                                   oauthConfig: Self.testConfig,
                                   oauthSession: session,
                                   apiSession: session,
                                   openURL: { _ in Issue.record("restore must not open a browser") },
                                   restoreOnInit: false)
        await restored.restore()
        #expect(restored.siteHost == "other.atlassian.net")
        #expect(restored.activeSiteID == "cloud-2")
        #expect(restored.availableSites.map(\.id) == ["cloud-1", "cloud-2"])
    }

    @Test("switching to a site the account can't browse lands in no-project-access")
    @MainActor
    func jiraServiceSwitchSiteWithoutBrowsePermission() async throws {
        defer { TestURLProtocol.reset() }
        let suite = "jira-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let port = Self.randomEphemeralPort()
        let session = TestURLProtocol.session(handler: Self.multiSiteHandler(canBrowseOnCloud2: false))
        let service = JiraService(defaults: defaults,
                                  store: FakeKeychain().makeStore(defaults: defaults),
                                  oauthConfig: Self.testConfig,
                                  oauthSession: session,
                                  apiSession: session,
                                  callbackPort: port,
                                  openURL: { simulateBrowserCallback(authorizeURL: $0, port: port) },
                                  restoreOnInit: false)

        _ = await service.connect()
        let sites = service.availableSites
        _ = await service.selectSite(try #require(sites.first))
        #expect(service.hasProjectAccess)

        let switched = await service.switchSite(try #require(sites.last))

        // OAuth reaches the site; Jira still won't show it a single project.
        #expect(!switched)
        #expect(service.isConnected)
        #expect(!service.hasProjectAccess)
        #expect(service.status == .noProjectAccess(site: "other.atlassian.net",
                                                   user: JiraUserIdentity(accountId: "abc123",
                                                                          displayName: "Dev User",
                                                                          emailAddress: "dev@example.com")))
    }

    @Test("switching sites drops cached issues belonging to the old site")
    @MainActor
    func jiraServiceSwitchSitePurgesForeignCache() async throws {
        defer { TestURLProtocol.reset() }
        let suite = "jira-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("jira-switch-\(UUID().uuidString).sqlite").path
        let storage = try #require(JiraStorage(path: path))
        defer { try? FileManager.default.removeItem(atPath: path) }
        // Same key, two sites — exactly the collision that makes a stale row a
        // lie rather than merely stale.
        storage.upsertIssue(CachedJiraIssue(issueID: "1", issueKey: "SHR-1",
                                            siteHost: "wayll.atlassian.net", summary: "Old site"))
        storage.upsertIssue(CachedJiraIssue(issueID: "2", issueKey: "SHR-1",
                                            siteHost: "other.atlassian.net", summary: "New site"))

        let port = Self.randomEphemeralPort()
        let session = TestURLProtocol.session(handler: Self.multiSiteHandler())
        let service = JiraService(defaults: defaults,
                                  store: FakeKeychain().makeStore(defaults: defaults),
                                  oauthConfig: Self.testConfig,
                                  oauthSession: session,
                                  apiSession: session,
                                  callbackPort: port,
                                  openURL: { simulateBrowserCallback(authorizeURL: $0, port: port) },
                                  issueCache: storage,
                                  restoreOnInit: false)

        _ = await service.connect()
        let sites = service.availableSites
        _ = await service.selectSite(try #require(sites.first))
        // Connecting to wayll already evicts the other site's row.
        #expect(storage.allIssues().map(\.issueID) == ["1"])

        _ = await service.switchSite(try #require(sites.last))

        // Nothing from wayll may now answer to a lookup on the new site.
        #expect(storage.allIssues().isEmpty)
        #expect(storage.issue(key: "SHR-1") == nil)
    }

    @Test("a single-site account has nothing to pick between")
    @MainActor
    func jiraServiceSingleSiteHasNoPicker() async throws {
        defer { TestURLProtocol.reset() }
        let suite = "jira-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let port = Self.randomEphemeralPort()
        let session = TestURLProtocol.session(handler: Self.oauthFlowHandler(canBrowseProjects: true))
        let service = JiraService(defaults: defaults,
                                  store: FakeKeychain().makeStore(defaults: defaults),
                                  oauthConfig: Self.testConfig,
                                  oauthSession: session,
                                  apiSession: session,
                                  callbackPort: port,
                                  openURL: { simulateBrowserCallback(authorizeURL: $0, port: port) },
                                  restoreOnInit: false)

        #expect(await service.connect())

        // Settings keys the picker off this count: one site, one read-only row.
        #expect(service.availableSites.map(\.id) == ["cloud-1"])
        #expect(service.activeSiteID == "cloud-1")
        // Switching to the site already in use is a no-op, not a round-trip.
        let before = TestURLProtocol.requests.count
        #expect(await service.switchSite(try #require(service.availableSites.first)))
        #expect(TestURLProtocol.requests.count == before)
    }

    // MARK: - The refresh hazard

    @Test("concurrent accessToken() callers trigger exactly ONE refresh")
    @MainActor
    func refreshIsSingleFlight() async throws {
        // Atlassian rotates refresh tokens: a second concurrent refresh presents
        // a token the first already spent, gets invalid_grant, and logs the user
        // out. N waiters must share one refresh.
        defer { TestURLProtocol.reset() }
        let suite = "jira-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let session = TestURLProtocol.session { request in
            // Hold the refresh open long enough for every caller to pile up on
            // it — without this the race the test is about can't happen.
            Thread.sleep(forTimeInterval: 0.05)
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), Data("""
            {"access_token":"at-NEW","expires_in":3600,"refresh_token":"rt-ROTATED",
             "scope":"read:jira-work offline_access","token_type":"Bearer"}
            """.utf8))
        }

        let keychain = FakeKeychain()
        let store = keychain.makeStore(defaults: defaults)
        try store.save(JiraOAuthSession(accessToken: "at-OLD",
                                        refreshToken: "rt-OLD",
                                        expiresAt: Date().addingTimeInterval(-10),
                                        cloudID: "cloud-1",
                                        siteURL: "https://wayll.atlassian.net",
                                        scopes: ["read:jira-work", "offline_access"]))

        let service = JiraService(defaults: defaults,
                                  store: store,
                                  oauthConfig: Self.testConfig,
                                  oauthSession: session,
                                  apiSession: session,
                                  restoreOnInit: false)

        let results: [String?] = await withTaskGroup(of: String?.self) { group in
            for _ in 0..<10 {
                group.addTask { try? await service.accessToken() }
            }
            var collected: [String?] = []
            for await token in group { collected.append(token) }
            return collected
        }

        #expect(results.count == 10)
        #expect(results.allSatisfy { $0 == "at-NEW" })

        let refreshes = TestURLProtocol.requests.filter {
            $0.url?.absoluteString == "https://auth.atlassian.com/oauth/token"
        }
        #expect(refreshes.count == 1,
                "10 concurrent callers must share one refresh — a second would invalidate the first's rotated token")
        let refreshBody = try #require(refreshes.first).jsonObject()
        #expect(refreshBody["grant_type"] as? String == "refresh_token")
        #expect(refreshBody["refresh_token"] as? String == "rt-OLD")

        // The rotated token is persisted, or the next launch is logged out.
        #expect(store.load()?.refreshToken == "rt-ROTATED")
        #expect(keychain.values[JiraTokenStore.refreshTokenAccount] == "rt-ROTATED")
    }

    @Test("a fresh token needs no refresh at all")
    @MainActor
    func liveTokenIsNotRefreshed() async throws {
        defer { TestURLProtocol.reset() }
        let suite = "jira-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let session = TestURLProtocol.session { request in
            (try TestURLProtocol.jsonResponse(for: request, status: 200), Data("{}".utf8))
        }
        let store = FakeKeychain().makeStore(defaults: defaults)
        try store.save(JiraOAuthSession(accessToken: "at-LIVE",
                                        refreshToken: "rt-1",
                                        expiresAt: Date().addingTimeInterval(3600),
                                        cloudID: "cloud-1",
                                        siteURL: "https://wayll.atlassian.net",
                                        scopes: []))

        let service = JiraService(defaults: defaults,
                                  store: store,
                                  oauthConfig: Self.testConfig,
                                  oauthSession: session,
                                  apiSession: session,
                                  restoreOnInit: false)

        #expect(try await service.accessToken() == "at-LIVE")
        #expect(try await service.cloudID() == "cloud-1")
        #expect(TestURLProtocol.requests.isEmpty)
    }

    @Test("invalid_grant on refresh clears the session and asks for re-consent")
    @MainActor
    func deadRefreshTokenNeedsReconsent() async throws {
        defer { TestURLProtocol.reset() }
        let suite = "jira-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let session = TestURLProtocol.session { request in
            (try TestURLProtocol.jsonResponse(for: request, status: 400), Data("""
            {"error":"invalid_grant","error_description":"Unknown or invalid refresh token."}
            """.utf8))
        }
        let keychain = FakeKeychain()
        let store = keychain.makeStore(defaults: defaults)
        try store.save(JiraOAuthSession(accessToken: "at-OLD",
                                        refreshToken: "rt-DEAD",
                                        expiresAt: Date().addingTimeInterval(-10),
                                        cloudID: "cloud-1",
                                        siteURL: "https://wayll.atlassian.net",
                                        scopes: []))

        let service = JiraService(defaults: defaults,
                                  store: store,
                                  oauthConfig: Self.testConfig,
                                  oauthSession: session,
                                  apiSession: session,
                                  restoreOnInit: false)

        do {
            _ = try await service.accessToken()
            Issue.record("expected a dead refresh token to fail")
        } catch let error as JiraError {
            #expect(error == .unauthorized)
            // Not retryable: only the user re-consenting can fix this.
            #expect(!error.isRetryable)
        }

        // The dead session is gone rather than lingering as a half-broken one.
        #expect(store.load() == nil)
        #expect(keychain.values[JiraTokenStore.refreshTokenAccount] == nil)

        // The state must be distinct from a transient error so the UI can offer
        // "Log in again" rather than a toast the user can only stare at.
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(service.status == .reconsentRequired)
        #expect(service.status.label == "Sign-in expired")
    }

    @Test("restore brings a stored session back without a browser round-trip")
    @MainActor
    func jiraServiceRestoresStoredSession() async throws {
        defer { TestURLProtocol.reset() }
        let suite = "jira-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let session = TestURLProtocol.session(handler: Self.oauthFlowHandler(canBrowseProjects: true))
        let store = FakeKeychain().makeStore(defaults: defaults)
        try store.save(JiraOAuthSession(accessToken: "at-1",
                                        refreshToken: "rt-1",
                                        expiresAt: Date().addingTimeInterval(3600),
                                        cloudID: "cloud-1",
                                        siteURL: "https://wayll.atlassian.net",
                                        scopes: []))

        let service = JiraService(defaults: defaults,
                                  store: store,
                                  oauthConfig: Self.testConfig,
                                  oauthSession: session,
                                  apiSession: session,
                                  openURL: { _ in Issue.record("restore must not open a browser") },
                                  restoreOnInit: false)
        await service.restore()

        #expect(service.isConnected)
        #expect(service.hasProjectAccess)
        #expect(service.siteHost == "wayll.atlassian.net")
        #expect(TestURLProtocol.requests.allSatisfy { $0.url?.host == "api.atlassian.com" })
    }

    @Test("the pre-OAuth site/email defaults and API token are purged on init")
    @MainActor
    func legacyBasicAuthCredentialsArePurged() async throws {
        let suite = "jira-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("https://example.atlassian.net", forKey: JiraService.legacySiteURLDefaultsKey)
        defaults.set("dev@example.com", forKey: JiraService.legacyEmailDefaultsKey)

        let deleted = DeletionLog()
        _ = JiraService(defaults: defaults,
                        store: FakeKeychain().makeStore(defaults: defaults),
                        oauthConfig: nil,
                        restoreOnInit: false,
                        legacyDeleteToken: { service, account in
                            deleted.append("\(service)|\(account)")
                        })

        #expect(defaults.string(forKey: JiraService.legacySiteURLDefaultsKey) == nil)
        #expect(defaults.string(forKey: JiraService.legacyEmailDefaultsKey) == nil)
        // The old API token is keyed by site host; nothing reads it any more, so
        // it has no business staying in the keychain.
        #expect(deleted.entries == ["\(JiraService.legacyKeychainService)|example.atlassian.net"])
    }

    // MARK: - Endpoints

    @Test("JiraClient maps rate limits")
    func jiraClientMapsRateLimit() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let response = try TestURLProtocol.response(for: request,
                                                        status: 429,
                                                        headers: ["Retry-After": "60"])
            let body = #"{"errorMessages":["Slow down"]}"#.data(using: .utf8)!
            return (response, body)
        }
        let client = JiraClient(tokens: StubTokens(), session: session)

        do {
            _ = try await client.myself()
            Issue.record("Expected rate limit error")
        } catch let error as JiraError {
            #expect(error == .rateLimited(retryAfter: 60))
        }
    }

    @Test("JiraClient searchJQL uses POST with nextPageToken pagination")
    func jiraClientSearchJQL() async throws {
        defer { TestURLProtocol.reset() }
        let firstPage = """
        {
          "issues": [
            {
              "id": "10001",
              "key": "SHR-1",
              "self": "https://example.atlassian.net/rest/api/3/issue/10001",
              "fields": {
                "summary": "Test issue",
                "status": { "name": "In Progress", "statusCategory": { "key": "indeterminate" } },
                "priority": { "name": "High" },
                "labels": ["bug", "urgent"],
                "duedate": "2025-12-31",
                "timeoriginalestimate": 7200,
                "description": { "type": "doc", "version": 1, "content": [] },
                "project": { "key": "SHR", "name": "Sharingan" },
                "issuetype": { "name": "Task" },
                "components": [{ "name": "Backend" }],
                "updated": "2025-01-15T10:00:00.000+0000"
              }
            }
          ],
          "nextPageToken": "abc123"
        }
        """.data(using: .utf8)!
        let secondPage = """
        {
          "issues": [
            {
              "id": "10002",
              "key": "SHR-2",
              "self": "https://example.atlassian.net/rest/api/3/issue/10002",
              "fields": {
                "summary": "Second page issue",
                "status": { "name": "To Do", "statusCategory": { "key": "new" } },
                "project": { "key": "SHR", "name": "Sharingan" },
                "issuetype": { "name": "Task" },
                "updated": "2025-01-15T10:00:00.000+0000"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let session = TestURLProtocol.session { request in
            let page = TestURLProtocol.requestCount <= 1 ? firstPage : secondPage
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), page)
        }
        let client = JiraClient(tokens: StubTokens(), session: session)

        let jql = "assignee = currentUser() AND statusCategory != Done"
        let result = try await client.searchJQL(jql: jql, maxResults: 50, nextPageToken: nil)
        let page2 = try await client.searchJQL(jql: jql, maxResults: 50, nextPageToken: result.nextPageToken)

        let requests = TestURLProtocol.requests
        #expect(requests.count == 2)

        let first = try #require(requests.first)
        #expect(first.method == "POST")
        #expect(first.url?.path == "/ex/jira/cloud-1/rest/api/3/search/jql")
        #expect(first.header("Content-Type") == "application/json")
        let firstBody = try first.jsonObject()
        #expect(firstBody["jql"] as? String == jql)
        #expect(firstBody["maxResults"] as? Int == 50)
        #expect(firstBody["nextPageToken"] == nil)

        let second = try #require(requests.last)
        #expect(second.method == "POST")
        #expect(second.url?.path == "/ex/jira/cloud-1/rest/api/3/search/jql")
        let secondBody = try second.jsonObject()
        #expect(secondBody["jql"] as? String == jql)
        #expect(secondBody["nextPageToken"] as? String == "abc123")

        #expect(result.issues.count == 1)
        #expect(result.issues[0].key == "SHR-1")
        #expect(result.issues[0].id == "10001")
        #expect(result.issues[0].fields.summary == "Test issue")
        #expect(result.issues[0].fields.status?.name == "In Progress")
        #expect(result.issues[0].fields.priority?.name == "High")
        #expect(result.issues[0].fields.labels == ["bug", "urgent"])
        #expect(result.issues[0].fields.duedate == "2025-12-31")
        #expect(result.issues[0].fields.timeoriginalestimate == 7200)
        #expect(result.nextPageToken == "abc123")

        #expect(page2.issues.map(\.key) == ["SHR-2"])
        #expect(page2.nextPageToken == nil)
    }

    @Test("JiraClient getIssue fetches full issue with editmeta")
    func jiraClientGetIssue() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let responseBody = """
            {
              "id": "10001",
              "key": "SHR-1",
              "self": "https://example.atlassian.net/rest/api/3/issue/10001",
              "fields": {
                "summary": "Test issue",
                "status": { "name": "In Progress", "statusCategory": { "key": "indeterminate" } },
                "priority": { "name": "High" },
                "labels": ["bug"],
                "duedate": "2025-12-31",
                "timeoriginalestimate": 7200,
                "description": { "type": "doc", "version": 1, "content": [] },
                "project": { "key": "SHR", "name": "Sharingan" },
                "issuetype": { "name": "Task" },
                "components": [{ "name": "Backend" }],
                "updated": "2025-01-15T10:00:00.000+0000"
              },
              "editmeta": {
                "fields": {
                  "summary": { "required": true, "schema": { "type": "string" } },
                  "description": { "required": false, "schema": { "type": "string" } },
                  "priority": { "required": false, "schema": { "type": "priority" } },
                  "labels": { "required": false, "schema": { "type": "array", "items": "string" } },
                  "duedate": { "required": false, "schema": { "type": "date" } },
                  "timeoriginalestimate": { "required": false, "schema": { "type": "timetracking" } }
                }
              }
            }
            """.data(using: .utf8)!
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), responseBody)
        }
        let client = JiraClient(tokens: StubTokens(), session: session)

        let issue = try await client.getIssue(key: "SHR-1")

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "GET")
        #expect(sent.url?.path == "/ex/jira/cloud-1/rest/api/3/issue/SHR-1")

        #expect(issue.id == "10001")
        #expect(issue.key == "SHR-1")
        #expect(issue.fields.summary == "Test issue")
        #expect(issue.fields.status?.name == "In Progress")
        // Jira spells it `editmeta`, all lowercase.
        #expect(issue.editMeta?.fields["summary"]?.required == true)
        #expect(issue.editMeta?.fields["priority"]?.schema.type == "priority")
    }

    @Test("JiraClient updateIssue sends PUT with fields")
    func jiraClientUpdateIssue() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            (try TestURLProtocol.response(for: request, status: 204), Data())
        }
        let client = JiraClient(tokens: StubTokens(), session: session)

        let fields = JiraIssueUpdateFields(
            summary: "Updated summary",
            description: try JSONDecoder().decode(JiraADFDocument.self, from: ADF.document(fromPlainText: "New description")),
            priority: JiraPriorityInput(id: "3"),
            labels: ["bug", "frontend"],
            duedate: "2025-12-31",
            timeoriginalestimate: 3600
        )
        try await client.updateIssue(key: "SHR-1", fields: fields)

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "PUT")
        #expect(sent.url?.path == "/ex/jira/cloud-1/rest/api/3/issue/SHR-1")

        let body = try sent.jsonObject()
        let fieldsDict = try #require(body["fields"] as? [String: Any])
        #expect(fieldsDict["summary"] as? String == "Updated summary")
        #expect((fieldsDict["description"] as? [String: Any])?["type"] as? String == "doc")
        #expect((fieldsDict["priority"] as? [String: Any])?["id"] as? String == "3")
        #expect(fieldsDict["labels"] as? [String] == ["bug", "frontend"])
        #expect(fieldsDict["duedate"] as? String == "2025-12-31")
        #expect(fieldsDict["timeoriginalestimate"] as? Int == 3600)
    }

    @Test("JiraClient getTransitions returns available transitions")
    func jiraClientGetTransitions() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let responseBody = """
            {
              "transitions": [
                { "id": "21", "name": "In Progress", "to": { "name": "In Progress", "statusCategory": { "key": "indeterminate" } } },
                { "id": "31", "name": "Code Review", "to": { "name": "Code Review", "statusCategory": { "key": "indeterminate" } } },
                { "id": "41", "name": "Done", "to": { "name": "Done", "statusCategory": { "key": "done" } } }
              ]
            }
            """.data(using: .utf8)!
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), responseBody)
        }
        let client = JiraClient(tokens: StubTokens(), session: session)

        let transitions = try await client.getTransitions(issueKey: "SHR-1")

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "GET")
        #expect(sent.url?.path == "/ex/jira/cloud-1/rest/api/3/issue/SHR-1/transitions")

        #expect(transitions.count == 3)
        #expect(transitions[0].id == "21")
        #expect(transitions[0].name == "In Progress")
        #expect(transitions[0].to.statusCategory.key == "indeterminate")
        #expect(transitions[2].to.statusCategory.key == "done")
    }

    @Test("JiraClient doTransition posts transition ID")
    func jiraClientDoTransition() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            (try TestURLProtocol.response(for: request, status: 204), Data())
        }
        let client = JiraClient(tokens: StubTokens(), session: session)

        try await client.doTransition(issueKey: "SHR-1", transitionId: "31")

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "POST")
        #expect(sent.url?.path == "/ex/jira/cloud-1/rest/api/3/issue/SHR-1/transitions")

        let body = try sent.jsonObject()
        let transition = try #require(body["transition"] as? [String: Any])
        #expect(transition["id"] as? String == "31")
    }

    @Test("JiraClient addComment posts comment body as ADF")
    func jiraClientAddComment() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let responseBody = """
            {
              "id": "10001",
              "self": "https://example.atlassian.net/rest/api/3/issue/10001/comment/10001",
              "body": { "type": "doc", "version": 1, "content": [{ "type": "paragraph", "content": [{ "type": "text", "text": "Test comment" }] }] },
              "author": { "accountId": "abc", "displayName": "Dev User" },
              "created": "2025-01-15T10:00:00.000+0000",
              "updated": "2025-01-15T10:00:00.000+0000"
            }
            """.data(using: .utf8)!
            return (try TestURLProtocol.jsonResponse(for: request, status: 201), responseBody)
        }
        let client = JiraClient(tokens: StubTokens(), session: session)

        let comment = try await client.addComment(issueKey: "SHR-1", body: "Test comment")

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "POST")
        #expect(sent.url?.path == "/ex/jira/cloud-1/rest/api/3/issue/SHR-1/comment")

        let body = try sent.jsonObject()
        let bodyDict = try #require(body["body"] as? [String: Any])
        #expect(bodyDict["type"] as? String == "doc")
        #expect(comment.id == "10001")
        #expect(comment.plainTextBody == "Test comment")
    }

    @Test("JiraClient getComments returns paginated comments")
    func jiraClientGetComments() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let responseBody = """
            {
              "startAt": 0,
              "maxResults": 20,
              "total": 1,
              "comments": [
                {
                  "id": "10001",
                  "self": "https://example.atlassian.net/rest/api/3/issue/10001/comment/10001",
                  "body": { "type": "doc", "version": 1, "content": [{ "type": "paragraph", "content": [{ "type": "text", "text": "Test comment" }] }] },
                  "author": { "accountId": "abc", "displayName": "Dev User" },
                  "created": "2025-01-15T10:00:00.000+0000",
                  "updated": "2025-01-15T10:00:00.000+0000"
                }
              ]
            }
            """.data(using: .utf8)!
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), responseBody)
        }
        let client = JiraClient(tokens: StubTokens(), session: session)

        let result = try await client.getComments(issueKey: "SHR-1")

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "GET")
        #expect(sent.url?.path == "/ex/jira/cloud-1/rest/api/3/issue/SHR-1/comment")

        #expect(result.comments.count == 1)
        #expect(result.comments[0].id == "10001")
        #expect(result.comments[0].plainTextBody == "Test comment")
        #expect(result.comments[0].author.displayName == "Dev User")
    }

    @Test("JiraClient getChangelog returns history")
    func jiraClientGetChangelog() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let responseBody = """
            {
              "startAt": 0,
              "maxResults": 100,
              "total": 1,
              "histories": [
                {
                  "id": "10001",
                  "author": { "accountId": "abc", "displayName": "Dev User" },
                  "created": "2025-01-15T10:00:00.000+0000",
                  "items": [
                    { "field": "status", "fieldtype": "jira", "from": "10001", "fromString": "To Do", "to": "3", "toString": "In Progress" }
                  ]
                }
              ]
            }
            """.data(using: .utf8)!
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), responseBody)
        }
        let client = JiraClient(tokens: StubTokens(), session: session)

        let result = try await client.getChangelog(issueKey: "SHR-1")

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "GET")
        #expect(sent.url?.path == "/ex/jira/cloud-1/rest/api/3/issue/SHR-1/changelog")

        #expect(result.histories.count == 1)
        #expect(result.histories[0].id == "10001")
        #expect(result.histories[0].items[0].field == "status")
        #expect(result.histories[0].items[0].fromString == "To Do")
        #expect(result.histories[0].items[0].toString == "In Progress")
    }

    @Test("JiraClient addWorklog posts worklog with adjustEstimate=auto")
    func jiraClientAddWorklog() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let responseBody = """
            {
              "id": "10001",
              "self": "https://example.atlassian.net/rest/api/3/issue/10001/worklog/10001",
              "author": { "accountId": "abc", "displayName": "Dev User" },
              "comment": { "type": "doc", "version": 1, "content": [{ "type": "paragraph", "content": [{ "type": "text", "text": "Focus session from Sharingan 🍅" }] }] },
              "started": "2025-01-15T10:00:00.000+0000",
              "timeSpent": "1500",
              "timeSpentSeconds": 1500,
              "updated": "2025-01-15T10:00:00.000+0000"
            }
            """.data(using: .utf8)!
            return (try TestURLProtocol.jsonResponse(for: request, status: 201), responseBody)
        }
        let client = JiraClient(tokens: StubTokens(), session: session)

        let worklog = try await client.addWorklog(
            issueKey: "SHR-1",
            timeSpentSeconds: 1500,
            started: "2025-01-15T10:00:00.000+0000",
            comment: "Focus session from Sharingan 🍅"
        )

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "POST")
        #expect(sent.url?.path == "/ex/jira/cloud-1/rest/api/3/issue/SHR-1/worklog")
        // Jira reads adjustEstimate off the query string; in the body it is ignored.
        #expect(sent.url?.query?.contains("adjustEstimate=auto") == true)

        let body = try sent.jsonObject()
        #expect(body["adjustEstimate"] == nil)
        #expect(body["timeSpentSeconds"] as? Int == 1500)
        #expect(body["started"] as? String == "2025-01-15T10:00:00.000+0000")
        let comment = try #require(body["comment"] as? [String: Any])
        #expect(comment["type"] as? String == "doc")
        #expect(worklog.id == "10001")
        #expect(worklog.timeSpentSeconds == 1500)
    }

    @Test("JiraClient getWorklogs returns worklogs")
    func jiraClientGetWorklogs() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let responseBody = """
            {
              "startAt": 0,
              "maxResults": 20,
              "total": 1,
              "worklogs": [
                {
                  "id": "10001",
                  "self": "https://example.atlassian.net/rest/api/3/issue/10001/worklog/10001",
                  "author": { "accountId": "abc", "displayName": "Dev User" },
                  "comment": { "type": "doc", "version": 1, "content": [{ "type": "paragraph", "content": [{ "type": "text", "text": "Focus session" }] }] },
                  "started": "2025-01-15T10:00:00.000+0000",
                  "timeSpent": "1500",
                  "timeSpentSeconds": 1500,
                  "updated": "2025-01-15T10:00:00.000+0000"
                }
              ]
            }
            """.data(using: .utf8)!
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), responseBody)
        }
        let client = JiraClient(tokens: StubTokens(), session: session)

        let result = try await client.getWorklogs(issueKey: "SHR-1")

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "GET")
        #expect(sent.url?.path == "/ex/jira/cloud-1/rest/api/3/issue/SHR-1/worklog")

        #expect(result.worklogs.count == 1)
        #expect(result.worklogs[0].id == "10001")
        #expect(result.worklogs[0].timeSpentSeconds == 1500)
    }

    @Test("JiraClient getProjects returns projects")
    func jiraClientGetProjects() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let responseBody = """
            {
              "startAt": 0,
              "maxResults": 50,
              "total": 2,
              "isLast": true,
              "values": [
                { "id": "10000", "key": "SHR", "name": "Sharingan", "projectTypeKey": "software" },
                { "id": "10001", "key": "DEV", "name": "Development", "projectTypeKey": "software" }
              ]
            }
            """.data(using: .utf8)!
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), responseBody)
        }
        let client = JiraClient(tokens: StubTokens(), session: session)

        let projects = try await client.getProjects()

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "GET")
        // /project/search, not the deprecated /project.
        #expect(sent.url?.path == "/ex/jira/cloud-1/rest/api/3/project/search")

        #expect(projects.values.count == 2)
        #expect(projects.values[0].key == "SHR")
        #expect(projects.values[0].name == "Sharingan")
        #expect(projects.values[1].key == "DEV")
    }

    @Test("JiraClient getIssueTypes returns issue types for project")
    func jiraClientGetIssueTypes() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let responseBody = """
            [
              { "id": "10001", "name": "Task", "description": "A task", "iconUrl": "https://...", "subtask": false },
              { "id": "10002", "name": "Bug", "description": "A bug", "iconUrl": "https://...", "subtask": false },
              { "id": "10003", "name": "Sub-task", "description": "A subtask", "iconUrl": "https://...", "subtask": true }
            ]
            """.data(using: .utf8)!
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), responseBody)
        }
        let client = JiraClient(tokens: StubTokens(), session: session)

        let types = try await client.getIssueTypes(projectId: "10000")

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "GET")
        #expect(sent.url?.path == "/ex/jira/cloud-1/rest/api/3/issuetype/project")
        // The numeric project id — a project key is rejected with a 400.
        #expect(sent.url?.query?.contains("projectId=10000") == true)

        #expect(types.values.count == 3)
        #expect(types.values[0].name == "Task")
        #expect(types.values[0].subtask == false)
        #expect(types.values[2].name == "Sub-task")
        #expect(types.values[2].subtask == true)
    }

    @Test("JiraClient getEditMeta returns edit metadata for issue")
    func jiraClientGetEditMeta() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let responseBody = """
            {
              "fields": {
                "summary": { "required": true, "schema": { "type": "string" } },
                "description": { "required": false, "schema": { "type": "string" } },
                "priority": { "required": false, "schema": { "type": "priority", "allowedValues": [{ "id": "1", "name": "Highest" }, { "id": "2", "name": "High" }, { "id": "3", "name": "Medium" }] } },
                "labels": { "required": false, "schema": { "type": "array", "items": "string" } },
                "duedate": { "required": false, "schema": { "type": "date" } }
              }
            }
            """.data(using: .utf8)!
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), responseBody)
        }
        let client = JiraClient(tokens: StubTokens(), session: session)

        let editMeta = try await client.getEditMeta(issueKey: "SHR-1")

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "GET")
        #expect(sent.url?.path == "/ex/jira/cloud-1/rest/api/3/issue/SHR-1/editmeta")

        #expect(editMeta.fields["summary"]?.required == true)
        #expect(editMeta.fields["priority"]?.schema.type == "priority")
        #expect(editMeta.fields["priority"]?.schema.allowedValues?.count == 3)
        #expect(editMeta.fields["labels"]?.schema.items == "string")
    }

    @Test("JiraClient Agile API - getBoards returns boards")
    func jiraClientGetBoards() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let responseBody = """
            {
              "maxResults": 50,
              "startAt": 0,
              "total": 1,
              "isLast": true,
              "values": [
                { "id": 1, "name": "Sharingan Board", "type": "scrum", "location": { "projectId": 10000, "displayName": "Sharingan" } }
              ]
            }
            """.data(using: .utf8)!
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), responseBody)
        }
        let client = JiraClient(tokens: StubTokens(), session: session)

        let result = try await client.getBoards()

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "GET")
        #expect(sent.url?.path == "/ex/jira/cloud-1/rest/agile/1.0/board")

        #expect(result.values.count == 1)
        #expect(result.values[0].id == 1)
        #expect(result.values[0].name == "Sharingan Board")
        #expect(result.values[0].type == "scrum")
    }

    @Test("JiraClient Agile API - getBoardConfiguration returns columns")
    func jiraClientGetBoardConfiguration() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let responseBody = """
            {
              "columnConfig": {
                "columns": [
                  { "name": "Backlog", "statuses": [{ "id": "1", "self": "https://..." }] },
                  { "name": "In Progress", "statuses": [{ "id": "3", "self": "https://..." }] },
                  { "name": "Done", "statuses": [{ "id": "5", "self": "https://..." }] }
                ]
              }
            }
            """.data(using: .utf8)!
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), responseBody)
        }
        let client = JiraClient(tokens: StubTokens(), session: session)

        let config = try await client.getBoardConfiguration(boardId: 1)

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "GET")
        #expect(sent.url?.path == "/ex/jira/cloud-1/rest/agile/1.0/board/1/configuration")

        #expect(config.columnConfig.columns.count == 3)
        #expect(config.columnConfig.columns[0].name == "Backlog")
        #expect(config.columnConfig.columns[1].name == "In Progress")
        #expect(config.columnConfig.columns[2].name == "Done")
    }

    @Test("JiraClient Agile API - getActiveSprint returns active sprint")
    func jiraClientGetActiveSprint() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let responseBody = """
            {
              "maxResults": 50,
              "startAt": 0,
              "total": 1,
              "isLast": true,
              "values": [
                { "id": 1, "name": "Sprint 1", "state": "active", "startDate": "2025-01-01T00:00:00.000Z", "endDate": "2025-01-14T23:59:59.000Z", "completeDate": null }
              ]
            }
            """.data(using: .utf8)!
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), responseBody)
        }
        let client = JiraClient(tokens: StubTokens(), session: session)

        let sprint = try await client.getActiveSprint(boardId: 1)

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "GET")
        #expect(sent.url?.path == "/ex/jira/cloud-1/rest/agile/1.0/board/1/sprint")
        #expect(sent.url?.query?.contains("state=active") == true)

        #expect(sprint?.id == 1)
        #expect(sprint?.name == "Sprint 1")
        #expect(sprint?.state == "active")
    }

    @Test("JiraClient Agile API - getSprintIssues returns sprint issues")
    func jiraClientGetSprintIssues() async throws {
        defer { TestURLProtocol.reset() }
        let session = TestURLProtocol.session { request in
            let responseBody = """
            {
              "maxResults": 50,
              "startAt": 0,
              "total": 1,
              "isLast": true,
              "issues": [
                { "id": "10001", "key": "SHR-1", "fields": { "summary": "Test", "status": { "name": "In Progress" } } }
              ]
            }
            """.data(using: .utf8)!
            return (try TestURLProtocol.jsonResponse(for: request, status: 200), responseBody)
        }
        let client = JiraClient(tokens: StubTokens(), session: session)

        let result = try await client.getSprintIssues(sprintId: 1)

        let sent = try #require(TestURLProtocol.requests.last)
        #expect(sent.method == "GET")
        #expect(sent.url?.path == "/ex/jira/cloud-1/rest/agile/1.0/sprint/1/issue")

        #expect(result.issues.count == 1)
        #expect(result.issues[0].key == "SHR-1")
    }

    // MARK: - Shared fixtures

    static let testConfig = JiraOAuthConfig(clientID: "client-abc", clientSecret: "secret-xyz")

    static let tokenPayload = Data("""
    {"access_token":"at-1","expires_in":3600,"refresh_token":"rt-1",
     "scope":"read:jira-user read:jira-work write:jira-work offline_access","token_type":"Bearer"}
    """.utf8)

    /// Ephemeral range, so a test run never fights the real 53682 listener or CI.
    static func randomEphemeralPort() -> UInt16 {
        UInt16.random(in: 49152...65500)
    }

    /// Stubs the whole 3LO flow: token exchange, cloudId lookup, and the two
    /// gateway calls `connect()` makes.
    static func oauthFlowHandler(canBrowseProjects: Bool) -> @Sendable (URLRequest) throws -> (HTTPURLResponse, Data) {
        { request in
            switch request.url?.path {
            case "/oauth/token":
                return (try TestURLProtocol.jsonResponse(for: request, status: 200), tokenPayload)
            case "/oauth/token/accessible-resources":
                return (try TestURLProtocol.jsonResponse(for: request, status: 200), Data("""
                [{"id":"cloud-1","url":"https://wayll.atlassian.net","name":"Wayll",
                  "scopes":["read:jira-work"]}]
                """.utf8))
            case "/ex/jira/cloud-1/rest/api/3/myself":
                return (try TestURLProtocol.jsonResponse(for: request, status: 200), Data("""
                {"accountId":"abc123","displayName":"Dev User","emailAddress":"dev@example.com","active":true}
                """.utf8))
            case "/ex/jira/cloud-1/rest/api/3/mypermissions":
                return (try TestURLProtocol.jsonResponse(for: request, status: 200), Data("""
                {"permissions":{
                  "BROWSE_PROJECTS":{"id":"10","key":"BROWSE_PROJECTS","name":"Browse Projects","havePermission":\(canBrowseProjects)},
                  "CREATE_ISSUES":{"id":"11","key":"CREATE_ISSUES","name":"Create Issues","havePermission":\(canBrowseProjects)},
                  "WORK_ON_ISSUES":{"id":"12","key":"WORK_ON_ISSUES","name":"Work On Issues","havePermission":\(canBrowseProjects)}
                }}
                """.utf8))
            default:
                return (try TestURLProtocol.response(for: request, status: 404), Data())
            }
        }
    }

    /// Two-site variant: `accessible-resources` returns cloud-1 (wayll) and
    /// cloud-2 (other), and both sites answer `myself`/`mypermissions` under
    /// their own gateway prefix. `canBrowseOnCloud2` lets a test model a site
    /// the account can reach over OAuth but has no browsable projects in.
    static func multiSiteHandler(canBrowseOnCloud2: Bool = true)
    -> @Sendable (URLRequest) throws -> (HTTPURLResponse, Data) {
        { request in
            let path = request.url?.path ?? ""

            func myself() throws -> (HTTPURLResponse, Data) {
                (try TestURLProtocol.jsonResponse(for: request, status: 200), Data("""
                {"accountId":"abc123","displayName":"Dev User","emailAddress":"dev@example.com","active":true}
                """.utf8))
            }
            func permissions(_ can: Bool) throws -> (HTTPURLResponse, Data) {
                (try TestURLProtocol.jsonResponse(for: request, status: 200), Data("""
                {"permissions":{
                  "BROWSE_PROJECTS":{"id":"10","key":"BROWSE_PROJECTS","name":"Browse Projects","havePermission":\(can)},
                  "CREATE_ISSUES":{"id":"11","key":"CREATE_ISSUES","name":"Create Issues","havePermission":\(can)},
                  "WORK_ON_ISSUES":{"id":"12","key":"WORK_ON_ISSUES","name":"Work On Issues","havePermission":\(can)}
                }}
                """.utf8))
            }

            switch path {
            case "/oauth/token":
                return (try TestURLProtocol.jsonResponse(for: request, status: 200), tokenPayload)
            case "/oauth/token/accessible-resources":
                return (try TestURLProtocol.jsonResponse(for: request, status: 200), Data("""
                [{"id":"cloud-1","url":"https://wayll.atlassian.net","name":"Wayll","scopes":["read:jira-work"]},
                 {"id":"cloud-2","url":"https://other.atlassian.net","name":"Other","scopes":["read:jira-work"]}]
                """.utf8))
            case "/ex/jira/cloud-1/rest/api/3/myself",
                 "/ex/jira/cloud-2/rest/api/3/myself":
                return try myself()
            case "/ex/jira/cloud-1/rest/api/3/mypermissions":
                return try permissions(true)
            case "/ex/jira/cloud-2/rest/api/3/mypermissions":
                return try permissions(canBrowseOnCloud2)
            default:
                return (try TestURLProtocol.response(for: request, status: 404), Data())
            }
        }
    }
}

// MARK: - Test doubles

/// Plays the browser half of the loopback flow: reads `state` out of the
/// authorize URL and GETs the callback, the way Atlassian's redirect would.
///
/// Retries because the listener binds inside `awaitCallback`, a moment *after*
/// `openURL` is called — a real browser takes seconds to get there, this doesn't.
private func simulateBrowserCallback(authorizeURL: URL, port: UInt16, code: String = "auth-code-1") {
    let state = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)?
        .queryItems?.first { $0.name == "state" }?.value ?? ""
    let encoded = state.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? state
    guard let callback = URL(string: "http://localhost:\(port)/callback?code=\(code)&state=\(encoded)") else {
        return
    }
    Task.detached {
        // Real loopback traffic — deliberately not the stubbed session.
        let browser = URLSession(configuration: .ephemeral)
        for _ in 0..<60 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if (try? await browser.data(from: callback)) != nil { return }
        }
    }
}

/// A `JiraTokenProviding` that hands out canned tokens and counts the asks.
///
/// The client must call this per request — the count is how the 401-retry test
/// proves the retry re-fetches rather than replaying the stale token.
private final class StubTokens: JiraTokenProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [String]
    private var calls = 0
    private let cloudId: String

    init(tokens: [String] = ["at-1"], cloudId: String = "cloud-1") {
        self.tokens = tokens
        self.cloudId = cloudId
    }

    var accessTokenCalls: Int {
        lock.lock(); defer { lock.unlock() }
        return calls
    }

    func accessToken() async throws -> String { take() }

    func cloudID() async throws -> String { cloudId }

    /// Synchronous on purpose: NSLock must not be taken directly in an async
    /// context (it isn't task-aware, and the compiler says so).
    private func take() -> String {
        lock.lock(); defer { lock.unlock() }
        calls += 1
        // The last token repeats forever, so a caller can pass one and forget.
        return tokens.count > 1 ? tokens.removeFirst() : tokens[0]
    }
}

/// In-memory stand-in for `KeychainStore`, keyed by account. Keeps tests off the
/// real login keychain (which would prompt, and would leak between runs).
private final class FakeKeychain: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]

    var values: [String: String] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

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

/// Lock-guarded boxes so `@Sendable` callbacks can report back to the test body.
private final class URLBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: URL?

    var value: URL? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }
}

private final class DeletionLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    var entries: [String] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func append(_ entry: String) {
        lock.lock(); defer { lock.unlock() }
        stored.append(entry)
    }
}

extension URLRequest {
    /// The request body as seen from inside a `URLProtocol`.
    ///
    /// URLSession moves `httpBody` into `httpBodyStream` by the time a request
    /// reaches a custom protocol, so `httpBody` always reads back nil there —
    /// assertions must drain the stream instead.
    var bodyData: Data? {
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

/// One request as it reached the stub, recorded so the test body — not the
/// `URLProtocol` callback — can assert on it.
///
/// `startLoading()` runs on URLSession's queue, outside the test's task-local
/// context, so any `#expect` there is orphaned onto `Test «unknown»` and cannot
/// fail the test. Handlers must only build responses; assertions belong after
/// the `await`, against these records.
private struct RecordedRequest: @unchecked Sendable {
    let request: URLRequest
    /// Drained at record time — the body stream is single-pass.
    let body: Data?

    var method: String? { request.httpMethod }
    var url: URL? { request.url }

    /// Case-insensitive, matching HTTP header semantics.
    func header(_ name: String) -> String? { request.value(forHTTPHeaderField: name) }

    func jsonObject() throws -> [String: Any] {
        let data = try #require(body, "request had no body")
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any],
                            "request body was not a JSON object")
    }
}

private final class TestURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var _handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    private static var _requests: [RecordedRequest] = []

    static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { lock.lock(); defer { lock.unlock() }; return _handler }
        set { lock.lock(); defer { lock.unlock() }; _handler = newValue }
    }

    /// Every request the stub saw this test, in order. The suite is
    /// `.serialized`, and `reset()` clears this between tests.
    static var requests: [RecordedRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    /// Handlers that need to vary by call read this instead of `requests.count`
    /// — it's the same number without copying the log.
    static var requestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _requests.count
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        _handler = nil
        _requests = []
    }

    /// Empties the request log but keeps the handler, so a test can assert on
    /// only the traffic from the step it's exercising. `reset()` drops the
    /// handler too, which would strand every request that follows.
    static func clearRequests() {
        lock.lock(); defer { lock.unlock() }
        _requests = []
    }

    private static func record(_ recorded: RecordedRequest) {
        lock.lock(); defer { lock.unlock() }
        _requests.append(recorded)
    }

    // MARK: - Response builders (no assertions — handlers run off-test)

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

        Self.record(RecordedRequest(request: request, body: request.bodyData))

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
