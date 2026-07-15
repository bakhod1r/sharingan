import Foundation
import Security

/// Minimal generic-password Keychain wrapper. The Jira API token is the only
/// secret the app stores, and it must never touch UserDefaults or iCloud —
/// this keeps it in the login keychain, scoped per site host.
///
/// The app is not sandboxed (see `Resources/App.entitlements`), so no
/// keychain-access-group entitlement is needed; the default keychain works.
public enum KeychainStore {

    /// Errors surfaced when the keychain refuses a write. Reads intentionally
    /// return `nil` on any failure — a missing token is a normal state.
    public enum KeychainError: Error, Equatable {
        case unexpectedStatus(OSStatus)
    }

    /// Store (or replace) a secret for `service`/`account`.
    public static func set(_ value: String, service: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Upsert: delete any existing item first, then add fresh. Simpler and
        // more reliable than SecItemUpdate's attribute diffing.
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Fetch a secret, or `nil` if absent or unreadable.
    public static func get(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    /// Remove a secret. No-op if it doesn't exist.
    public static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
