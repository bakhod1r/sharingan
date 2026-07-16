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
public final class JiraService: ObservableObject, JiraPomodoroHooks {

    public static let autoStartTransitionDefaultsKey = "jira.autoStartTransition"
    public static let doneBehaviorDefaultsKey = "jira.doneBehavior"
    public static let autoCompleteLocalDefaultsKey = "jira.autoCompleteLocal"
    public static let worklogSyncDefaultsKey = "jira.worklogSync"
    public static let pushEstimateDefaultsKey = "jira.pushEstimate"
    public static let pollMinutesDefaultsKey = "jira.pollMinutes"
    public static let customJQLDefaultsKey = "jira.customJQL"
    public static let showTypeBadgeDefaultsKey = "jira.showTypeBadge"
    /// When on, a newly-created Jira issue is also dropped into the project's
    /// active sprint (best-effort).
    public static let addToActiveSprintDefaultsKey = "jira.addToActiveSprint"

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
    /// Host of the **active session's** site. Never read off `availableSites` —
    /// that list is a menu of what could be picked, not a record of what is.
    @Published public private(set) var siteHost: String?
    /// cloudId of the active session — the picker's selection.
    @Published public private(set) var activeSiteID: String?
    /// Every site this grant can reach. One OAuth grant covers all of them, so
    /// this is a menu the user may pick from at any time while connected, not
    /// just during connect. Deliberately not persisted: refetching is one cheap
    /// request and is always current, whereas a stale list offers sites the
    /// account has since lost.
    @Published public private(set) var availableSites: [JiraAccessibleResource] = []
    @Published public private(set) var isWorking = false
    @Published public private(set) var lastErrorMessage: String?

    /// Lets a `JiraService` extension in another file (quick-add) publish a
    /// user-facing failure without widening the setter to the whole module.
    func setLastError(_ message: String?) { lastErrorMessage = message }
    /// Outcome of the most recent `syncAssignedIssues()`, for the Settings row.
    @Published public private(set) var lastSync: JiraSyncSummary?
    /// Projects (Atlassian "spaces") on the active site the account can browse.
    /// Populated by `refreshProjects()`; empty until then.
    @Published public private(set) var availableProjects: [JiraProject] = []

    public static let selectedProjectDefaultsKey = "jira.selectedProject"

    /// The project a sync restricts to, or nil for "everything assigned to me".
    /// Persisted so the choice survives relaunch.
    public var selectedProjectKey: String? {
        get { defaults.string(forKey: Self.selectedProjectDefaultsKey) }
        set {
            if let newValue, !newValue.isEmpty {
                defaults.set(newValue, forKey: Self.selectedProjectDefaultsKey)
            } else {
                defaults.removeObject(forKey: Self.selectedProjectDefaultsKey)
            }
            objectWillChange.send()
        }
    }

    private let defaults: UserDefaults
    private let store: JiraTokenStore
    private let oauthConfig: JiraOAuthConfig?
    private let oauthSession: URLSession
    private let callbackPort: UInt16
    private let openURL: (@Sendable (URL) -> Void)?
    private let tokens: JiraOAuthTokenProvider
    private let client: JiraClient
    /// The issue cache, when the app wired one in. Site-scoped: rows carry the
    /// host they were fetched from, and a switch must not let the old site's
    /// issues masquerade as the new one's.
    private let issueCache: JiraStorage?
    /// The task list syncs write into — injectable so tests run against a
    /// throwaway store instead of the app's.
    private let taskStore: TaskStore
    /// Decides which newly-assigned / due-today / sprint-ending notifications a
    /// sync should fire. `lazy` so it binds to this service's `defaults`; a test
    /// can replace it to capture what would be posted.
    public lazy var notifier: JiraNotifier = JiraNotifier(
        defaults: defaults,
        notify: { NotificationService.shared.notify(title: $0, body: $1, identifier: $2) })
    /// Held between `connect()` surfacing a site list and `selectSite(_:)`.
    private var pendingTokens: JiraOAuth.Tokens?
    private var restoreTask: Task<Void, Never>?

