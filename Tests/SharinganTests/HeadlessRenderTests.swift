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

    // MARK: - What the seam does *not* cover: UserDefaults
    //
    // The database is redirected; the preferences domain is not. These two are
    // the mutations that shipped through that gap, and the properties that make
    // the fixes correct rather than merely careful.

    /// **Why `--render-site-assets` never had to clear the user's focus queue.**
    ///
    /// It used to call `AppServices.focusQueue.clear()` to keep the user's queued
    /// tasks out of the screenshots — and `FocusQueue` persists, so it emptied
    /// the real, planned queue, permanently, every time the site was rebuilt.
    ///
    /// It was redundant on top of destructive. The queue holds *ids*; a render
    /// resolves them against the throwaway store, which has never heard of them.
    /// The ids fall out on their own: what the island lists is exactly the sample
    /// tasks the render seeded, in their own order.
    @Test("a render's queued ids resolve to nothing, so no clearing is needed")
    func theUsersQueueVanishesFromARenderWithoutBeingCleared() {
        // The render's throwaway store: only the seeded samples exist here.
        let seeded = [TaskItem(title: "Ship landing page v1"),
                      TaskItem(title: "Review pull request #42")]
        // The user's real queue, read out of their real defaults: ids of tasks
        // that live in the *real* database, which this process never opened.
        let usersQueue = [UUID(), UUID(), UUID()]

        let rows = NotchTaskRows.rows(today: seeded, queue: usersQueue, limit: 5)

        #expect(rows.map(\.title) == ["Ship landing page v1", "Review pull request #42"])
        // And nothing of the user's leaks into the shot.
        #expect(!rows.contains { usersQueue.contains($0.id) })
    }

    /// The same property from the queue's own validated read: ids that resolve to
    /// nothing in the store it is handed are skipped, not shown. (Isolated
    /// defaults — this read *persists* the drop, which is exactly why no render
    /// may call it against the throwaway store.)
    @MainActor
    @Test("the validated read skips ids the store does not have")
    func validatedReadSkipsUnresolvableIDs() {
        let suite = "blink-render-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TaskStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("blink-render-\(UUID().uuidString).sqlite"))

        let queue = FocusQueue(defaults: defaults)
        queue.enqueue(UUID())
        queue.enqueue(UUID())

        #expect(queue.current(validatedAgainst: store) == nil)
    }

    /// **`PomodoroTimer.settings` persists in its `didSet`.** So the way
    /// `--render-break-preview` used to dress its shot —
    /// `timer.settings.breakBackgroundStyle = style` — rewrote the user's real
    /// break background as a side effect of taking a screenshot. A render builds
    /// the value and hands it to `init` instead, and an assignment inside `init`
    /// does not fire `didSet`: nothing is written.
    @MainActor
    @Test("building a timer from a settings value writes nothing to the defaults")
    func initFromSettingsValueDoesNotPersist() {
        let key = PomodoroSettings.defaultsKey
        let before = UserDefaults.standard.data(forKey: key)

        var settings = PomodoroTimer.savedSettings()
        settings.breakBackgroundStyle = settings.breakBackgroundStyle == .slate
            ? .graphite : .slate
        let timer = PomodoroTimer(settings: settings)

        // The view sees the styled settings...
        #expect(timer.settings.breakBackgroundStyle == settings.breakBackgroundStyle)
        // ...and the user's stored settings are byte-for-byte what they were.
        #expect(UserDefaults.standard.data(forKey: key) == before)
    }

    /// **Merely constructing a timer used to write to the user's defaults.**
    /// `stats` carried a default value, so `self.stats = Self.loadStats()` in
    /// `init` was an assignment through the setter rather than an
    /// initialization: `didSet` fired and re-encoded the stats straight back to
    /// disk. Same values, so nothing was ever visibly lost — but every render
    /// process wrote to the user's preferences, and a write-back of a value
    /// loaded moments earlier is exactly how a concurrently-registered pomodoro
    /// gets clobbered. A render reads; it does not write.
    @MainActor
    @Test("constructing a timer writes nothing — not the settings, not the stats")
    func constructingATimerPersistsNothing() {
        let statsKey = "com.sharingan.stats"          // PomodoroTimer.statsKey
        let settingsKey = PomodoroSettings.defaultsKey
        let statsBefore = UserDefaults.standard.data(forKey: statsKey)
        let settingsBefore = UserDefaults.standard.data(forKey: settingsKey)

        _ = PomodoroTimer()
        _ = PomodoroTimer(settings: PomodoroTimer.savedSettings())

        #expect(UserDefaults.standard.data(forKey: statsKey) == statsBefore)
        #expect(UserDefaults.standard.data(forKey: settingsKey) == settingsBefore)
    }
}
