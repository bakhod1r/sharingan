import Foundation

extension Bundle {
    /// The `BlinkCore` target's resource bundle, resolved from a code-signable location.
    ///
    /// See the note in `Blink/ResourceBundle.swift`: the SwiftPM-generated
    /// `Bundle.module` expects the bundle at the `.app` root, which breaks the
    /// code signature. In the shipped `.app` the bundle is sealed under
    /// `Contents/Resources` instead; `.module` is the `swift run` / test fallback.
    static let blinkCoreResources: Bundle = {
        if let res = Bundle.main.resourceURL,
           let bundle = Bundle(url: res.appendingPathComponent("Blink_BlinkCore.bundle")) {
            return bundle
        }
        return .module
    }()
}
