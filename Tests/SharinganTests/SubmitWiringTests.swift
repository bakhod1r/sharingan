import Testing
import Foundation

/// Guards the July-2026 double-add fix. The legacy
/// `TextField(_:text:onCommit:)` initializer fires on Return AND again when
/// the field ends editing — on macOS the field editor re-syncs its stale text
/// into the binding on focus loss, so "add" handlers ran twice and every quick
/// add produced a duplicate task. Several fields even registered the same
/// handler through BOTH `onCommit:` and `.onSubmit`. Submission must be wired
/// through exactly one `.onSubmit` per field, never `onCommit:`.
@Suite("Submit wiring")
struct SubmitWiringTests {

    private static var sourcesRoot: URL {
        // Tests/SharinganTests/SubmitWiringTests.swift → repo root → Sources
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SharinganTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("Sources")
    }

    @Test func noLegacyOnCommitHandlers() throws {
        let fm = FileManager.default
        let enumerator = try #require(fm.enumerator(at: Self.sourcesRoot,
                                                    includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false)
                                 .enumerated()
            where line.contains("onCommit") {
                offenders.append("\(url.lastPathComponent):\(i + 1)")
            }
        }
        #expect(offenders.isEmpty,
                "Legacy onCommit fires twice (Return + end-editing) and duplicates adds; use a single .onSubmit instead: \(offenders)")
    }
}
