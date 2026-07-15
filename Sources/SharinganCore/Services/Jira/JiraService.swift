import Combine
import Foundation

public enum JiraDoneBehavior: String, CaseIterable, Identifiable, Sendable {
    case off
    case prompt
    case auto

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .off: return "Off"
        case .prompt: return "Prompt"
        case .auto: return "Auto"
        }
    }
}

// MARK: - Token provider

/// Owns the live OAuth session and hands `JiraClient` a valid bearer token.
///
/// **Why this is an actor, and why the refresh is single-flight.**
/// Atlassian rotates refresh tokens: every successful refresh mints a new one
/// and kills the one it was given. So two refreshes racing on the same stored
/// token do not merely waste a round-trip — the second one presents a token the
/// first has already spent, gets `invalid_grant`, and the user is logged out.
/// The window is wide open in practice: an access token expires while several
/// requests (poll, worklog flush, identity refresh) are in flight, and each asks
/// for a token at the same instant.
///
/// The fix is that a refresh happens inside exactly one `Task`, held in
/// `refreshInFlight`. Concurrent callers that find it already set await *that*
/// task's result instead of starting their own. The refreshed session is cached
/// on the actor before the flag clears, so a caller arriving a moment later sees
/// a fresh token and doesn't refresh either.
actor JiraOAuthTokenProvider: JiraTokenProviding {

    private let store: JiraTokenStore
    private let oauth: JiraOAuth?
    private var cached: JiraOAuthSession?
    private var didReadStore = false
    /// Non-nil exactly while a refresh is running. The single-flight latch.
    private var refreshInFlight: Task<JiraOAuthSession, Error>?
    private var onSessionDied: (@Sendable () -> Void)?

    init(store: JiraTokenStore, oauth: JiraOAuth?) {
        self.store = store
        self.oauth = oauth
    }

    /// Called when a refresh comes back `invalid_grant` — the session is gone and
    /// only re-consent brings it back.
    func onSessionDied(_ handler: @escaping @Sendable () -> Void) {
        onSessionDied = handler
    }

    /// Installs a session minted by `connect()`, skipping a store round-trip.
    func adopt(_ session: JiraOAuthSession) {
        cached = session
        didReadStore = true
    }

    func forget() {
        refreshInFlight?.cancel()
        refreshInFlight = nil
        cached = nil
        didReadStore = true
    }

    func currentSession() -> JiraOAuthSession? { loadedSession() }

    // MARK: JiraTokenProviding

    func accessToken() async throws -> String {
        guard let current = loadedSession() else { throw JiraError.notConfigured }
        guard current.isExpired() else { return current.accessToken }
        return try await refreshed(from: current).accessToken
    }

    /// The cloudId never expires, so this deliberately never triggers a refresh.
    func cloudID() async throws -> String {
        guard let current = loadedSession() else { throw JiraError.notConfigured }
        return current.cloudID
    }

    // MARK: - Internals

    private func loadedSession() -> JiraOAuthSession? {
        if let cached { return cached }
        if didReadStore { return nil }
        didReadStore = true
        cached = store.load()
        return cached
    }

    private func refreshed(from current: JiraOAuthSession) async throws -> JiraOAuthSession {
        // Someone else is already refreshing — take their result, don't spend the
        // refresh token a second time.
        if let refreshInFlight { return try await refreshInFlight.value }
        guard let oauth else { throw JiraError.notConfigured }

        let store = self.store
        let task = Task { () throws -> JiraOAuthSession in
            let tokens = try await oauth.refresh(refreshToken: current.refreshToken)
            var updated = current
            updated.accessToken = tokens.accessToken
            updated.refreshToken = tokens.refreshToken
            updated.expiresAt = tokens.expiresAt
            if !tokens.scopes.isEmpty { updated.scopes = tokens.scopes }
            // Persist the rotated refresh token before returning: the one we came
            // in with is already dead on Atlassian's side.
            try store.save(updated)
            return updated
        }
        refreshInFlight = task
        defer { refreshInFlight = nil }

        do {
            let updated = try await task.value
            cached = updated
            return updated
        } catch let error as JiraError where error == .unauthorized {
            // `invalid_grant`: spent, revoked, or 90 days idle. Retrying can't
            // help — drop the dead session and let the UI ask for re-consent.
            store.clear()
            cached = nil
            onSessionDied?()
            throw error
        }
    }
}

