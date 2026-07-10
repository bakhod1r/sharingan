# Menu bar toggle + Daily goal + DND Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the three approved conveniences: a Settings toggle for the menu-bar countdown, daily-goal completion notification + goal progress on the Stats page, and Focus/DND toggling through user-created Shortcuts.

**Architecture:** All state lives in `PomodoroSettings` (one JSON blob in UserDefaults, defensively decoded field-by-field). Timer-side logic goes in BlinkCore (testable); AppKit/SwiftUI surfaces consume it. DND is a new BlinkCore service wrapping `/usr/bin/shortcuts run <name>` with an injected process runner; `BlinkCoordinator` drives it from timer state edges.

**Tech Stack:** Swift 5 / SwiftPM (no Xcode project), SwiftUI + AppKit, Swift Testing (`import Testing`, `@Test`, `#expect`) in `Tests/BlinkTests`.

**Spec:** `docs/superpowers/specs/2026-07-10-menubar-goal-dnd-design.md`

## Global Constraints

- Build with `swift build`, test with `swift test` from the repo root.
- New `PomodoroSettings` fields MUST get a `decodeIfPresent … ?? d.<field>` line in `init(from:)` (older blobs must not reset settings). `CodingKeys` is synthesized — adding the property is enough for the key.
- Follow existing UI idioms: `ToggleRow(title:isOn:)`, `StepperRow(title:value:unit:)`, `DarkGlassFieldStyle()` for text fields, `Section("…") { }` in `SettingsView.categorySections`.
- Commit after every task; push after every commit (multi-Mac workflow).
- Daily goal setting already exists: `PomodoroSettings.dailyPomodoroGoal: Int = 8` (0 = off), Settings stepper, and the popover `dailyGoalBar` are DONE — do not re-add them.

---

### Task 1: Menu bar countdown toggle

**Files:**
- Modify: `Sources/BlinkCore/Models/PomodoroSettings.swift` (property block ~line 92, `init(from:)` ~line 160)
- Modify: `Sources/Blink/AppDelegate.swift:60-69` (`updateTitle`)
- Modify: `Sources/Blink/Views/SettingsView.swift` (case `.timer`, after the `Section("Floating timer")` block)
- Test: `Tests/BlinkTests/PomodoroModelsTests.swift`

**Interfaces:**
- Produces: `PomodoroSettings.showMenuBarCountdown: Bool` (default `true`) — read by `AppDelegate.updateTitle()`.

- [x] **Step 1: Write the failing test** (append to `PomodoroModelsTests.swift`)

```swift
@Suite("Menu bar countdown setting")
struct MenuBarCountdownSettingTests {
    @Test func defaultsToOn() {
        #expect(PomodoroSettings().showMenuBarCountdown == true)
    }

    @Test func decodingOldBlobWithoutKeyFallsBackToDefault() throws {
        let old = try JSONSerialization.data(withJSONObject: ["focusMinutes": 30])
        let s = try JSONDecoder().decode(PomodoroSettings.self, from: old)
        #expect(s.showMenuBarCountdown == true)
        #expect(s.focusMinutes == 30)
    }

    @Test func roundTripsWhenOff() throws {
        var s = PomodoroSettings()
        s.showMenuBarCountdown = false
        let back = try JSONDecoder().decode(PomodoroSettings.self,
                                            from: JSONEncoder().encode(s))
        #expect(back.showMenuBarCountdown == false)
    }
}
```

- [x] **Step 2: Run to verify it fails**

Run: `swift test --filter MenuBarCountdownSettingTests`
Expected: compile error — `showMenuBarCountdown` not defined.

- [x] **Step 3: Add the setting**

In `PomodoroSettings.swift`, after the `tagStyles` property:

```swift
    /// Show the MM:SS countdown next to the menu-bar icon while a session
    /// is engaged (off = icon only).
    public var showMenuBarCountdown: Bool = true
```

At the end of `init(from:)`, after the `tagStyles` line:

```swift
        showMenuBarCountdown = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarCountdown) ?? d.showMenuBarCountdown
```

- [x] **Step 4: Run tests**

Run: `swift test --filter MenuBarCountdownSettingTests`
Expected: 3 PASS.

- [x] **Step 5: Honor it in the menu bar**

In `AppDelegate.updateTitle()` replace the `engaged` line pair:

```swift
        let engaged = timer.isRunning
            || (timer.remainingSeconds > 0 && timer.remainingSeconds < timer.totalSeconds)
        let show = engaged && timer.settings.showMenuBarCountdown
        button.title = show ? String(format: " %02d:%02d", Int(s) / 60, Int(s) % 60) : ""
```

