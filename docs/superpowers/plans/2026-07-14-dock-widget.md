# Dock Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A persistent "now playing"-style pill anchored just above the Dock near the Trash, showing the active task, remaining time, and always-standing Start / Stop / Reset buttons.

**Architecture:** A borderless non-activating `NSPanel` (macOS Dock tiles are always square and cannot be widened — the reference video's widget is the same trick) hosting a SwiftUI pill. Plumbing mirrors the Today panel exactly: a `DockWidgetController` protocol in `SharinganCoordinator`, a `syncDockWidget()` driven purely by a new `dockWidgetEnabled` settings flag, and a window manager singleton in the app target.

**Tech Stack:** Swift 5.9, SwiftPM, SwiftUI + AppKit, Swift Testing (`import Testing`, `#expect` — NOT XCTest).

**Spec:** `docs/superpowers/specs/2026-07-14-dock-widget-design.md`

## Global Constraints

- macOS 14+ (`Package.swift` platform floor); build with `swift build`, test with `swift test`.
- `docs/` is wholesale-gitignored but specs/plans/TECHNICAL.md ARE versioned — stage them with `git add -f`.
- Push after every task's commit (multi-Mac workflow; parallel agents advance origin/main — run `git pull --rebase` before starting and before each push).
- Working tree already has unrelated uncommitted edits (AppDelegate.swift, MenuBarView.swift, SettingsView.swift, main.swift, PomodoroSettings.swift) — stage ONLY the hunks/files each task names; never `git add -A`. NEVER include CHANGELOG.md in a commit made from a worktree that will be cherry-picked.
- Target version is the next minor above whatever `CHANGELOG.md` shows at implementation time (1.11.0 as of planning). Tag nothing — tags are cut only on explicit release.
- `dist/Sharingan.app` may be running; to swap it, `mv` the old bundle aside (`rm -rf` is permission-denied on it).

---

### Task 1: `dockWidgetEnabled` settings flag

**Files:**
- Modify: `Sources/SharinganCore/Models/PomodoroSettings.swift` (field near the `floating*` block ~line 192; decode line in `init(from:)` near line 390)
- Test: `Tests/SharinganTests/DockWidgetTests.swift` (new)

**Interfaces:**
- Produces: `PomodoroSettings.dockWidgetEnabled: Bool` (default `true`), Codable-safe against old settings blobs. Tasks 2 and 5 read/write this exact name.

- [ ] **Step 1: Write the failing tests**

Create `Tests/SharinganTests/DockWidgetTests.swift`:

```swift
import Testing
import Foundation
@testable import SharinganCore

@Suite("Dock widget")
struct DockWidgetTests {

    // MARK: - Settings flag

    @Test("dockWidgetEnabled defaults to on")
    func defaultIsOn() {
        #expect(PomodoroSettings().dockWidgetEnabled == true)
    }

    @Test("dockWidgetEnabled survives a codable round trip")
    func codableRoundTrip() throws {
        var s = PomodoroSettings()
        s.dockWidgetEnabled = false
        let decoded = try JSONDecoder().decode(PomodoroSettings.self,
                                               from: JSONEncoder().encode(s))
        #expect(decoded.dockWidgetEnabled == false)
        #expect(decoded == s)
    }

    @Test("old settings blob without the key decodes to the default")
    func defensiveDecode() throws {
        let decoded = try JSONDecoder().decode(PomodoroSettings.self,
                                               from: Data("{}".utf8))
        #expect(decoded.dockWidgetEnabled == true)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DockWidgetTests`
Expected: COMPILE ERROR — `value of type 'PomodoroSettings' has no member 'dockWidgetEnabled'`

- [ ] **Step 3: Add the field and decode line**

In `Sources/SharinganCore/Models/PomodoroSettings.swift`, directly below the
`floatingShowTask` declaration (`public var floatingShowTask: Bool = true`), add:

```swift
    /// Dock widget: a control pill anchored near the Trash end of the Dock —
    /// active task, remaining time, Start / Stop / Reset.
    public var dockWidgetEnabled: Bool = true
```

In `init(from decoder:)`, directly below the `floatingShowTask` decode line
(`floatingShowTask = try c.decodeIfPresent(...) ?? d.floatingShowTask`), add:

```swift
        dockWidgetEnabled = try c.decodeIfPresent(Bool.self, forKey: .dockWidgetEnabled) ?? d.dockWidgetEnabled
```

(`CodingKeys` and `encode(to:)` are compiler-synthesized from the stored
properties — adding the `var` is enough; no enum to edit.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter DockWidgetTests`
Expected: `Test run with 3 tests passed`

- [ ] **Step 5: Commit and push**

```bash
cd /Users/mrb/Desktop/Blink
git add Sources/SharinganCore/Models/PomodoroSettings.swift Tests/SharinganTests/DockWidgetTests.swift
git commit -m "feat(dock-widget): dockWidgetEnabled settings flag"
git pull --rebase && git push
```

CAUTION: `PomodoroSettings.swift` has pre-existing uncommitted edits from other
work. If `git diff` shows hunks unrelated to this task, stage selectively
(`git add -p`) so only the new field + decode line go in.

---

### Task 2: Coordinator plumbing — `DockWidgetController` + `syncDockWidget()`

**Files:**
- Modify: `Sources/SharinganCore/Services/SharinganCoordinator.swift`
- Test: `Tests/SharinganTests/DockWidgetTests.swift` (extend)

**Interfaces:**
- Consumes: `timer.settings.dockWidgetEnabled` (Task 1).
- Produces:
  ```swift
  @MainActor public protocol DockWidgetController: AnyObject {
      func showDockWidget(timer: PomodoroTimer)
      func hideDockWidget()
  }
  ```
  plus `SharinganCoordinator.dockWidgetController: DockWidgetController?` and
  `SharinganCoordinator.syncDockWidget()`. Task 4's manager conforms to this
  exact protocol; AppDelegate assigns the property.

- [ ] **Step 1: Write the failing test**

Append to `Tests/SharinganTests/DockWidgetTests.swift` (inside the
`DockWidgetTests` suite, mirroring `TodayPanelTests.syncFollowsFlag`):

```swift
    // MARK: - Coordinator sync

    /// Records show/hide calls so the sync logic is assertable headless.
    @MainActor
    private final class SpyDockWidget: DockWidgetController {
        var shown = 0
        var hidden = 0
        func showDockWidget(timer: PomodoroTimer) { shown += 1 }
        func hideDockWidget() { hidden += 1 }
    }

    @MainActor
    @Test("syncDockWidget follows the settings flag, not the running state")
    func syncFollowsFlag() {
        let name = "blink-dockwidget-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let coordinator = SharinganCoordinator(timer: PomodoroTimer(),
                                           focusQueue: FocusQueue(defaults: defaults))
        let spy = SpyDockWidget()
        coordinator.dockWidgetController = spy

        // Flag on (the default) → shown, even though nothing is running.
        coordinator.timer.settings.dockWidgetEnabled = true
        coordinator.syncDockWidget()
        #expect(spy.shown == 1)
        #expect(spy.hidden == 0)

        // Flag off → hidden regardless of the timer's running state.
        coordinator.timer.settings.dockWidgetEnabled = false
        coordinator.syncDockWidget()
        #expect(spy.shown == 1)
        #expect(spy.hidden == 1)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DockWidgetTests`
Expected: COMPILE ERROR — `cannot find type 'DockWidgetController' in scope`

- [ ] **Step 3: Implement the coordinator side**

In `Sources/SharinganCore/Services/SharinganCoordinator.swift`:

1. Below the `TodayPanelController` protocol (ends ~line 25), add:

```swift
@MainActor
public protocol DockWidgetController: AnyObject {
    /// Show the Dock-anchored control pill (task + time + Start/Stop/Reset).
    func showDockWidget(timer: PomodoroTimer)
    func hideDockWidget()
}
```

2. Below `public var todayPanelController: TodayPanelController?`, add:

```swift
    public var dockWidgetController: DockWidgetController?
```

3. Below the `syncTodayPanel()` function, add:

```swift
    /// Like the today panel, the dock widget follows its settings flag alone —
    /// it stays up while the timer is idle so Start is always reachable.
    public func syncDockWidget() {
        if timer.settings.dockWidgetEnabled {
            dockWidgetController?.showDockWidget(timer: timer)
        } else {
            dockWidgetController?.hideDockWidget()
        }
    }
```

4. In `syncAll()`, add `syncDockWidget()` on the line after `syncTodayPanel()`.

5. In the settings-diff function (the one with `guard let old = lastSyncedSettings`),
   after the `if old.showTodayPanel != new.showTodayPanel { syncTodayPanel() }`
   line, add:

```swift
        if old.dockWidgetEnabled != new.dockWidgetEnabled { syncDockWidget() }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter DockWidgetTests`
Expected: `Test run with 4 tests passed`

- [ ] **Step 5: Commit and push**

```bash
cd /Users/mrb/Desktop/Blink
git add Sources/SharinganCore/Services/SharinganCoordinator.swift Tests/SharinganTests/DockWidgetTests.swift
git commit -m "feat(dock-widget): DockWidgetController protocol + coordinator sync"
git pull --rebase && git push
```

---

### Task 3: `DockWidgetView` — the pill UI

**Files:**
- Create: `Sources/Sharingan/Views/DockWidgetView.swift`

**Interfaces:**
- Consumes: `PomodoroTimer` published state (`phase`, `progress`, `isRunning`,
  `remainingSeconds`, `settings.timeFormat`), `TaskStore.shared.activeTask`,
  `TaskStore.color(for:)`, `Color(hex:)`, `Font.dsTimer(_:)`, engine controls
  `timer.start() / pause() / stop()`.
- Produces: `struct DockWidgetView: View` with `init(timer: PomodoroTimer)` —
  Task 4 hosts exactly `DockWidgetView(timer: timer)` at 320×56.

- [ ] **Step 1: Create the view**

Create `Sources/Sharingan/Views/DockWidgetView.swift`:

```swift
import SwiftUI
import SharinganCore

/// The Dock widget pill: a "now playing"-style strip anchored to the Dock by
/// DockWidgetWindowManager. Progress ring + active task + remaining time on
/// the left, three always-standing transport buttons on the right —
/// ▶︎ start (resumes a paused session), ⏸ stop (pause), ⟲ reset (the engine's
/// stop(): fresh focus, counters zeroed). Buttons disable rather than hide so
/// the pill never changes shape under the pointer.
struct DockWidgetView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var tasks = TaskStore.shared

    private var phaseColors: [Color] { timer.phase.gradient }

    var body: some View {
        HStack(spacing: 12) {
            ring
            VStack(alignment: .leading, spacing: 2) {
                titleRow
                Text(timer.settings.timeFormat.string(max(0, timer.remainingSeconds)))
                    .font(.dsTimer(17))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.3), value: timer.remainingSeconds)
            }
            Spacer(minLength: 8)
            controls
        }
        .padding(.horizontal, 14)
        .frame(width: 320, height: 56)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Mini progress ring stroked with the phase gradient; dimmed while idle.
    private var ring: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.15), lineWidth: 3.5)
            Circle()
                .trim(from: 0, to: max(0.003, timer.progress))
                .stroke(AngularGradient(colors: phaseColors, center: .center),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 30, height: 30)
        .opacity(timer.isRunning ? 1 : 0.55)
        .animation(.snappy(duration: 0.3), value: timer.progress)
    }

    @ViewBuilder
    private var titleRow: some View {
        if let task = tasks.activeTask {
            HStack(spacing: 5) {
                Circle().fill(Color(hex: tasks.color(for: task.category)))
                    .frame(width: 6, height: 6)
                Text(task.title)
                    .font(.system(size: 12, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
            }
        } else {
            Text("No task selected")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            control("play.fill", enabled: !timer.isRunning, help: "Start") {
                timer.start()
            }
            control("pause.fill", enabled: timer.isRunning, help: "Stop") {
                timer.pause()
            }
            control("arrow.counterclockwise", enabled: true, help: "Reset") {
                timer.stop()
            }
        }
    }

    private func control(_ symbol: String, enabled: Bool, help: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(enabled ? 0.9 : 0.3))
                .frame(width: 26, height: 26)
                .background(Circle().fill(.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build`
Expected: `Build complete!` (no test — SwiftUI views in this repo are verified by build + the manual pass in Task 6; no view is unit-tested here.)

- [ ] **Step 3: Commit and push**

```bash
cd /Users/mrb/Desktop/Blink
git add Sources/Sharingan/Views/DockWidgetView.swift
git commit -m "feat(dock-widget): pill view — ring, task, time, start/stop/reset"
git pull --rebase && git push
```

---

### Task 4: `DockWidgetWindowManager` + AppDelegate wiring

**Files:**
- Create: `Sources/Sharingan/Services/DockWidgetWindowManager.swift`
- Modify: `Sources/Sharingan/AppDelegate.swift` (one line, next to `coord.todayPanelController = TodayPanelWindowManager.shared`)

**Interfaces:**
- Consumes: `DockWidgetController` (Task 2), `DockWidgetView` (Task 3),
  `WindowAnimator.present(_:makeKey:)` / `WindowAnimator.dismiss(_:completion:)`.
- Produces: `DockWidgetWindowManager.shared`, conforming to `DockWidgetController`.

- [ ] **Step 1: Create the manager**

Create `Sources/Sharingan/Services/DockWidgetWindowManager.swift`:

```swift
import AppKit
import SwiftUI
import SharinganCore

/// Hosts the Dock widget (DockWidgetView) in a non-activating borderless
/// NSPanel pinned just above the Dock near its Trash end — macOS Dock tiles
/// are always square, so "widening the Dock" is really a window aligned flush
/// with it. Shown/hidden purely by the `dockWidgetEnabled` settings flag (via
/// SharinganCoordinator.syncDockWidget()); like the today panel it ignores the
/// running state, so Start is always reachable.
@MainActor
final class DockWidgetWindowManager: DockWidgetController {
    static let shared = DockWidgetWindowManager()
    private var panel: NSPanel?
    private var screenObserver: NSObjectProtocol?
    private static let size = NSSize(width: 320, height: 56)

    func showDockWidget(timer: PomodoroTimer) {
        guard panel == nil else { reposition(); return }
        let panel = DockWidgetPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                    .stationary, .ignoresCycle]
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The pill draws its own material; the OS shadow would be a rectangle
        // around the transparent window (same reasoning as the floating timer).
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        // Pinned to the Dock — not user-draggable; placement is recomputed
        // whenever the screen layout (and thus the Dock) changes.
        panel.isMovable = false
        panel.isFloatingPanel = true

        let hosting = NSHostingView(rootView: DockWidgetView(timer: timer))
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        self.panel = panel
        reposition()
        WindowAnimator.present(panel, makeKey: false)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { DockWidgetWindowManager.shared.reposition() }
        }
    }

    func hideDockWidget() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        guard let panel else { return }
        self.panel = nil
        WindowAnimator.dismiss(panel) {
            panel.orderOut(nil)
            panel.contentView = nil
        }
    }

    /// Flush against the Dock's inner edge, near the Trash end. The Dock's
    /// side and thickness fall out of the difference between the screen's
    /// full frame and its visibleFrame; with the Dock auto-hidden the two
    /// (nearly) coincide and the pill rests at the screen edge instead.
    private func reposition() {
        guard let panel, let screen = NSScreen.main else { return }
        let vis = screen.visibleFrame
        let full = screen.frame
        let s = Self.size
        var origin = NSPoint(x: vis.maxX - s.width - 16, y: vis.minY + 4)
        if vis.minX > full.minX {          // Dock on the left
            origin = NSPoint(x: vis.minX + 4, y: vis.minY + 16)
        } else if vis.maxX < full.maxX {   // Dock on the right
            origin = NSPoint(x: vis.maxX - s.width - 4, y: vis.minY + 16)
        }
        panel.setFrame(NSRect(origin: origin, size: s), display: true)
    }
}

private final class DockWidgetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
```

- [ ] **Step 2: Wire it in AppDelegate**

In `Sources/Sharingan/AppDelegate.swift`, directly below
`coord.todayPanelController = TodayPanelWindowManager.shared`, add:

```swift
        coord.dockWidgetController = DockWidgetWindowManager.shared
```

(`syncAll()` already calls `syncDockWidget()` from Task 2, so the widget
appears on launch with no further wiring.)

- [ ] **Step 3: Build and run the full test suite**

Run: `swift build && swift test`
Expected: `Build complete!`, all tests pass (pre-existing failures unrelated to
dock-widget files are not yours to fix — note them and move on).

- [ ] **Step 4: Commit and push**

```bash
cd /Users/mrb/Desktop/Blink
git add Sources/Sharingan/Services/DockWidgetWindowManager.swift Sources/Sharingan/AppDelegate.swift
git commit -m "feat(dock-widget): Dock-anchored panel manager + app wiring"
git pull --rebase && git push
```

CAUTION: `AppDelegate.swift` has pre-existing uncommitted edits — stage with
`git add -p` if the diff contains unrelated hunks.

---

### Task 5: Settings toggle

**Files:**
- Modify: `Sources/Sharingan/Views/SettingsView.swift` (after the `Section("Floating timer")` block, ~line 349)

**Interfaces:**
- Consumes: `$settings.dockWidgetEnabled` (Task 1), existing `ToggleRow`.

- [ ] **Step 1: Add the section**

In `Sources/Sharingan/Views/SettingsView.swift`, directly after the
`Section("Floating timer") { ... }` block, add:

```swift
                Section("Dock widget") {
                    ToggleRow(title: "Dock widget",
                              isOn: $settings.dockWidgetEnabled)
                    Text("A pill above the Dock, near the Trash: active task, time left, and Start / Stop / Reset.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
```

(Match the Today panel section's exact formatting — ToggleRow + caption2 hint.)

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit and push**

```bash
cd /Users/mrb/Desktop/Blink
git add Sources/Sharingan/Views/SettingsView.swift
git commit -m "feat(dock-widget): settings toggle"
git pull --rebase && git push
```

CAUTION: `SettingsView.swift` has pre-existing uncommitted edits — `git add -p`
if needed.

---

### Task 6: Version bump, docs, end-to-end verification

**Files:**
- Modify: `CHANGELOG.md`, `Resources/Info.plist`, `docs/TECHNICAL.md`

- [ ] **Step 1: Determine the version**

Run: `head -12 CHANGELOG.md && /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist`
Take the next minor above the highest version shown (1.11.0 if the repo is
still at 1.10.0 — parallel release agents may have moved it).

- [ ] **Step 2: CHANGELOG entry**

Under `## [Unreleased]` in `CHANGELOG.md`, insert (with today's date and the
version from Step 1):

```markdown
## [1.11.0] — 2026-07-14

### Added
- Dock widget: a "now playing"-style pill anchored just above the Dock near the Trash — active task, remaining time, and always-standing Start / Stop / Reset buttons. On by default; toggle in Settings, next to the floating timer.
```

- [ ] **Step 3: Bump Info.plist**

```bash
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 1.11.0" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist 2>/dev/null \
  && /usr/libexec/PlistBuddy -c "Set :CFBundleVersion 1.11.0" Resources/Info.plist || true
```

- [ ] **Step 4: docs/TECHNICAL.md**

Add a "Dock widget" subsection alongside the floating-timer/today-panel
documentation, covering: the square-tile limitation and the flush-panel trick,
the three files (`DockWidgetWindowManager`, `DockWidgetView`, the
`DockWidgetController` protocol in `SharinganCoordinator`), the
`dockWidgetEnabled` flag (default on, settings-flag-only — not tied to the
running state), and the `visibleFrame`-vs-`frame` placement math including the
left/right-Dock and auto-hide behavior. Bump the version reference at the top
of the file if it carries one.

- [ ] **Step 5: Full verification**

```bash
swift build && swift test --filter DockWidgetTests
# The user launches from dist/Sharingan.app and it may be running: move the
# old bundle aside FIRST (rm -rf on it is permission-denied), then rebuild.
mv dist/Sharingan.app dist/Sharingan.app.old-$(date +%H%M%S) 2>/dev/null || true
Scripts/make-app.sh
open dist/Sharingan.app
```

Manual pass (needs the user or a screen session):
- Pill sits just above the Dock, right side, near the Trash.
- ▶︎ starts / resumes; ⏸ pauses (and disables when idle); ⟲ resets to a fresh
  focus duration; state matches the menu bar popover throughout.
- Typing in another app while clicking pill buttons never steals focus.
- Settings → Dock widget toggle hides/shows the pill live.
- Task title updates when the active task changes; "No task selected" when none.

- [ ] **Step 6: Commit and push**

```bash
cd /Users/mrb/Desktop/Blink
git add CHANGELOG.md Resources/Info.plist
git add -f docs/TECHNICAL.md
git commit -m "feat(dock-widget): CHANGELOG + version 1.11.0 + TECHNICAL.md"
git pull --rebase && git push
```
