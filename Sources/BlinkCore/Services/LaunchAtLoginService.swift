import Foundation
#if canImport(ServiceManagement)
import ServiceManagement
#endif

/// Wraps `SMAppService` to register/unregister Blink as a login item.
///
/// `register()` only succeeds when the app runs from a proper, LaunchServices-known
/// `.app` bundle (see `Scripts/make-app.sh`). When launched unbundled via
/// `swift run`, calls fail gracefully and `setEnabled` returns `false`.
@MainActor
public final class LaunchAtLoginService {
    public static let shared = LaunchAtLoginService()

    public init() {}

    /// Whether the login item is currently registered.
    public var isEnabled: Bool {
        #if canImport(ServiceManagement)
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        #endif
        return false
    }

    /// Whether login-item registration is supported in this run context.
    public var isSupported: Bool {
        #if canImport(ServiceManagement)
        if #available(macOS 13.0, *) { return true }
        #endif
        return false
    }

    /// Registers or unregisters the login item. Returns `true` on success.
    @discardableResult
    public func setEnabled(_ enabled: Bool) -> Bool {
        #if canImport(ServiceManagement)
        if #available(macOS 13.0, *) {
            do {
                let service = SMAppService.mainApp
                if enabled {
                    if service.status != .enabled { try service.register() }
                } else {
                    if service.status == .enabled { try service.unregister() }
                }
                return true
            } catch {
                return false
            }
        }
        #endif
        return false
    }
}