- [x] **Step 6: Settings toggle**

In `SettingsView.categorySections`, case `.timer`, directly after the closing brace of `Section("Floating timer") { … }`:

```swift
                Section("Menu bar") {
                    ToggleRow(title: "Show countdown in menu bar",
                              isOn: $settings.showMenuBarCountdown)
                }
```

- [x] **Step 7: Build + full tests**

Run: `swift build && swift test`
Expected: Build complete, all tests pass.

- [x] **Step 8: Commit + push**

```bash
git add Sources/BlinkCore/Models/PomodoroSettings.swift Sources/Blink/AppDelegate.swift Sources/Blink/Views/SettingsView.swift Tests/BlinkTests/PomodoroModelsTests.swift
git commit -m "feat: menu bar countdown can be hidden via Settings"
git push
```

---

### Task 2: Daily-goal-reached notification

**Files:**
- Modify: `Sources/BlinkCore/Services/PomodoroTimer.swift` (`phaseComplete()` ~line 184, `Notification.Name` extension ~line 331)
- Modify: `Sources/BlinkCore/Services/BlinkCoordinator.swift` (`observe()` ~line 165)
- Test: `Tests/BlinkTests/ServicesTests.swift`

**Interfaces:**
- Consumes: `stats.registerFocusCompletion()`, `stats.completedTodayCount()`, `settings.dailyPomodoroGoal`.
- Produces: `PomodoroTimer.goalJustReached(count:goal:) -> Bool` (static, pure); `Notification.Name.dailyGoalReached` posted with `userInfo: ["count": Int]`.

- [x] **Step 1: Write the failing test** (append to `ServicesTests.swift`)

```swift
@Suite("Daily goal trigger")
struct DailyGoalTriggerTests {
    @Test func firesExactlyAtTheGoal() {
        #expect(PomodoroTimer.goalJustReached(count: 8, goal: 8))
    }
    @Test func silentBeforeAndAfterTheGoal() {
        #expect(!PomodoroTimer.goalJustReached(count: 7, goal: 8))
        #expect(!PomodoroTimer.goalJustReached(count: 9, goal: 8))
    }
    @Test func disabledGoalNeverFires() {
        #expect(!PomodoroTimer.goalJustReached(count: 0, goal: 0))
        #expect(!PomodoroTimer.goalJustReached(count: 5, goal: 0))
    }
}
```

- [x] **Step 2: Run to verify it fails**

Run: `swift test --filter DailyGoalTriggerTests`
Expected: compile error — `goalJustReached` not defined.

- [x] **Step 3: Implement trigger + post**

In `PomodoroTimer`, add near `phaseComplete()`:

```swift
    /// True only at the exact completion that lands on the goal, so the
    /// celebration fires once per day without any extra persisted state.
    public static func goalJustReached(count: Int, goal: Int) -> Bool {
        goal > 0 && count == goal
    }
```

In `phaseComplete()`, inside the `if phase == .focus { … }` block, after the `.streakUpdated` post:

```swift
            if Self.goalJustReached(count: stats.completedTodayCount(),
                                    goal: settings.dailyPomodoroGoal) {
                NotificationCenter.default.post(
                    name: .dailyGoalReached, object: self,
                    userInfo: ["count": settings.dailyPomodoroGoal])
            }
```

In the `Notification.Name` extension at the bottom of the file:

```swift
    static let dailyGoalReached = Notification.Name("blink.dailyGoalReached")
```

- [x] **Step 4: Run tests**

Run: `swift test --filter DailyGoalTriggerTests`
Expected: 3 PASS.

- [x] **Step 5: Surface it as a macOS notification**

In `BlinkCoordinator.observe()`, after the `.streakUpdated` subscription block:

```swift
        NotificationCenter.default.publisher(for: .dailyGoalReached)
            .receive(on: RunLoop.main)
            .sink { note in
                let n = note.userInfo?["count"] as? Int ?? 0
                NotificationService.shared.notify(
                    title: "Daily goal reached 🎯",
                    body: "\(n)/\(n) pomodoros today. Great work!",
                    identifier: "blink.dailyGoal")
            }
            .store(in: &cancellables)
```

- [x] **Step 6: Build + full tests**

Run: `swift build && swift test`
Expected: all pass.

- [x] **Step 7: Commit + push**

```bash
git add Sources/BlinkCore/Services/PomodoroTimer.swift Sources/BlinkCore/Services/BlinkCoordinator.swift Tests/BlinkTests/ServicesTests.swift
git commit -m "feat: notification when the daily pomodoro goal is reached"
git push
```

