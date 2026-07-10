import Foundation

extension Bundle {
    /// The `Blink` target's resource bundle, resolved from a code-signable location.
    ///
    /// SwiftPM's generated `Bundle.module` only looks at `Bundle.main.bundleURL`
    /// (the `.app` ROOT) plus a hard-coded build path. Putting the resource bundle
    /// at the app root breaks codesign — `codesign --verify --strict` reports
    /// "unsealed contents present in the bundle root", so a copy that arrives
    /// quarantined on another Mac is rejected by Gatekeeper and won't open.
    ///
    /// In the shipped `.app` the bundle therefore lives in `Contents/Resources`
    /// (which `Bundle.main.resourceURL` points to and codesign can seal cleanly).
    /// The `.module` fallback keeps `swift run` / test builds working, where the
    /// bundle sits next to the executable.
    static let blinkAppResources: Bundle = {
        if let res = Bundle.main.resourceURL,
           let bundle = Bundle(url: res.appendingPathComponent("Blink_Blink.bundle")) {
            return bundle
        }
        return .module
    }()
}
