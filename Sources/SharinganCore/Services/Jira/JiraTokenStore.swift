import Foundation

/// A live Atlassian OAuth 2.0 (3LO) session.
///
/// `refreshToken` is the long-lived credential: it rotates on every refresh and
/// is the only thing standing between the app and a re-consent prompt. It — and
/// the access token — live in the keychain; everything else here is
/// non-sensitive bookkeeping that `JiraTokenStore` keeps in UserDefaults.
public struct JiraOAuthSession: Sendable, Equatable {
    /// Bearer token for `api.atlassian.com`. Short-lived (~1h).
    public var accessToken: String
    /// Rotates on every refresh — persist the new one immediately.
    public var refreshToken: String
    /// True server-stated expiry (`now + expires_in`), with no margin baked in.
    /// Staleness decisions go through `isExpired(asOf:margin:)`.
    public var expiresAt: Date
    /// Atlassian cloud id — the `id` from `accessible-resources`, used to build
    /// `https://api.atlassian.com/ex/jira/<cloudID>/...` request URLs.
    public var cloudID: String
    /// e.g. `https://wayll.atlassian.net` — for user-facing "Open in Jira" links.
    public var siteURL: String
    public var scopes: [String]

    public init(accessToken: String,
                refreshToken: String,
                expiresAt: Date,
                cloudID: String,
                siteURL: String,
                scopes: [String]) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.cloudID = cloudID
        self.siteURL = siteURL
        self.scopes = scopes
    }

    /// How early a token is considered stale. A request that leaves with a token
    /// valid for another 5 seconds can still land after it expires, so callers
    /// refresh ahead of the wire expiry rather than on it.
    public static let refreshMargin: TimeInterval = 60

    /// Whether the access token should be refreshed before the next request.
    public func isExpired(asOf now: Date = Date(),
                          margin: TimeInterval = JiraOAuthSession.refreshMargin) -> Bool {
        now.addingTimeInterval(margin) >= expiresAt
    }
}

/// Persistence for the OAuth session: secrets to the keychain, bookkeeping to
/// UserDefaults.
///
/// The keychain and defaults are injected the same way `JiraService` does it, so
/// tests never touch the real login keychain.
///
/// `@unchecked Sendable` because of the stored `UserDefaults`, which is not
/// formally `Sendable` but is documented as thread-safe. The store is otherwise
/// immutable, and unlike `JiraService` it is not `@MainActor` — the OAuth flow
/// persists rotated tokens from a background task.
public struct JiraTokenStore: @unchecked Sendable {

    // MARK: - Storage keys

    public static let defaultKeychainService = "com.bakhod1r.sharingan.jira"
    /// Keychain accounts. Distinct from the Basic-auth token's account (the site
    /// host), so an old API-token install and a new OAuth install can coexist.
    public static let refreshTokenAccount = "oauth.refresh-token"
    public static let accessTokenAccount = "oauth.access-token"

    public static let expiresAtDefaultsKey = "jira.oauth.expiresAt"
    public static let cloudIDDefaultsKey = "jira.oauth.cloudID"
    public static let siteURLDefaultsKey = "jira.oauth.siteURL"
    public static let scopesDefaultsKey = "jira.oauth.scopes"
    public static let accountNameDefaultsKey = "jira.oauth.accountName"

    private let defaults: UserDefaults
    private let keychainService: String
    private let readToken: @Sendable (String, String) -> String?
    private let writeToken: @Sendable (String, String, String) throws -> Void
    private let deleteToken: @Sendable (String, String) -> Void

    public init(defaults: UserDefaults = .standard,
                keychainService: String = JiraTokenStore.defaultKeychainService,
                readToken: @escaping @Sendable (String, String) -> String? = {
                    KeychainStore.get(service: $0, account: $1)
                },
                writeToken: @escaping @Sendable (String, String, String) throws -> Void = {
                    try KeychainStore.set($0, service: $1, account: $2)
                },
                deleteToken: @escaping @Sendable (String, String) -> Void = {
                    KeychainStore.delete(service: $0, account: $1)
                }) {
        self.defaults = defaults
        self.keychainService = keychainService
        self.readToken = readToken
        self.writeToken = writeToken
        self.deleteToken = deleteToken
    }

    /// The stored session, or `nil` if any required piece is missing — a
    /// half-written session is treated as no session at all rather than as a
    /// broken one, so the UI just shows "Connect".
    public func load() -> JiraOAuthSession? {
        guard let accessToken = readToken(keychainService, Self.accessTokenAccount),
              let refreshToken = readToken(keychainService, Self.refreshTokenAccount),
              let cloudID = defaults.string(forKey: Self.cloudIDDefaultsKey),
              let siteURL = defaults.string(forKey: Self.siteURLDefaultsKey),
              defaults.object(forKey: Self.expiresAtDefaultsKey) != nil else {
            return nil
        }
        let expiresAt = Date(timeIntervalSince1970: defaults.double(forKey: Self.expiresAtDefaultsKey))
        let scopes = defaults.stringArray(forKey: Self.scopesDefaultsKey) ?? []
        return JiraOAuthSession(accessToken: accessToken,
                                refreshToken: refreshToken,
                                expiresAt: expiresAt,
                                cloudID: cloudID,
                                siteURL: siteURL,
                                scopes: scopes)
    }

    /// Writes secrets first: if the keychain refuses, the defaults still describe
    /// the previous session rather than pointing at tokens that were never saved.
    public func save(_ session: JiraOAuthSession) throws {
        try writeToken(session.accessToken, keychainService, Self.accessTokenAccount)
        try writeToken(session.refreshToken, keychainService, Self.refreshTokenAccount)
        defaults.set(session.expiresAt.timeIntervalSince1970, forKey: Self.expiresAtDefaultsKey)
        defaults.set(session.cloudID, forKey: Self.cloudIDDefaultsKey)
        defaults.set(session.siteURL, forKey: Self.siteURLDefaultsKey)
        defaults.set(session.scopes, forKey: Self.scopesDefaultsKey)
    }

    public func clear() {
        deleteToken(keychainService, Self.accessTokenAccount)
        deleteToken(keychainService, Self.refreshTokenAccount)
        for key in [Self.expiresAtDefaultsKey,
                    Self.cloudIDDefaultsKey,
                    Self.siteURLDefaultsKey,
                    Self.scopesDefaultsKey,
                    Self.accountNameDefaultsKey] {
            defaults.removeObject(forKey: key)
        }
    }

    /// Display name of the connected Atlassian account. Cosmetic only — it is
    /// not part of `JiraOAuthSession` because losing it costs nothing.
    public var accountName: String? {
        get { defaults.string(forKey: Self.accountNameDefaultsKey) }
        nonmutating set {
            if let newValue {
                defaults.set(newValue, forKey: Self.accountNameDefaultsKey)
            } else {
                defaults.removeObject(forKey: Self.accountNameDefaultsKey)
            }
        }
    }
}
