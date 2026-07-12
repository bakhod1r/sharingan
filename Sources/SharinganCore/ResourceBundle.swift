import Foundation

extension Bundle {
    /// The `SharinganCore` target's resource bundle, resolved from a code-signable location.
    ///
    /// See the note in `Sharingan/ResourceBundle.swift`: the SwiftPM-generated
    /// `Bundle.module` expects the bundle at the `.app` root, which breaks the
    /// code signature. In the shipped `.app` the bundle is sealed under
    /// `Contents/Resources` instead; `.module` is the `swift run` / test fallback.
    static let sharinganCoreResources: Bundle = {
        if let res = Bundle.main.resourceURL,
           let bundle = Bundle(url: res.appendingPathComponent("Sharingan_SharinganCore.bundle")) {
            return bundle
        }
        return .module
    }()
}