---

### Task 3: Goal progress on the Stats page

**Files:**
- Modify: `Sources/Blink/Views/StatsSummaryView.swift` (metrics array ~line 24)
- Modify: `Sources/Blink/Views/MainWindowView.swift` (~line 763, `StatsSummaryView(...)` call)

**Interfaces:**
- Consumes: `stats.completedTodayCount()`, new `dailyGoal` view parameter.

No unit test — pure SwiftUI presentation; verified by build + manual look.

- [x] **Step 1: Thread the goal into the view**

In `StatsSummaryView`, add below `var accent`:

```swift
    /// Today's pomodoro target (0 = no goal configured).
    var dailyGoal: Int = 0
```

Replace the "Today" metric entry:

```swift
            Metric("calendar", "\(stats.completedTodayCount())", "Today",
                   .green),
```

with:

```swift
            Metric("calendar",
                   dailyGoal > 0
                       ? "\(stats.completedTodayCount())/\(dailyGoal)"
                       : "\(stats.completedTodayCount())",
                   dailyGoal > 0 ? "Today · goal" : "Today",
                   .green,
                   sub: dailyGoal > 0 && stats.completedTodayCount() >= dailyGoal
                       ? "goal reached 🎯" : nil),
```

- [x] **Step 2: Pass it at the call site**

In `MainWindowView` (case `.stats`), extend the existing call:

```swift
                    StatsSummaryView(stats: timer.stats,
                                     focusMinutes: timer.settings.focusMinutes,
                                     accent: timer.settings.theme.accent,
                                     dailyGoal: timer.settings.dailyPomodoroGoal)
```

(Keep whatever argument list already exists — only add `dailyGoal:` last.)

- [x] **Step 3: Build**

Run: `swift build`
Expected: Build complete.

- [x] **Step 4: Commit + push**

```bash
git add Sources/Blink/Views/StatsSummaryView.swift Sources/Blink/Views/MainWindowView.swift
git commit -m "feat(stats): Today card shows daily-goal progress"
git push
```

---

### Task 4: DND settings fields + DNDShortcutService

**Files:**
- Modify: `Sources/BlinkCore/Models/PomodoroSettings.swift`
- Create: `Sources/BlinkCore/Services/DNDShortcutService.swift`
- Test: `Tests/BlinkTests/ServicesTests.swift`

**Interfaces:**
- Produces: `PomodoroSettings.dndEnabled: Bool` (default `false`), `dndShortcutOn: String` (default `"Blink Focus On"`), `dndShortcutOff: String` (default `"Blink Focus Off"`).
- Produces: `DNDShortcutService` with `static let shared`, `init(runner:)`, `sync(focusActive:settings:)`, `deactivate(settings:)`, `run(_ name: String)`, `@Published private(set) var lastResult: [String: RunResult]`, `enum RunResult: Equatable { case success; case failure(String) }`, `typealias Runner = (String, [String], @escaping (Int32, String) -> Void) -> Void`.

- [x] **Step 1: Write the failing tests** (append to `ServicesTests.swift`)

