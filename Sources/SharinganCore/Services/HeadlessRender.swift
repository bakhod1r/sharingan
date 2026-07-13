import Foundation

/// The launch flags that make this process a *renderer* instead of the app.
///
/// `main.swift` answers either flag by writing PNGs and calling `exit(0)`: the
/// process never reaches `NSApplication.run()`, never installs the coordinator,
/// never shows a window. It is a camera, not a session.
///
/// Which matters because both render blocks *seed sample tasks* — "Ship landing
/// page v1", "Review pull request #42" — into `TaskStore.shared` so the shots
/// have something to photograph. And `TaskStore.shared` persists: until this
/// seam existed, every render permanently injected those fakes into the user's
/// real SQLite in Application Support (the `HOME=` override the site-assets
/// block used to rely on does not work — `FileManager.urls(for:in:)` does not
/// read `$HOME`).
///
/// So `TaskStore` asks *here* whether the process is a render, and points the
/// shared store at a throwaway file when it is.
///
/// **Why this cannot fire in a normal launch.** The seam is the running
/// process's own argv, and nothing else — not a preference, not a setting, not
/// an environment variable a shell could have exported into the app's
/// environment, not a marker file. A normal launch (Finder, Dock, LaunchServices,
/// `open -a`) passes no arguments at all; a launch that somehow *did* carry one
/// of these flags would not be a normal launch, because `main.swift` would
/// photograph the UI and exit before the app existed. The two facts are welded
/// together: the same argument that redirects the database is the argument that
/// stops the process from becoming Blink.
public enum HeadlessRender {
    /// Every flag `main.swift` seeds sample tasks and renders-and-exits on. A
    /// flag added there without being added here is a flag that writes to the
    /// user's database again.
    ///
    /// (The other `--render-*` flags — the icon, the iris grid, the break
    /// preview — draw a view and exit without ever touching `TaskStore`, so they
    /// have no business redirecting it.)
    public static let flags = ["--render-dev-preview", "--render-site-assets"]

    /// Where a render was told to write, `nil` if this is not that render.
    ///
    /// **This is the rule, and `main.swift` calls it rather than reimplementing
    /// it.** A flag with nothing after it is *not* a render: there is no
    /// destination, so `main.swift` cannot photograph anything and falls through
    /// to launching the app. If this function and that check ever disagreed, the
    /// disagreement would be the worst outcome available — the *real app*,
    /// running on a throwaway database, quietly dropping everything the user
    /// typed into it. One rule, one place, or the bug comes back sideways.
    public static func outputDirectory(for flag: String,
                                       arguments: [String] = CommandLine.arguments) -> String? {
        guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }

    /// Pure, so the rule is tested without launching a process.
    public static func isRender(arguments: [String]) -> Bool {
        flags.contains { outputDirectory(for: $0, arguments: arguments) != nil }
    }

    /// This process.
    public static var isActive: Bool { isRender(arguments: CommandLine.arguments) }

    /// Where a render's tasks go instead: a fresh directory per process, under
    /// the system temp dir. Never Application Support, and never a path the app
    /// would read back on a later launch — a render starts from an empty list
    /// every time, which is also what makes the previews deterministic.
    public static func throwawayDatabaseURL(
        pid: Int32 = ProcessInfo.processInfo.processIdentifier
    ) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Sharingan-render-\(pid)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("blink.sqlite")
    }
}
