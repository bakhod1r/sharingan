import Testing
import Foundation
@testable import SharinganCore

/// The seam that keeps a preview render out of the user's task database.
///
/// `--render-dev-preview` and `--render-site-assets` seed sample tasks into
/// `TaskStore.shared` so the shots have something to photograph, and
/// `TaskStore.shared` persists — so before this existed, every render left a
/// copy of "Ship landing page v1" and "Review pull request #42" in the user's
/// real list, forever.
///
/// The rule is a pure function of argv, which is what makes it impossible to
/// trip by accident: a normal launch passes no arguments, and a launch that did
/// pass one of these flags would render PNGs and `exit(0)` before it ever became
/// the app.
@Suite("Headless render")
struct HeadlessRenderTests {

    @Test("only the render flags count as a render")
    func onlyRenderFlagsCount() {
        #expect(HeadlessRender.isRender(arguments: ["Sharingan", "--render-dev-preview",
                                                    "/tmp/out"]))
        #expect(HeadlessRender.isRender(arguments: ["Sharingan", "--render-site-assets",
                                                    "/tmp/out"]))
        #expect(HeadlessRender.outputDirectory(for: "--render-dev-preview",
                                               arguments: ["Sharingan", "--render-dev-preview",
                                                           "/tmp/out"]) == "/tmp/out")
    }

    /// **The rule `main.swift` renders on is the rule that redirects the store,
    /// and it is one function.** A flag with no destination after it is not a
    /// render: `main.swift` has nowhere to write, so it falls through and
    /// launches the app — and an app running on a throwaway database would
    /// silently drop everything the user typed into it. The two answers must
    /// agree, so they are the same call.
    @Test("a flag with no destination is not a render — the app runs, and keeps its database")
    func aFlagWithoutADestinationIsNotARender() {
        for args in [["Sharingan", "--render-dev-preview"],
                     ["Sharingan", "--render-site-assets"]] {
            #expect(!HeadlessRender.isRender(arguments: args), "\(args)")
            #expect(HeadlessRender.outputDirectory(for: args[1], arguments: args) == nil)
        }
    }

    /// The important half: everything a *normal* launch can look like, and every
    /// near miss, is not a render. A Finder/Dock launch passes no arguments at
    /// all; `-psn_…` is what LaunchServices used to add; the rest are the app's
    /// own CLI, which really is the app and really must keep its database.
    @Test("a normal launch is never a render")
    func normalLaunchIsNeverARender() {
        let normal: [[String]] = [
            [],
            ["/Applications/Blink.app/Contents/MacOS/Sharingan"],
            ["Sharingan", "-psn_0_123456"],
            ["Sharingan", "task", "add", "Write the report"],
            ["Sharingan", "--help"],
            // The other headless flags draw a view and exit without ever opening
            // the task store, so they are not renders in this sense and must not
            // redirect it.
            ["Sharingan", "--render-icon", "/tmp/icon.png"],
            ["Sharingan", "--render-break-preview", "/tmp/b.png"],
            // Near misses: a flag that is a prefix, a suffix or a substring of a
            // real one. Matching is whole-argument equality, so none of these
            // are a render.
            ["Sharingan", "--render"],
            ["Sharingan", "--render-dev-preview=/tmp/out"],
            ["Sharingan", "-render-dev-preview"],
            ["Sharingan", "--no-render-dev-preview"],
            ["Sharingan", "ship --render-dev-preview today"],
        ]
        for args in normal {
            #expect(!HeadlessRender.isRender(arguments: args), "\(args)")
        }
    }

    /// The throwaway is under the temp directory, per process, and is emphatically
    /// not the real database.
    @Test("the throwaway database is a temp file, never Application Support")
    func throwawayIsATempFile() {
        let url = HeadlessRender.throwawayDatabaseURL(pid: 4242)
        let path = url.path
        #expect(path.hasSuffix("blink.sqlite"))
        #expect(path.contains("Sharingan-render-4242"))
        #expect(!path.contains("Application Support"))
        #expect(url.deletingLastPathComponent().path
                    .hasPrefix(FileManager.default.temporaryDirectory.path))
        // Per process, so two renders never share a file.
        #expect(HeadlessRender.throwawayDatabaseURL(pid: 1) !=
                HeadlessRender.throwawayDatabaseURL(pid: 2))
    }

    /// And the suite itself is not a render: the test process's own argv has no
    /// render flag, so `TaskStore()` in every other test still resolves the way
    /// it always did (and the tests that need isolation still pass `fileURL:`).
    @Test("the test process is not a render")
    func testProcessIsNotARender() {
        #expect(!HeadlessRender.isActive)
    }
}