// MARK: - Service

/// Jira Cloud connection state for Settings, over OAuth 2.0 (3LO).
///
/// The service conforms to `JiraTokenProviding` (delegating to the actor above),
/// which is how `JiraClient` gets its bearer token without ever touching a
/// refresh token or the client secret.
@MainActor
public final class JiraService: ObservableObject {

    public static let autoStartTransitionDefaultsKey = "jira.autoStartTransition"
    public static let doneBehaviorDefaultsKey = "jira.doneBehavior"
    public static let autoCompleteLocalDefaultsKey = "jira.autoCompleteLocal"
    public static let worklogSyncDefaultsKey = "jira.worklogSync"
    public static let pushEstimateDefaultsKey = "jira.pushEstimate"
    public static let pollMinutesDefaultsKey = "jira.pollMinutes"

    /// Leftovers from the API-token era. Kept only so `purgeLegacyBasicAuth` can
    /// delete them — nothing reads these for auth any more.
    static let legacySiteURLDefaultsKey = "jira.siteURL"
    static let legacyEmailDefaultsKey = "jira.email"
    static let legacyKeychainService = "com.bakhod1r.sharingan.jira"

    public enum ConnectionStatus: Equatable, Sendable {
        case disconnected
        /// This build shipped without OAuth credentials — the flow cannot start.
        case notConfigured
        case restoring
        case connecting
        /// The token reaches more than one Atlassian site; the user picks.
        case chooseSite([JiraAccessibleResource])
        case connected(site: String, user: JiraUserIdentity)
        /// Authenticated, but the account can't browse any project. Distinct from
        /// `connected` because Jira's search answers 200 + zero issues in this
        /// case, so "Connected ✓" plus an empty list reads as a broken app.
        case noProjectAccess(site: String, user: JiraUserIdentity)
        /// The refresh token is dead. Not a transient error — needs "Log in again".
        case reconsentRequired
        case failed(String)

        public var label: String {
            switch self {
            case .disconnected: return "Not connected"
            case .notConfigured: return "Unavailable in this build"
            case .restoring: return "Restoring…"
            case .connecting: return "Connecting…"
            case .chooseSite: return "Choose a site"
            case .connected(_, let user): return "Connected as \(user.displayName)"
            case .noProjectAccess: return "No project access"
            case .reconsentRequired: return "Sign-in expired"
            case .failed(let message): return message
            }
        }
    }

    @Published public private(set) var status: ConnectionStatus = .disconnected
    @Published public private(set) var currentUser: JiraUserIdentity?
    @Published public private(set) var siteHost: String?
    @Published public private(set) var isWorking = false
    @Published public private(set) var lastErrorMessage: String?

    private let defaults: UserDefaults
    private let store: JiraTokenStore
    private let oauthConfig: JiraOAuthConfig?
    private let oauthSession: URLSession
    private let callbackPort: UInt16
    private let openURL: (@Sendable (URL) -> Void)?
    private let tokens: JiraOAuthTokenProvider
    private let client: JiraClient
    /// Held between `connect()` surfacing a site list and `selectSite(_:)`.
    private var pendingTokens: JiraOAuth.Tokens?
    private var restoreTask: Task<Void, Never>?

    /// The OAuth app credentials baked into this bundle, or nil for a build made
    /// without them (a plain `swift build`, and every test).
    public nonisolated static func bundledOAuthConfig() -> JiraOAuthConfig? {
        guard JiraAppCredentials.isConfigured,
              let clientID = JiraAppCredentials.clientID,
              let clientSecret = JiraAppCredentials.clientSecret else { return nil }
        return JiraOAuthConfig(clientID: clientID, clientSecret: clientSecret)
    }

