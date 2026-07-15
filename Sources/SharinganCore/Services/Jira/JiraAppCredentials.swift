import Foundation

/// The OAuth app's own `client_id` / `client_secret`, baked into the bundle at
/// build time by `Scripts/make-app.sh` from `.env.release`.
///
/// **On the secret's protection — read before changing anything here.**
///
/// Atlassian's OAuth 2.0 (3LO) does not support PKCE and requires
/// `client_secret` in the token exchange, so a distributed desktop app has no
/// way to avoid shipping it. The values below are XOR-masked purely so the
/// secret is not a greppable string: `strings Sharingan | grep ATOA` and
/// automated secret scanners come up empty. That is the entire benefit.
///
/// It is **not** a security boundary. Anyone can recover the secret with a
/// debugger breakpoint on the token request, or by pointing a TLS-intercepting
/// proxy at the app — the app must present the secret to Atlassian, so it must
/// be reconstructible at runtime, by definition. Do not build anything on the
/// assumption that this value is private.
///
/// What a leak actually costs: `client_id` + `client_secret` do not grant
/// access to anyone's Jira. They would let someone stand up a consent screen
/// impersonating Sharingan — a phishing risk to the app's name, not a direct
/// path to user data. The secret can be rotated in the developer console at
/// any time, which invalidates the old one.
///
/// The real fix is a backend that holds the secret and brokers the exchange, so
/// it never ships at all. That is deliberately deferred: Sharingan has no
/// server today, and adding one would put us in the path of users' Jira data.
/// When a backend exists, this type goes away and `JiraOAuth` talks to it
/// instead.
public enum JiraAppCredentials {

    /// Info.plist keys written by `make-app.sh`. Deliberately bland — a key
    /// named "JiraClientSecret" would undo the point of masking the value.
    private enum PlistKey {
        static let clientID = "SHIntegrationAppID"
        static let clientSecret = "SHIntegrationAppKey"
    }

    /// XOR mask. Fixed and public by necessity (it ships in the same binary);
    /// it defeats string extraction, nothing more.
    private static let mask: [UInt8] = [
        0x53, 0x68, 0x61, 0x72, 0x69, 0x6E, 0x67, 0x61,
        0x6E, 0x2D, 0x4A, 0x69, 0x72, 0x61, 0x2D, 0x76, 0x31,
    ]

    /// The OAuth client ID, or nil when the build wasn't given one.
    public static var clientID: String? { unmask(PlistKey.clientID) }

    /// The OAuth client secret, or nil when the build wasn't given one.
    public static var clientSecret: String? { unmask(PlistKey.clientSecret) }

    /// Whether this build can run the OAuth flow at all. Dev builds made with
    /// a plain `swift build` have no baked credentials — the UI uses this to
    /// say so plainly instead of failing at the authorize step with a 400.
    public static var isConfigured: Bool {
        clientID?.isEmpty == false && clientSecret?.isEmpty == false
    }

    private static func unmask(_ key: String) -> String? {
        guard let encoded = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !encoded.isEmpty,
              let data = Data(base64Encoded: encoded) else {
            return nil
        }
        return Self.applyMask(to: data)
    }

    /// XOR round-trip — its own inverse, so `make-app.sh` uses the same routine
    /// to encode. Exposed for the generator and for tests.
    public static func applyMask(to data: Data) -> String? {
        guard !mask.isEmpty else { return nil }
        var out = [UInt8]()
        out.reserveCapacity(data.count)
        for (index, byte) in data.enumerated() {
            out.append(byte ^ mask[index % mask.count])
        }
        return String(bytes: out, encoding: .utf8)
    }

    /// Encode a plaintext value the way `unmask` expects to read it back.
    /// Used by the build script's Swift one-liner and by tests.
    public static func mask(_ plaintext: String) -> String {
        let bytes = Array(plaintext.utf8)
        var out = [UInt8]()
        out.reserveCapacity(bytes.count)
        for (index, byte) in bytes.enumerated() {
            out.append(byte ^ mask[index % mask.count])
        }
        return Data(out).base64EncodedString()
    }
}