    /// The OAuth app credentials baked into this bundle, or nil for a build made
    /// without them (a plain `swift build`, and every test).
    public nonisolated static func bundledOAuthConfig() -> JiraOAuthConfig? {
        guard JiraAppCredentials.isConfigured,
              let clientID = JiraAppCredentials.clientID else { return nil }
        // With a broker the secret is empty by design; JiraOAuth drops it from
        // the request when tokenBrokerURL is set, so "" never goes on the wire.
        return JiraOAuthConfig(clientID: clientID,
                               clientSecret: JiraAppCredentials.clientSecret ?? "",
                               tokenBrokerURL: JiraAppCredentials.brokerURL)
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
                issueCache: JiraStorage? = nil,
                taskStore: TaskStore? = nil,
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
        self.issueCache = issueCache
        self.taskStore = taskStore ?? .shared

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
        // Re-entrancy guard: a second sign-in started while the first is still
        // waiting for its browser callback gets a fresh `state` and rebinds the
        // same loopback port, so completing the *older* browser page then fails
        // the CSRF check ("state mismatch"). One flow at a time.
        if case .connecting = status { return false }
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
            availableSites = resources
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
        activeSiteID = session.cloudID
        store.accountName = user.displayName
        dropCachedIssues(foreignTo: host)

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

    // MARK: - Sites

    /// Re-reads the sites this grant can reach. Best-effort: a failure leaves the
    /// last known list in place rather than emptying the picker under the user.
    ///
    /// This needs no consent and no new token — `accessible-resources` answers
    /// for the whole grant, which is exactly why switching sites is possible at
    /// all.
    @discardableResult
    public func refreshAvailableSites() async -> Bool {
        guard let oauthConfig else { return false }
        do {
            let token = try await tokens.accessToken()
            let oauth = JiraOAuth(config: oauthConfig, session: oauthSession)
            let sites = try await oauth.accessibleResources(accessToken: token)
            guard !sites.isEmpty else { return false }
            availableSites = sites
            return true
        } catch {
            return false
        }
    }

    /// Points the live session at another Atlassian site.
    ///
    /// One 3LO grant covers every site in `availableSites`, so this is a cloudId
    /// swap — no browser, no consent, no token refresh. What it *does* need is
    /// the preflight run again: permissions are per-site, so a site the grant can
    /// reach may still have no browsable project.
    ///
    /// If the new site doesn't answer, the previous session is put back: a failed
    /// switch must not leave the app pointing at a site it cannot talk to.
    @discardableResult
    public func switchSite(_ resource: JiraAccessibleResource) async -> Bool {
        guard isConnected else {
            lastErrorMessage = "Connect to Jira before switching site."
            return false
        }
        guard let previous = await tokens.currentSession() else {
            fail(with: JiraError.notConfigured)
            return false
        }
        guard previous.cloudID != resource.id else { return true }

        var session = previous
        session.cloudID = resource.id
        session.siteURL = resource.url

        isWorking = true
        lastErrorMessage = nil
        do {
            try store.save(session)
            await tokens.adopt(session)
            // Switching to a site the account can reach over OAuth but can't
            // browse is not a usable switch — report it as failure so the UI
            // can steer back, even though the session is technically connected.
            let hasAccess = try await identityAndPermissions(session: session)
            isWorking = false
            return hasAccess
        } catch {
            try? store.save(previous)
            await tokens.adopt(previous)
            fail(with: error, unauthorizedMeansReconsent: true)
            return false
        }
    }

    /// Forgets cached issues belonging to any site but the active one.
    ///
    /// `jira_issues` is keyed by issue id and carries `site_host`; two sites can
    /// hand out the same issue *key*, and a row fetched from the old site would
    /// otherwise be served as the new site's. The cache is refetchable, so
    /// deleting the foreign rows is cheaper than teaching every read to filter.
    // MARK: - Sync direction + change capture

    public static let syncModeDefaultsKey = "jira.syncMode"

    /// One-way (`pull`, the default) or two-way. In pull mode local edits never
    /// queue — Jira stays the untouched source of truth.
    public enum SyncMode: String, Sendable {
        case pull, twoWay
    }

    public var syncMode: SyncMode {
        get { SyncMode(rawValue: defaults.string(forKey: Self.syncModeDefaultsKey) ?? "") ?? .pull }
        set { defaults.set(newValue.rawValue, forKey: Self.syncModeDefaultsKey); objectWillChange.send() }
    }

    /// True while a sync is writing Jira's own values into the task store —
    /// those writes echo through the change observer and must not be captured
    /// as local edits (they'd bounce straight back to Jira).
    private var isApplyingRemote = false

    /// Called (via the TaskStore observer) whenever a Jira-linked task changes
    /// locally. Diffs against the last-seen snapshot and queues a `fields` op;
    /// repeated edits to one issue coalesce into a single queued item carrying
    /// the latest cumulative diff.
    public func taskDidChange(_ task: TaskItem) {
        guard syncMode == .twoWay, !isApplyingRemote,
              let issueID = task.jiraIssueID, let key = task.jiraKey,
              let issueCache,
              let lastSeen = issueCache.issue(id: issueID) else { return }

        let push = JiraFieldMapper.pushFields(
            local: task, lastSeen: lastSeen,
            pushEstimate: defaults.bool(forKey: Self.pushEstimateDefaultsKey))
        guard !push.isEmpty,
              let data = try? JSONEncoder().encode(push),
              let payload = String(data: data, encoding: .utf8) else { return }

        // Reusing the queued item's id turns enqueue's upsert into the coalesce.
        let existing = issueCache.pendingItem(issueKey: key, op: .fields)
        issueCache.enqueue(OutboxItem(id: existing?.id ?? UUID(),
                                      issueKey: key, op: .fields, payload: payload,
                                      createdAt: existing?.createdAt ?? Date()))
        objectWillChange.send()
    }

    /// The active site's host — the live `siteHost` when connected this session,
    /// else derived from the persisted session's URL (so a create right after a
    /// cold launch, before a refresh, still knows where it's filing).
    private var resolvedSiteHost: String? {
        if let siteHost { return siteHost }
        guard let url = defaults.string(forKey: JiraTokenStore.siteURLDefaultsKey) else { return nil }
        return URL(string: url)?.host ?? url
    }

    // MARK: - Create (Sharingan → Jira)

    public static let categoryProjectMapDefaultsKey = "jira.categoryProjectMap"

    /// Category → project-key map for issue creation, edited in Settings. A
    /// task's category decides which project it's filed under.
    public var categoryProjectMap: [String: String] {
        get { (defaults.dictionary(forKey: Self.categoryProjectMapDefaultsKey) as? [String: String]) ?? [:] }
        set { defaults.set(newValue, forKey: Self.categoryProjectMapDefaultsKey); objectWillChange.send() }
    }

    /// The project a task should be created in: an explicit key, else the
    /// category mapping, else the selected space.
    public func projectKey(forTask task: TaskItem, explicit: String? = nil) -> String? {
        explicit ?? categoryProjectMap[task.category] ?? boardProjectKey
    }

    /// Creates a Jira issue from a local task and links the returned key back
    /// onto it. Creating team-visible issues is deliberate and per-task — the
    /// caller confirms before bulk runs. Returns false and records an error on
    /// failure; the task is left unlinked so it can be retried.
    @discardableResult
    public func createIssue(from task: TaskItem, projectKey explicitProject: String? = nil,
                            issueType explicitType: String? = nil) async -> Bool {
        guard let host = resolvedSiteHost,
              let project = projectKey(forTask: task, explicit: explicitProject) else {
            lastErrorMessage = "Pick a Jira project for this task first."
            return false
        }
        // Prefer an explicit type, else the one the task already carries (a
        // re-linked Story shouldn't downgrade to Task), else the standard "Task".
        let issueType = explicitType ?? task.jiraIssueType ?? "Task"
        do {
            let ref = try await client.createIssue(fields: JiraIssueCreateFields(
                projectKey: project, issueTypeName: issueType,
                summary: task.title,
                priorityName: JiraFieldMapper.jiraPriorityName(from: task.priority),
                descriptionText: task.notes.isEmpty ? nil : task.notes,
                labels: task.tags.map(JiraFieldMapper.jiraLabel(from:)),
                dueDate: JiraFieldMapper.jiraDueDate(from: task.dueDate),
                estimateSeconds: JiraFieldMapper.estimateSeconds(fromPomodoros: task.estimatedPomodoros)))
            var linked = task
            linked.jiraKey = ref.key
            linked.jiraIssueID = ref.id
            linked.jiraSiteHost = host
            linked.jiraIssueType = issueType

            // Create each not-yet-linked subtask as a real Jira sub-task under
            // the new parent, so a converted multi-step task keeps its shape.
            // A subtask failing is not fatal — the parent is already created and
            // linked; the subtask stays local and can be retried.
            let unlinkedSubs = linked.subtasks.contains { $0.jiraKey == nil }
            if unlinkedSubs, let subType = await subtaskIssueTypeName(forProjectKey: project) {
                for i in linked.subtasks.indices where linked.subtasks[i].jiraKey == nil {
                    let sub = linked.subtasks[i]
                    if let subRef = try? await client.createIssue(fields: JiraIssueCreateFields(
                        projectKey: project, issueTypeName: subType, summary: sub.title,
                        estimateSeconds: JiraFieldMapper.estimateSeconds(fromPomodoros: sub.estimatedPomodoros),
                        parentKey: ref.key)) {
                        linked.subtasks[i].jiraKey = subRef.key
                        linked.subtasks[i].jiraIssueID = subRef.id
                    }
                }
            }

            isApplyingRemote = true
            taskStore.update(linked)
            isApplyingRemote = false

            // Optionally drop the new issue into the project's active sprint.
            await addToActiveSprintIfEnabled(issueKey: ref.key, projectKey: project)

            lastErrorMessage = nil
            objectWillChange.send()
            return true
        } catch {
            lastErrorMessage = (error as? JiraError)?.userMessage ?? error.localizedDescription
            return false
        }
    }

    /// Adds a freshly-created issue to the project's active sprint when the
    /// setting is on. Best-effort: any failure (no board, no active sprint, a
    /// restricted sprint) is swallowed — the issue is already created and
    /// linked, it just stays in the backlog.
    private func addToActiveSprintIfEnabled(issueKey: String, projectKey: String) async {
        guard UserDefaults.standard.bool(forKey: Self.addToActiveSprintDefaultsKey) else { return }
        guard let boards = try? await client.getBoards(projectKeyOrId: projectKey),
              let board = boards.values.first,
              let sprint = try? await client.getActiveSprint(boardId: board.id) ?? nil else { return }
        try? await client.addIssuesToSprint(sprintId: sprint.id, issueKeys: [issueKey])
    }

    /// A cache of each project's sub-task issue-type name, keyed by project key.
    /// Resolved once per project — the value doesn't change between syncs.
    private var subtaskTypeCache: [String: String] = [:]

    /// The name of a sub-task issue type in the given project ("Sub-task" in
    /// company-managed projects, "Subtask" in team-managed ones), or nil when
    /// the project has none (so the caller skips sub-task creation rather than
    /// 400ing). Looked up via the project's numeric id, which the issue-type
    /// endpoint requires.
    private func subtaskIssueTypeName(forProjectKey key: String) async -> String? {
        if let cached = subtaskTypeCache[key] { return cached }
        guard let projectID = availableProjects.first(where: { $0.key == key })?.id else { return nil }
        guard let types = try? await client.getIssueTypes(projectId: projectID) else { return nil }
        guard let name = types.values.first(where: { $0.subtask })?.name else { return nil }
        subtaskTypeCache[key] = name
        return name
    }

    #if DEBUG
    /// Seeds `availableProjects` for tests that create issues without a full
    /// connect (which is what populates the real list).
    func setAvailableProjectsForTesting(_ projects: [JiraProject]) {
        availableProjects = projects
    }
    #endif

    /// Local tasks eligible to be pushed to Jira: not yet linked and not done,
    /// optionally scoped to one category. The Settings "Convert to Jira" action
    /// previews this set before creating anything.
    public func unlinkedTasks(inCategory category: String? = nil) -> [TaskItem] {
        taskStore.tasks.filter { task in
            !task.isJiraLinked && !task.isDone
                && (category == nil || task.category == category)
        }
    }

    /// Bulk-creates Jira issues for every unlinked, undone task (optionally in
    /// one category) and links each returned key back. Existing local tasks are
    /// what seed Jira the first time — the queue only carries *changes* to tasks
    /// that are already linked, so nothing shows there until this runs. Returns
    /// the number created; a per-task failure is recorded and skipped.
    @discardableResult
    public func pushUnlinkedTasks(inCategory category: String? = nil) async -> Int {
        var created = 0
        for task in unlinkedTasks(inCategory: category) {
            if await createIssue(from: task) { created += 1 }
        }
        return created
    }

    // MARK: - View-model factories

    /// A board model bound to this connection, or nil when disconnected.
    /// Reuses the service's authenticated client so the views never touch auth.
    public func makeBoardModel() -> JiraBoardModel? {
        guard let host = siteHost else { return nil }
        return JiraBoardModel(client: client, siteHost: host, defaults: defaults)
    }

    /// A detail model for one issue, or nil when disconnected.
    public func makeDetailModel(issueKey: String) -> JiraIssueDetailModel? {
        guard let host = siteHost else { return nil }
        return JiraIssueDetailModel(client: client, issueKey: issueKey, siteHost: host)
    }

    /// The project key a board should open — the selected space, else the first
    /// browsable project.
    public var boardProjectKey: String? {
        selectedProjectKey ?? availableProjects.first?.key
    }

    // MARK: - Cached status (for the row chip)

    /// The last-synced status name + category key for a linked issue, if cached.
    public func cachedStatus(issueID: String) -> (name: String, category: String)? {
        guard let cached = issueCache?.issue(id: issueID),
              let name = cached.statusName else { return nil }
        return (name, cached.statusCategory ?? "undefined")
    }

    // MARK: - Transitions (move status from Sharingan)

    /// The workflow moves available from an issue's current status. Empty on
    /// error; the caller shows a menu.
    public func transitions(forIssueKey key: String) async -> [JiraTransition] {
        (try? await client.getTransitions(issueKey: key)) ?? []
    }

    /// Applies a transition immediately (interactive, not queued). On success
    /// the cached status is updated so the row's chip reflects the new column
    /// at once. Returns false and records an error on failure.
    @discardableResult
    public func applyTransition(issueKey: String, transition: JiraTransition) async -> Bool {
        do {
            try await client.doTransition(issueKey: issueKey, transitionId: transition.id)
            if let issueCache, var cached = issueCache.issue(key: issueKey) {
                cached.statusName = transition.to.name
                cached.statusCategory = transition.to.statusCategory.key
                cached.statusID = transition.to.id
                issueCache.upsertIssue(cached)
            }
            lastErrorMessage = nil
            objectWillChange.send()
            return true
        } catch {
            lastErrorMessage = (error as? JiraError)?.userMessage ?? error.localizedDescription
            return false
        }
    }

    // MARK: - Worklog (pomodoro → Jira)

    /// A completed pomodoro on a linked task. In two-way mode with worklog sync
    /// on, queues a worklog against the sub-task's issue when the active subtask
    /// is Jira-linked (the time belongs to the sub-task), otherwise the parent
    /// task's issue. Sessions under a minute are dropped — Jira rejects them.
    public func pomodoroCompleted(taskID: UUID, subtaskID: UUID?,
                                  seconds: TimeInterval, completedAt: Date = Date()) {
        guard syncMode == .twoWay,
              defaults.bool(forKey: Self.worklogSyncDefaultsKey),
              let issueCache,
              let task = taskStore.tasks.first(where: { $0.id == taskID }) else { return }

        let whole = Int(seconds.rounded(.down))
        guard whole >= 60 else { return }

        // Prefer the active sub-task's issue.
        let subtask = subtaskID.flatMap { sid in task.subtasks.first { $0.id == sid } }
        let issueKey = (subtask?.isJiraLinked == true ? subtask?.jiraKey : nil) ?? task.jiraKey
        guard let issueKey else { return }

        let started = JiraWorklogPayload.startedFormatter.string(
            from: completedAt.addingTimeInterval(-Double(whole)))
        let comment = defaults.string(forKey: Self.worklogCommentDefaultsKey)
            ?? "Focus session from Sharingan 🍅"
        let payload = JiraWorklogPayload(timeSpentSeconds: whole, started: started, comment: comment)
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else { return }

        issueCache.enqueue(OutboxItem(issueKey: issueKey, op: .worklog, payload: json))
        objectWillChange.send()
    }

    public static let worklogCommentDefaultsKey = "jira.worklogComment"

    // MARK: - Push (drain the queue)

    /// Sends every due queued write now — the "Push now" button and the poll's
    /// second half. Safe to call in pull mode (the queue is simply empty).
    @discardableResult
    public func pushNow() async -> (sent: Int, failed: Int) {
        guard let issueCache else { return (0, 0) }
        let flusher = JiraOutboxFlusher(client: client, storage: issueCache)
        let result = await flusher.flush()
        objectWillChange.send()
        return result
    }

    /// Queued-but-unsent writes, for the Settings row.
    public var pendingPushCount: Int { issueCache?.pendingCount() ?? 0 }

    /// Permanently failed writes awaiting Retry/Dismiss.
    public var failedPushItems: [OutboxItem] { issueCache?.failedItems() ?? [] }

    // MARK: - Poll

    private var pollTask: Task<Void, Never>?

    /// Pull on a timer, then (in two-way mode) push the queue. Reads the
    /// interval each lap, so a Settings change applies without a restart;
    /// 0 pauses polling but keeps the loop alive so re-enabling works.
    public func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let minutes = self?.defaults.integer(forKey: Self.pollMinutesDefaultsKey) ?? 0
                let wait = minutes > 0 ? minutes : 1
                try? await Task.sleep(nanoseconds: UInt64(wait) * 60 * 1_000_000_000)
                guard let self, !Task.isCancelled, minutes > 0, self.hasProjectAccess else { continue }
                await self.syncAssignedIssues()
                if self.syncMode == .twoWay { await self.pushNow() }
            }
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Issue sync

