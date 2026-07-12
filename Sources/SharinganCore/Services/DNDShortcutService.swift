import Foundation

/// Toggles macOS Focus ("Do Not Disturb") by running user-created Shortcuts
/// via `/usr/bin/shortcuts run <name>` — macOS has no public Focus API. The
/// process runner is injected so tests never spawn real processes.
public final class DNDShortcutService: ObservableObject {
    public static let shared = DNDShortcutService()

    public enum RunResult: Equatable {
        case success
        case failure(String)
    }

    /// Last outcome per shortcut name — drives the Settings status indicator.
    @Published public private(set) var lastResult: [String: RunResult] = [:]

    public typealias Runner = (String, [String], @escaping (Int32, String) -> Void) -> Void
    private let runner: Runner
    /// Whether we believe DND is currently engaged; sync only acts on edges
    /// so repeated timer callbacks don't re-run shortcuts.
    private var dndOn = false

    public init(runner: @escaping Runner = DNDShortcutService.processRunner) {
        self.runner = runner
    }

    /// Reconcile DND with the focus state (running focus session or not).
    public func sync(focusActive: Bool, settings: PomodoroSettings) {
        guard settings.dndEnabled else {
            // Feature switched off while engaged — restore normal mode once.
            if dndOn { dndOn = false; run(settings.dndShortcutOff) }
            return
        }
        guard focusActive != dndOn else { return }
        dndOn = focusActive
        run(focusActive ? settings.dndShortcutOn : settings.dndShortcutOff)
    }

    /// Best-effort teardown for app termination; safe to call repeatedly.
    public func deactivate(settings: PomodoroSettings) {
        guard dndOn else { return }
        dndOn = false
        run(settings.dndShortcutOff)
    }

    /// Run one shortcut by name (also behind the Settings "Test" buttons).
    public func run(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        runner("/usr/bin/shortcuts", ["run", trimmed]) { [weak self] code, err in
            let result: RunResult = code == 0
                ? .success
                : .failure(err.isEmpty ? "exit code \(code)" : err)
            if Thread.isMainThread {
                self?.lastResult[trimmed] = result
            } else {
                DispatchQueue.main.async { self?.lastResult[trimmed] = result }
            }
        }
    }

    /// The real runner: spawns the process off the main thread, reports the
    /// exit status and trimmed stderr (where `shortcuts` prints its errors).
    public static func processRunner(_ path: String, _ args: [String],
                                     _ done: @escaping (Int32, String) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
            let errPipe = Pipe()
            p.standardError = errPipe
            p.standardOutput = Pipe()
            do {
                try p.run()
                p.waitUntilExit()
                let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                done(p.terminationStatus,
                     String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            } catch {
                done(-1, error.localizedDescription)
            }
        }
    }
}
