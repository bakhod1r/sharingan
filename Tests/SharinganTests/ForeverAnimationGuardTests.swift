import Foundation
import Testing

/// Forever animations keep SwiftUI rendering at display rate (CPU). Only the
/// allowlisted view files may use them.
@Suite struct ForeverAnimationGuardTests {
    /// file -> max allowed occurrences (nil = unlimited)
    private static let allowlist: [String: Int?] = [
        "CameraIndicatorBadge.swift": nil,  // break screen only
        "MenuBarView.swift": 1,             // sync spinner, only while syncing
        "GlassComponents.swift": nil,       // MatrixRainView, Hacker theme
    ]

    @Test func foreverAnimationsOnlyInAllowlistedFiles() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var urls: [URL] = []
        for dir in ["Sources/Sharingan/Views", "Sources/Sharingan/Services"] {
            let base = root.appendingPathComponent(dir)
            let en = try #require(FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil))
            for case let url as URL in en where url.pathExtension == "swift" { urls.append(url) }
        }
        var checked = 0
        for url in urls {
            checked += 1
            let text = try String(contentsOf: url, encoding: .utf8)
            let count = text.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("//") { return false }
                return t.contains("repeatForever") || t.contains("TimelineView(.animation)")
            }.count
            guard count > 0 else { continue }
            let name = url.lastPathComponent
            let limit = Self.allowlist[name]
            let allowed = limit != nil && (limit! == nil || count <= limit!!)
            #expect(allowed, "\(name) has \(count) forever animation(s): they keep SwiftUI rendering every frame (CPU) and must be justified in the allowlist.")
        }
        #expect(checked > 0)
    }
}