    /// The default filter: issues assigned to me that aren't done, newest first.
    public static let assignedOpenJQL =
        "assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC"

    /// The same, restricted to one project ("space").
    public static func assignedOpenJQL(project key: String) -> String {
        "assignee = currentUser() AND statusCategory != Done AND project = \"\(key)\" ORDER BY updated DESC"
    }

    /// A JQL of the user's own that *replaces* the built-in filter, or "" when
    /// unset. This is the escape hatch for the filters the Settings pickers
    /// can't express (a saved team filter, a label, a sprint) — so it overrides
    /// the space scoping rather than being ANDed onto it: a query the user typed
    /// verbatim must be the query that runs, or the field is a lie.
    ///
    /// Whitespace stores as "unset": a field holding two spaces is not a filter,
    /// and sending it would fail every sync with a Jira parse error.
    public var customJQL: String {
        get { defaults.string(forKey: Self.customJQLDefaultsKey) ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                defaults.removeObject(forKey: Self.customJQLDefaultsKey)
            } else {
                defaults.set(trimmed, forKey: Self.customJQLDefaultsKey)
            }
            objectWillChange.send()
        }
    }

    /// The filter a sync runs when the caller names none: the custom JQL if the
    /// user wrote one, else the selected space, else everything assigned to me.
    var effectiveJQL: String {
        let custom = customJQL
        if !custom.isEmpty { return custom }
        return selectedProjectKey.map(Self.assignedOpenJQL(project:)) ?? Self.assignedOpenJQL
    }

    /// Loads the browsable projects on the active site for the Settings picker.
    /// Best-effort: a failure leaves the list as-is rather than dropping the
    /// connection, since the picker is a convenience, not a requirement.
    public func refreshProjects() async {
        guard hasProjectAccess else { return }
        do {
            let response = try await client.getProjects(maxResults: 50)
            availableProjects = response.values
        } catch {
            // Keep whatever we had; surface nothing — this is a background refresh.
        }
    }

    /// The Jira fields worth fetching — everything the mapper reads. Asking for
    /// only these keeps each page small.
    private static let syncFields = [
        "summary", "status", "priority", "labels", "components",
        "duedate", "timetracking", "project", "issuetype", "updated", "parent",
    ]

    /// Pulls the issues assigned to me into the task list.
    ///
    /// Fresh issues become tasks; issues already linked to a task are reconciled
    /// through `JiraFieldMapper.merge` against the last-seen cache snapshot, so a
    /// Jira-side change lands locally without clobbering local pomodoro progress.
    /// This is pull-only for now — conflicts are counted and surfaced, but local
    /// edits are not yet pushed back (that lands with the worklog/transition
    /// work). Paginates to a safety ceiling so a huge backlog can't run forever.
    @discardableResult
    public func syncAssignedIssues(jql explicitJQL: String? = nil) async -> JiraSyncSummary {
        // Default to the user's custom JQL, else the selected project ("space"),
        // else everything assigned. An explicit argument overrides all of them
        // (used by tests and by callers that know exactly what they want).
        let jql = explicitJQL ?? effectiveJQL
        guard hasProjectAccess, let host = siteHost else {
            let empty = JiraSyncSummary(imported: 0, updated: 0, conflicts: 0,
                                        failed: true, message: "Connect to a Jira site you can browse first.")
            lastSync = empty
            return empty
        }

        isWorking = true
        lastErrorMessage = nil
        // Everything this sync writes into the store is Jira's own state coming
        // back — the change observer must not re-queue it as a local edit.
        isApplyingRemote = true
        defer { isWorking = false; isApplyingRemote = false }

        let pushEstimate = defaults.bool(forKey: Self.pushEstimateDefaultsKey)
        var imported = 0, updated = 0, conflicts = 0

        do {
            // 1. Collect everything first — hierarchy can only be built over
            //    the whole set (a sub-task's parent may be pages away).
            var all: [JiraIssue] = []
            var token: String? = nil
            var pagesLeft = 20  // ceiling: 20 × 50 = 1000 issues
            repeat {
                let page = try await client.searchJQL(jql: jql, maxResults: 50,
                                                      nextPageToken: token,
                                                      fields: Self.syncFields)
                all += page.issues
                token = page.nextPageToken
                pagesLeft -= 1
            } while token != nil && pagesLeft > 0

            var hierarchy = JiraFieldMapper.buildHierarchy(issues: all)

            // 2. Orphan sub-tasks: their parents aren't assigned to me, so the
            //    search never returned them. One batched key-in query brings
            //    the parents in; the sub-task then nests like any other.
            let missingParentKeys = Set(hierarchy.orphanSubtasks.compactMap(\.fields.parent?.key))
                .subtracting(hierarchy.parents.map(\.key))
            if !missingParentKeys.isEmpty {
                let keyList = missingParentKeys.sorted().joined(separator: ",")
                let parentPage = try await client.searchJQL(
                    jql: "key in (\(keyList))", maxResults: 50, fields: Self.syncFields)
                hierarchy = JiraFieldMapper.buildHierarchy(issues: all + parentPage.issues)
            }

            // 3. Upsert parents with their sub-tasks nested. Flat twins — the
            //    pre-hierarchy imports of these sub-tasks — donate their
            //    progress and are deleted.
            for parentIssue in hierarchy.parents {
                let subIssues = hierarchy.subtasks(forParentKey: parentIssue.key)

                var task: TaskItem
                let existing = taskStore.tasks.first { $0.jiraIssueID == parentIssue.id }
                if let existing {
                    let outcome = JiraFieldMapper.merge(
                        local: existing, remote: parentIssue,
                        lastSeen: issueCache?.issue(id: parentIssue.id),
                        pushEstimate: pushEstimate)
                    task = outcome.mergedTask
                    conflicts += outcome.conflicts.count
                    updated += 1
                } else {
                    task = JiraFieldMapper.taskItem(from: parentIssue, siteHost: host)
                }
                task.jiraIssueType = parentIssue.fields.issuetype?.name ?? task.jiraIssueType

                let twins = taskStore.tasks.filter { candidate in
                    candidate.id != task.id
                        && subIssues.contains { $0.id == candidate.jiraIssueID }
                }
                let nested = JiraFieldMapper.nestSubtasks(into: task, remote: subIssues,
                                                          absorbing: twins)
                if existing != nil {
                    taskStore.update(nested.parent)
                } else if taskStore.upsertJiraTask(nested.parent) {
                    imported += 1
                }
                for absorbedID in nested.absorbedTaskIDs {
                    taskStore.delete(absorbedID)
                }

                issueCache?.upsertIssue(JiraFieldMapper.snapshot(from: parentIssue, siteHost: host))
                for sub in subIssues {
                    issueCache?.upsertIssue(JiraFieldMapper.snapshot(from: sub, siteHost: host))
                }
            }

            // 4. Sub-tasks whose parent couldn't be fetched at all fall back to
            //    the old flat import — visible beats lost.
            for orphan in hierarchy.orphanSubtasks
            where !hierarchy.parents.contains(where: { $0.key == orphan.fields.parent?.key }) {
                let task = JiraFieldMapper.taskItem(from: orphan, siteHost: host)
                if taskStore.tasks.first(where: { $0.jiraIssueID == orphan.id }) == nil {
                    if taskStore.upsertJiraTask(task) { imported += 1 }
                }
                issueCache?.upsertIssue(JiraFieldMapper.snapshot(from: orphan, siteHost: host))
            }

            // The list is already scoped to me (the JQL carries
            // `assignee = currentUser()` unless the user overrode it), so the
            // notifier can treat "newly appeared" as "newly assigned". The active
            // sprint is resolved only when the sprint-ending notification is on,
            // so an ordinary sync doesn't pay for the extra board calls.
            let sprint = notifier.isSprintEndingEnabled ? await activeSprintForNotifications() : nil
            notifier.process(issues: all, sprint: sprint, now: Date())

            let summary = JiraSyncSummary(imported: imported, updated: updated,
                                          conflicts: conflicts, failed: false, message: nil)
            lastSync = summary
            return summary
        } catch {
            let why = (error as? JiraError)?.userMessage ?? error.localizedDescription
            lastErrorMessage = why
            let summary = JiraSyncSummary(imported: imported, updated: updated,
                                          conflicts: conflicts, failed: true, message: why)
            lastSync = summary
            return summary
        }
    }

    /// The active sprint of the selected project's first board, for the
    /// sprint-ending notification. Best-effort: any failure (no board, no
    /// sprint, a kanban project) returns nil and the notifier simply skips the
    /// sprint check — a missed reminder is better than a failed sync.
    private func activeSprintForNotifications() async -> JiraSprint? {
        guard let project = boardProjectKey else { return nil }
        guard let boards = try? await client.getBoards(projectKeyOrId: project),
              let board = boards.values.first else { return nil }
        return (try? await client.getActiveSprint(boardId: board.id)) ?? nil
    }

    private func dropCachedIssues(foreignTo host: String) {
        guard let issueCache else { return }
        for cached in issueCache.allIssues() where cached.siteHost != host {
            issueCache.deleteIssue(id: cached.issueID)
        }
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
            activeSiteID = nil
            availableSites = []
            return
        }

        status = .restoring
        isWorking = true
        lastErrorMessage = nil
        do {
            _ = try await identityAndPermissions(session: session)
            // Only once the session is known good: an unreachable site says
            // nothing about which sites exist.
            await refreshAvailableSites()
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
        activeSiteID = nil
        availableSites = []
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

/// What one `syncAssignedIssues()` did, for the Settings row and any toast.
public struct JiraSyncSummary: Equatable, Sendable {
    public let imported: Int
    public let updated: Int
    public let conflicts: Int
    public let failed: Bool
    public let message: String?

    public init(imported: Int, updated: Int, conflicts: Int, failed: Bool, message: String?) {
        self.imported = imported
        self.updated = updated
        self.conflicts = conflicts
        self.failed = failed
        self.message = message
    }

    /// A short, user-facing recap ("8 imported · 4 updated").
    public var label: String {
        if failed { return message ?? "Sync failed." }
        var parts: [String] = []
        if imported > 0 { parts.append("\(imported) imported") }
        if updated > 0 { parts.append("\(updated) updated") }
        if conflicts > 0 { parts.append("\(conflicts) conflict\(conflicts == 1 ? "" : "s")") }
        return parts.isEmpty ? "Already up to date" : parts.joined(separator: " · ")
    }
}
