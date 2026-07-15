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

@MainActor
public final class JiraService: ObservableObject {
    public static let keychainService = "com.bakhod1r.sharingan.jira"

    public static let siteURLDefaultsKey = "jira.siteURL"
    public static let emailDefaultsKey = "jira.email"
    public static let autoStartTransitionDefaultsKey = "jira.autoStartTransition"
    public static let doneBehaviorDefaultsKey = "jira.doneBehavior"
    public static let autoCompleteLocalDefaultsKey = "jira.autoCompleteLocal"
    public static let worklogSyncDefaultsKey = "jira.worklogSync"
    public static let pushEstimateDefaultsKey = "jira.pushEstimate"
    public static let pollMinutesDefaultsKey = "jira.pollMinutes"

    public enum ConnectionStatus: Equatable, Sendable {
        case disconnected
        case restoring
        case connecting
        case connected(host: String, user: JiraUserIdentity)
        case failed(String)

        public var label: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .restoring: return "Restoring…"
            case .connecting: return "Connecting…"
            case .connected(_, let user): return "Connected as \(user.displayName)"
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
    private let client: JiraClient
    private let keychainService: String
    private let readToken: (String, String) -> String?
    private let writeToken: (String, String, String) throws -> Void
    private let deleteToken: (String, String) -> Void
    private var restoreTask: Task<Void, Never>?

    public init(defaults: UserDefaults = .standard,
                client: JiraClient = JiraClient(),
                keychainService: String = "com.bakhod1r.sharingan.jira",
                readToken: @escaping (String, String) -> String? = KeychainStore.get,
                writeToken: @escaping (String, String, String) throws -> Void = {
                    try KeychainStore.set($0, service: $1, account: $2)
                },
                deleteToken: @escaping (String, String) -> Void = {
                    KeychainStore.delete(service: $0, account: $1)
                }) {
        self.defaults = defaults
        self.client = client
        self.keychainService = keychainService
        self.readToken = readToken
        self.writeToken = writeToken
        self.deleteToken = deleteToken
        restoreTask = Task { [weak self] in
            await self?.restoreStoredSession()
        }
    }

    deinit {
        restoreTask?.cancel()
    }

    public var isConnected: Bool {
        if case .connected = status { return true }
        return false
    }

    public func connect(siteURLString: String, email: String, apiToken: String) async -> Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSite = siteURLString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty, !trimmedToken.isEmpty, !trimmedSite.isEmpty else {
            lastErrorMessage = "Enter your Jira site, email, and API token."
            status = .failed(lastErrorMessage ?? "Missing Jira credentials.")
            return false
        }

        do {
            let normalizedSite = try Self.normalizeSiteURL(trimmedSite)
            status = .connecting
            isWorking = true
            lastErrorMessage = nil
            await client.configure(siteURL: normalizedSite, email: trimmedEmail, apiToken: trimmedToken)
            let myself = try await client.myself()
            let user = JiraUserIdentity(myself: myself)
            try writeToken(trimmedToken, keychainService, normalizedSite.host ?? trimmedSite)
            defaults.set(normalizedSite.absoluteString, forKey: Self.siteURLDefaultsKey)
            defaults.set(trimmedEmail, forKey: Self.emailDefaultsKey)
            currentUser = user
            siteHost = normalizedSite.host
            status = .connected(host: normalizedSite.host ?? normalizedSite.absoluteString,
                                user: user)
            isWorking = false
            return true
        } catch {
            await client.clearConfiguration()
            let jiraError = (error as? JiraError) ?? .network(error.localizedDescription)
            currentUser = nil
            siteHost = nil
            lastErrorMessage = jiraError.userMessage
            status = .failed(jiraError.userMessage)
            isWorking = false
            return false
        }
    }

    public func disconnect() {
        restoreTask?.cancel()
        if let host = savedSiteHost {
            deleteToken(keychainService, host)
        }
        defaults.removeObject(forKey: Self.siteURLDefaultsKey)
        defaults.removeObject(forKey: Self.emailDefaultsKey)
        currentUser = nil
        siteHost = nil
        lastErrorMessage = nil
        status = .disconnected
        isWorking = false
        Task { await client.clearConfiguration() }
    }

    public func refreshIdentity() async {
        guard let siteString = defaults.string(forKey: Self.siteURLDefaultsKey),
              let email = defaults.string(forKey: Self.emailDefaultsKey),
              let siteURL = URL(string: siteString),
              let host = siteURL.host,
              let token = readToken(keychainService, host) else {
            status = .disconnected
            currentUser = nil
            siteHost = nil
            return
        }

        status = .restoring
        isWorking = true
        lastErrorMessage = nil

        do {
            await client.configure(siteURL: siteURL, email: email, apiToken: token)
            let myself = try await client.myself()
            let user = JiraUserIdentity(myself: myself)
            currentUser = user
            siteHost = host
            status = .connected(host: host, user: user)
        } catch {
            await client.clearConfiguration()
            let jiraError = (error as? JiraError) ?? .network(error.localizedDescription)
            currentUser = nil
            siteHost = host
            lastErrorMessage = jiraError.userMessage
            status = .failed(jiraError.userMessage)
        }

        isWorking = false
    }

    private var savedSiteHost: String? {
        guard let siteString = defaults.string(forKey: Self.siteURLDefaultsKey),
              let url = URL(string: siteString) else { return nil }
        return url.host
    }

    private func restoreStoredSession() async {
        await refreshIdentity()
    }

    static func normalizeSiteURL(_ raw: String) throws -> URL {
        let prefixed = raw.contains("://") ? raw : "https://\(raw)"
        guard var components = URLComponents(string: prefixed),
              let host = components.host, !host.isEmpty else {
            throw JiraError.network("Enter a valid Jira site URL.")
        }
        components.scheme = components.scheme?.isEmpty == false ? components.scheme : "https"
        components.user = nil
        components.password = nil
        components.path = ""
        components.query = nil
        components.fragment = nil
        guard let normalized = components.url else {
            throw JiraError.network("Enter a valid Jira site URL.")
        }
        return normalized
    }
}