    /// - Parameter openURL: opens the Atlassian consent page in the user's
    ///   browser. Injected because `SharinganCore` must stay free of AppKit —
    ///   the app layer passes `NSWorkspace.shared.open`. Nil means no browser,
    ///   and `connect()` says so instead of waiting on a callback that can never
    ///   arrive.
    public init(defaults: UserDefaults = .standard,
                store: JiraTokenStore = JiraTokenStore(),
                oauthConfig: JiraOAuthConfig? = JiraService.bundledOAuthConfig(),
                oauthSession: URLSession = .shared,
                apiSession: URLSession = .shared,
                callbackPort: UInt16 = JiraOAuth.callbackPort,
                openURL: (@Sendable (URL) -> Void)? = nil,
                restoreOnInit: Bool = true,
                legacyDeleteToken: @escaping @Sendable (String, String) -> Void = {
                    KeychainStore.delete(service: $0, account: $1)
                }) {
        self.defaults = defaults
        self.store = store
        self.oauthConfig = oauthConfig
        self.oauthSession = oauthSession
        self.callbackPort = callbackPort
        self.openURL = openURL

        let oauth = oauthConfig.map { JiraOAuth(config: $0, session: oauthSession) }
        let provider = JiraOAuthTokenProvider(store: store, oauth: oauth)
        self.tokens = provider
        self.client = JiraClient(tokens: provider, session: apiSession)

        purgeLegacyBasicAuth(deleteToken: legacyDeleteToken)

        if oauthConfig == nil {
            status = .notConfigured
        }
        restoreTask = Task { [weak self, provider] in
            await provider.onSessionDied { [weak self] in
                Task { @MainActor in self?.sessionDied() }
            }
            if restoreOnInit { await self?.restore() }
        }
    }

    deinit {
        restoreTask?.cancel()
    }

    public var isConnected: Bool {
        switch status {
        case .connected, .noProjectAccess: return true
        default: return false
        }
    }

    /// Connected *and* able to see projects — the only state where an empty issue
    /// list genuinely means "no issues".
    public var hasProjectAccess: Bool {
        if case .connected = status { return true }
        return false
    }

    public var isConfigured: Bool { oauthConfig != nil }

    // MARK: - Connect

    /// Runs the full 3LO dance: consent in the browser → loopback callback →
    /// code exchange → cloudId lookup → permission preflight.
    @discardableResult
    public func connect() async -> Bool {
        guard let oauthConfig else {
            // Fail here, not at Atlassian's authorize endpoint with a 400 about
            // an unknown client_id.
            lastErrorMessage = "This build of Sharingan was made without Jira sign-in credentials."
            status = .notConfigured
            return false
        }
        guard let openURL else {
            lastErrorMessage = "Sharingan couldn't open your browser to sign in to Jira."
            status = .failed(lastErrorMessage ?? "")
            return false
        }

        status = .connecting
        isWorking = true
        lastErrorMessage = nil
        pendingTokens = nil

        do {
            let oauth = JiraOAuth(config: oauthConfig, session: oauthSession)
            let state = JiraOAuth.makeState()
            openURL(oauth.authorizationURL(state: state))
            let code = try await oauth.awaitCallback(state: state, port: callbackPort)
            let tokens = try await oauth.exchange(code: code)
            let resources = try await oauth.accessibleResources(accessToken: tokens.accessToken)

            guard let first = resources.first else {
                throw JiraError.api(status: 403, messages: [
                    "This Atlassian account has no Jira site Sharingan can reach."
                ])
            }
            guard resources.count == 1 else {
                // More than one site: never guess. The wrong pick silently syncs
                // against someone else's project.
                pendingTokens = tokens
                status = .chooseSite(resources)
                isWorking = false
                return false
            }
            return await finishConnect(tokens: tokens, resource: first)
        } catch {
            fail(with: error)
            return false
        }
    }

    /// Completes a connect that stopped at `.chooseSite`.
    @discardableResult
    public func selectSite(_ resource: JiraAccessibleResource) async -> Bool {
        guard let pending = pendingTokens else {
            lastErrorMessage = "That Jira sign-in expired. Start again."
            status = .failed(lastErrorMessage ?? "")
            return false
        }
        status = .connecting
        isWorking = true
        return await finishConnect(tokens: pending, resource: resource)
    }

    private func finishConnect(tokens: JiraOAuth.Tokens,
                               resource: JiraAccessibleResource) async -> Bool {
        pendingTokens = nil
        let session = JiraOAuthSession(accessToken: tokens.accessToken,
                                       refreshToken: tokens.refreshToken,
                                       expiresAt: tokens.expiresAt,
                                       cloudID: resource.id,
                                       siteURL: resource.url,
                                       scopes: tokens.scopes)
        do {
            try store.save(session)
            await self.tokens.adopt(session)
            _ = try await identityAndPermissions(session: session)
            isWorking = false
            return isConnected
        } catch {
            store.clear()
            await self.tokens.forget()
            fail(with: error)
            return false
        }
    }