```swift
@Suite("DND shortcut service")
struct DNDShortcutServiceTests {
    /// Captures runner invocations synchronously.
    final class Spy {
        var calls: [(path: String, args: [String])] = []
        func runner(_ path: String, _ args: [String],
                    _ done: @escaping (Int32, String) -> Void) {
            calls.append((path, args))
            done(0, "")
        }
    }

    func makeSettings(enabled: Bool = true) -> PomodoroSettings {
        var s = PomodoroSettings()
        s.dndEnabled = enabled
        return s
    }

    @Test func focusStartRunsTheOnShortcutOnce() {
        let spy = Spy()
        let svc = DNDShortcutService(runner: spy.runner)
        let s = makeSettings()
        svc.sync(focusActive: true, settings: s)
        svc.sync(focusActive: true, settings: s)   // no edge — no extra run
        #expect(spy.calls.count == 1)
        #expect(spy.calls[0].path == "/usr/bin/shortcuts")
        #expect(spy.calls[0].args == ["run", "Blink Focus On"])
    }

    @Test func focusEndRunsTheOffShortcut() {
        let spy = Spy()
        let svc = DNDShortcutService(runner: spy.runner)
        let s = makeSettings()
        svc.sync(focusActive: true, settings: s)
        svc.sync(focusActive: false, settings: s)
        #expect(spy.calls.map(\.args) == [["run", "Blink Focus On"],
                                          ["run", "Blink Focus Off"]])
    }

    @Test func disabledSettingIsANoOp() {
        let spy = Spy()
        let svc = DNDShortcutService(runner: spy.runner)
        svc.sync(focusActive: true, settings: makeSettings(enabled: false))
        #expect(spy.calls.isEmpty)
    }

    @Test func disablingMidFocusTearsDown() {
        let spy = Spy()
        let svc = DNDShortcutService(runner: spy.runner)
        svc.sync(focusActive: true, settings: makeSettings())
        svc.sync(focusActive: true, settings: makeSettings(enabled: false))
        #expect(spy.calls.map(\.args) == [["run", "Blink Focus On"],
                                          ["run", "Blink Focus Off"]])
    }

    @Test func deactivateIsBestEffortAndIdempotent() {
        let spy = Spy()
        let svc = DNDShortcutService(runner: spy.runner)
        let s = makeSettings()
        svc.deactivate(settings: s)                 // never engaged — no run
        svc.sync(focusActive: true, settings: s)
        svc.deactivate(settings: s)
        svc.deactivate(settings: s)                 // second call — no run
        #expect(spy.calls.map(\.args) == [["run", "Blink Focus On"],
                                          ["run", "Blink Focus Off"]])
    }

    @Test func emptyShortcutNameNeverSpawnsAProcess() {
        let spy = Spy()
        let svc = DNDShortcutService(runner: spy.runner)
        svc.run("   ")
        #expect(spy.calls.isEmpty)
    }

    @Test func settingsFieldsDefaultAndDecode() throws {
        let d = PomodoroSettings()
        #expect(d.dndEnabled == false)
        #expect(d.dndShortcutOn == "Blink Focus On")
        #expect(d.dndShortcutOff == "Blink Focus Off")
        let old = try JSONSerialization.data(withJSONObject: ["focusMinutes": 25])
        let s = try JSONDecoder().decode(PomodoroSettings.self, from: old)
        #expect(s.dndEnabled == false)
    }
}
```

- [x] **Step 2: Run to verify it fails**

Run: `swift test --filter DNDShortcutServiceTests`
Expected: compile error — `DNDShortcutService` / `dndEnabled` not defined.

- [x] **Step 3: Add the settings fields**

In `PomodoroSettings.swift`, after `showMenuBarCountdown` (Task 1):

```swift
    /// Toggle macOS Focus during focus sessions by running user-created
    /// Shortcuts (there is no public Focus API).
    public var dndEnabled: Bool = false
    public var dndShortcutOn: String = "Blink Focus On"
    public var dndShortcutOff: String = "Blink Focus Off"
```

In `init(from:)`, after the `showMenuBarCountdown` line:

```swift
        dndEnabled = try c.decodeIfPresent(Bool.self, forKey: .dndEnabled) ?? d.dndEnabled
        dndShortcutOn = try c.decodeIfPresent(String.self, forKey: .dndShortcutOn) ?? d.dndShortcutOn
        dndShortcutOff = try c.decodeIfPresent(String.self, forKey: .dndShortcutOff) ?? d.dndShortcutOff
```

- [x] **Step 4: Create the service**

`Sources/BlinkCore/Services/DNDShortcutService.swift`:

```swift
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
```

- [x] **Step 5: Run tests**

Run: `swift test --filter DNDShortcutServiceTests`
Expected: 7 PASS.

- [x] **Step 6: Build + full tests, commit + push**

```bash
swift build && swift test
git add Sources/BlinkCore/Models/PomodoroSettings.swift Sources/BlinkCore/Services/DNDShortcutService.swift Tests/BlinkTests/ServicesTests.swift
git commit -m "feat: DNDShortcutService — Focus toggling via Shortcuts, settings fields"
git push
```

---

### Task 5: DND Settings UI

**Files:**
- Modify: `Sources/Blink/Views/SettingsView.swift` (case `.focus`, after `Section("App blocking") { … }` closes, ~line 397)

**Interfaces:**
- Consumes: `settings.dndEnabled/dndShortcutOn/dndShortcutOff`, `DNDShortcutService.shared.run(_:)`, `.lastResult`.

No unit test — SwiftUI form; verified by build + manual look.

- [x] **Step 1: Add the section**

Insert between `Section("App blocking")` and `Section("Reminders …")` in case `.focus`:

```swift
                Section("Do Not Disturb") {
                    ToggleRow(title: "Turn on Focus during focus sessions",
                              isOn: $settings.dndEnabled)
                    if settings.dndEnabled {
                        dndShortcutRow(label: "On shortcut",
                                       name: $settings.dndShortcutOn)
                        dndShortcutRow(label: "Off shortcut",
                                       name: $settings.dndShortcutOff)
                        Button {
                            NSWorkspace.shared.open(URL(string: "shortcuts://")!)
                        } label: {
                            Label("Open Shortcuts app",
                                  systemImage: "arrow.up.forward.app")
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                        }
                        .buttonStyle(.pressableSubtle)
                        Text("Create two shortcuts with these names: one sets a Focus (e.g. Do Not Disturb) on, the other turns it off. Blink runs them when a focus session starts and ends.")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
```

- [x] **Step 2: Add the row helper**

Add as a private method on `SettingsView` (next to the other private helpers, e.g. below `categorySections`):

```swift
    /// One DND shortcut: editable name + Test button + last-run status.
    @ViewBuilder
    private func dndShortcutRow(label: String, name: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(.caption, design: .rounded).weight(.medium))
                .frame(width: 84, alignment: .leading)
            TextField("Shortcut name", text: name)
                .textFieldStyle(DarkGlassFieldStyle())
            switch dndService.lastResult[name.wrappedValue
                .trimmingCharacters(in: .whitespaces)] {
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("Shortcut ran successfully")
            case .failure(let msg):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help("Failed: \(msg)")
            case nil:
                EmptyView()
            }
            Button("Test") { dndService.run(name.wrappedValue) }
                .buttonStyle(.pressableSubtle)
                .font(.system(.caption, design: .rounded).weight(.semibold))
        }
    }
```

And add the observed service near `@Binding var settings` at the top of `SettingsView`:

```swift
    @ObservedObject private var dndService = DNDShortcutService.shared
```

- [x] **Step 3: Build**

Run: `swift build`
Expected: Build complete. (If `switch` in a ViewBuilder complains on the optional, bind it first: `let result = dndService.lastResult[…]` then `if case`.)

- [x] **Step 4: Commit + push**

```bash
git add Sources/Blink/Views/SettingsView.swift
git commit -m "feat(settings): Do Not Disturb section — shortcut names, test buttons, status"
git push
```

---

### Task 6: Wire DND to the timer lifecycle

**Files:**
- Modify: `Sources/BlinkCore/Services/BlinkCoordinator.swift` (`observe()` ~line 165)
- Modify: `Sources/Blink/AppDelegate.swift` (add `applicationWillTerminate`)

**Interfaces:**
- Consumes: `DNDShortcutService.shared.sync(focusActive:settings:)`, `.deactivate(settings:)`; `timer.$isRunning`, `timer.phase`, `.phaseDidComplete`.
- Produces: `BlinkCoordinator.syncDND()` (public, also called on settings changes).

- [x] **Step 1: Add syncDND to the coordinator**

```swift
    /// DND follows "a focus session is actually running" — pausing or
    /// finishing focus restores normal mode; breaks never engage it.
    public func syncDND() {
        DNDShortcutService.shared.sync(
            focusActive: timer.isRunning && timer.phase == .focus,
            settings: timer.settings)
    }
```

Call it from the existing subscriptions in `observe()`:
- inside the `timer.$isRunning` sink, after `self.refreshAppBlocker()`: `self.syncDND()`
- inside the `timer.$settings` sink, after `self?.syncAll()`: `self?.syncDND()`
- at the top of `handlePhaseComplete(_:)`, first line after the `guard`: `syncDND()`

- [x] **Step 2: Best-effort teardown on quit**

In `AppDelegate` (it already has the `timer` property), add:

```swift
    func applicationWillTerminate(_ notification: Notification) {
        if let timer {
            DNDShortcutService.shared.deactivate(settings: timer.settings)
        }
    }
```

(If `timer` is non-optional there, drop the `if let`.)

- [x] **Step 3: Build + full tests**

Run: `swift build && swift test`
Expected: all pass.

- [x] **Step 4: Manual smoke test**

Run the app (`swift run Blink` or `make`), enable DND in Settings → Focus, press Test on both shortcuts (⚠︎ expected if the user hasn't created them yet — the indicator must show the warning, not crash). Start/stop a focus session and confirm `shortcuts run` fires (status indicator updates).

- [x] **Step 5: Commit + push**

```bash
git add Sources/BlinkCore/Services/BlinkCoordinator.swift Sources/Blink/AppDelegate.swift
git commit -m "feat: Focus/DND follows the pomodoro lifecycle via Shortcuts"
git push
```