    /// Fetches `myself` and runs the BROWSE_PROJECTS preflight, then sets status.
    /// Returns whether the account can browse projects.
    @discardableResult
    private func identityAndPermissions(session: JiraOAuthSession) async throws -> Bool {
        let myself = try await client.myself()
        let user = JiraUserIdentity(myself: myself)
        let host = URL(string: session.siteURL)?.host ?? session.siteURL
        currentUser = user
        siteHost = host
        store.accountName = user.displayName

        let permissions = try await client.getMyPermissions()
        if permissions.canBrowseProjects {
            status = .connected(site: host, user: user)
            lastErrorMessage = nil
            return true
        }
        status = .noProjectAccess(site: host, user: user)
        lastErrorMessage = nil
        return false
    }

    // MARK: - Restore / disconnect

    /// Brings a stored session back at launch. A stale access token refreshes
    /// itself on the way through `JiraClient`.
    public func restore() async {
        guard oauthConfig != nil else {
            status = .notConfigured
            return
        }
        guard let session = await tokens.currentSession() else {
            status = .disconnected
            currentUser = nil
            siteHost = nil
            return
        }

        status = .restoring
        isWorking = true
        lastErrorMessage = nil
        do {
            _ = try await identityAndPermissions(session: session)
        } catch {
            fail(with: error, unauthorizedMeansReconsent: true)
        }
        isWorking = false
    }

    /// Drops the OAuth session. Task↔issue links are plain fields on `TaskItem`
    /// and survive untouched, so reconnecting picks them straight back up.
    public func disconnect() {
        restoreTask?.cancel()
        store.clear()
        pendingTokens = nil
        currentUser = nil
        siteHost = nil
        lastErrorMessage = nil
        isWorking = false
        status = oauthConfig == nil ? .notConfigured : .disconnected
        Task { [tokens] in await tokens.forget() }
    }

    private func sessionDied() {
        currentUser = nil
        isWorking = false
        lastErrorMessage = "Your Jira sign-in expired. Log in again to reconnect."
        status = .reconsentRequired
    }

    /// - Parameter unauthorizedMeansReconsent: true when we were acting on a
    ///   stored session — a 401 then means the tokens are dead and the honest
    ///   offer is "Log in again", not a toast the user can only stare at. During
    ///   a fresh `connect()` a 401 is Atlassian rejecting the exchange, which
    ///   re-consenting would not fix, so it stays a plain failure.
    private func fail(with error: Error, unauthorizedMeansReconsent: Bool = false) {
        let jiraError = (error as? JiraError) ?? .network(error.localizedDescription)
        currentUser = nil
        isWorking = false
        if unauthorizedMeansReconsent, jiraError == .unauthorized {
            sessionDied()
            return
        }
        lastErrorMessage = jiraError.userMessage
        status = .failed(jiraError.userMessage)
    }

    /// Removes the pre-OAuth site/email defaults and the API token they pointed
    /// at. Nothing reads them any more; leaving the token in the keychain forever
    /// would be a secret we no longer have any use for.
    private func purgeLegacyBasicAuth(deleteToken: @Sendable (String, String) -> Void) {
        guard let site = defaults.string(forKey: Self.legacySiteURLDefaultsKey) else { return }
        if let host = URL(string: site)?.host {
            deleteToken(Self.legacyKeychainService, host)
        }
        defaults.removeObject(forKey: Self.legacySiteURLDefaultsKey)
        defaults.removeObject(forKey: Self.legacyEmailDefaultsKey)
    }
}

// MARK: - JiraTokenProviding

extension JiraService: JiraTokenProviding {
    /// `nonisolated` and forwarded to the actor: token vending must not hop to
    /// the main actor on every REST call, and the single-flight guarantee lives
    /// in `JiraOAuthTokenProvider`, not here.
    public nonisolated func accessToken() async throws -> String {
        try await tokens.accessToken()
    }

    public nonisolated func cloudID() async throws -> String {
        try await tokens.cloudID()
    }
}
