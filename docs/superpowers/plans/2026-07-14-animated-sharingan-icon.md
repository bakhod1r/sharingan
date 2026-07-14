# Animated Spinning Sharingan Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Sharingan mark spins slowly and continuously in the menu bar and (while the main window is open) in the Dock, with a Settings toggle (default ON).

**Architecture:** One 12 fps `IconSpinner` clock advances a clockwise angle (60°/s); the menu bar icon redraws its tomoe at that angle through the existing `IconKey` change-gate, and a `DockIconAnimator` draws the bundled icon bitmap rotated into `NSApp.applicationIconImage`. The spinner idles on: setting off, macOS Reduce Motion, or screens asleep. Spec: `docs/superpowers/specs/2026-07-14-animated-sharingan-icon-design.md`.

**Tech Stack:** Swift 6 / AppKit / SwiftPM (no Xcode), Swift Testing (`@Suite`/`@Test`/`#expect`) for SharinganCore.

## Global Constraints

- `docs/` is gitignored wholesale — commit plan/spec/doc changes with `git add -f`.
- App target (`Sources/Sharingan`) is an executable — not importable from tests; its changes are verified by `swift build` + the headless `--render-*` flags (terminal has no Screen Recording permission, `screencapture` fails).
- Settings persistence must keep the `decodeIfPresent … ?? d.<field>` pattern so old JSON blobs decode.
- Rotation constants: 12 fps, 5°/frame (= 60°/s, full turn 6 s, visible cycle 2 s by 3-fold symmetry), clockwise.
- Commit after every task; push at the end (multi-Mac workflow).

---

### Task 1: `animateIcon` setting in SharinganCore

**Files:**
- Modify: `Sources/SharinganCore/Models/PomodoroSettings.swift` (property near line 248, decode line near line 412)
- Test: `Tests/SharinganTests/IconSpinSettingsTests.swift` (create)

**Interfaces:**
- Produces: `PomodoroSettings.animateIcon: Bool` (default `true`) — read by Tasks 3–5.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import SharinganCore

@Suite("Icon spin setting")
struct IconSpinSettingsTests {

    @Test("defaults to spinning")
    func defaultsOn() {
        #expect(PomodoroSettings().animateIcon)
    }

    @Test("survives a codable round trip")
    func roundTrip() throws {
        var s = PomodoroSettings()
        s.animateIcon = false
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(PomodoroSettings.self, from: data)
        #expect(back.animateIcon == false)
    }

    @Test("settings saved before the toggle existed still decode, spinning")
    func decodesLegacyJSON() throws {
        // A blob written by an older build has no animateIcon key at all.
        let s = try JSONDecoder().decode(PomodoroSettings.self, from: Data("{}".utf8))
        #expect(s.animateIcon)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter IconSpinSettings`
Expected: compile error — `value of type 'PomodoroSettings' has no member 'animateIcon'` (that IS the red state; Swift Testing can't run against a missing property).

- [ ] **Step 3: Implement the setting**

In `PomodoroSettings.swift`, directly under `showMenuBarCountdown` (~line 248):

```swift
    /// Spin the Sharingan mark — the menu-bar tomoe and (while the main
    /// window is open) the Dock icon rotate slowly. Runtime-only; the .icns
    /// on disk stays static.
    public var animateIcon: Bool = true
```

In `init(from decoder:)`, next to the `showMenuBarCountdown` line (~line 412):

```swift
        animateIcon = try c.decodeIfPresent(Bool.self, forKey: .animateIcon) ?? d.animateIcon
```

(CodingKeys are compiler-synthesized from the properties — adding the `var` adds the key.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter IconSpinSettings`
Expected: 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SharinganCore/Models/PomodoroSettings.swift Tests/SharinganTests/IconSpinSettingsTests.swift
git commit -m "feat(settings): animateIcon flag for the spinning Sharingan"
```

---

### Task 2: Rotation parameter on the menu-bar icon drawing

**Files:**
- Modify: `Sources/Sharingan/AppDelegate.swift` (`menuBarIcon`, ~line 112 and the tomoe loop ~line 195)
- Modify: `Sources/Sharingan/main.swift` (`--render-menubar-icon` block, lines 17–37)

**Interfaces:**
- Consumes: nothing new.
- Produces: `MenuBarController.menuBarIcon(progress: Double? = nil, phase: PomodoroPhase = .focus, rotationDegrees: Double = 0) -> NSImage?` — Task 3 passes the spinner angle.

- [ ] **Step 1: Add the parameter**

Change the signature (~line 112):

```swift
    static func menuBarIcon(progress: Double? = nil,
                            phase: PomodoroPhase = .focus,
                            rotationDegrees: Double = 0) -> NSImage? {
```

In the tomoe loop (~line 196) rotate ONLY the tomoe heads — the ring keeps its 12-o'clock anchor and the gradient/pupil are rotation-invariant (subtracting the angle spins them visually clockwise in the y-up context):

```swift
                let head = (-80.0 + Double(i) * 120.0 - rotationDegrees) * .pi / 180.0
```

Extend the doc comment above the function with one line:

```swift
    /// `rotationDegrees` spins the tomoe (clockwise) — the animated menu bar.
```

- [ ] **Step 2: Let the headless render flag exercise the rotation**

In `main.swift`, replace the body of the `--render-menubar-icon` block so an optional third argument sets the angle (existing 2-arg usage unchanged):

```swift
if let i = CommandLine.arguments.firstIndex(of: "--render-menubar-icon"),
   i + 1 < CommandLine.arguments.count {
    let out = CommandLine.arguments[i + 1]
    let rotation = i + 2 < CommandLine.arguments.count
        ? Double(CommandLine.arguments[i + 2]) ?? 0 : 0
    MainActor.assumeIsolated {
        if let img = MenuBarController.menuBarIcon(progress: 0.4, phase: .focus,
                                                   rotationDegrees: rotation),
           let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 144, pixelsHigh: 144,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            img.draw(in: NSRect(x: 0, y: 0, width: 144, height: 144))
            NSGraphicsContext.restoreGraphicsState()
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: out))
        }
    }
    exit(0)
}
```

- [ ] **Step 3: Check for other call sites**

Run: `grep -rn "menuBarIcon(" Sources/ Tests/`
Expected: only `AppDelegate.swift` (definition + `updateTitle` call, both fine — new param has a default) and `main.swift`.

- [ ] **Step 4: Build and render three frames**

```bash
swift build
.build/debug/Sharingan --render-menubar-icon /tmp/mb-0.png 0
.build/debug/Sharingan --render-menubar-icon /tmp/mb-40.png 40
.build/debug/Sharingan --render-menubar-icon /tmp/mb-80.png 80
cmp -s /tmp/mb-0.png /tmp/mb-40.png && echo SAME || echo DIFFERENT
```

Expected: build succeeds; `DIFFERENT`; visually inspect the PNGs — tomoe advanced clockwise, ring/pupil unmoved.

- [ ] **Step 5: Commit**

```bash
git add Sources/Sharingan/AppDelegate.swift Sources/Sharingan/main.swift
git commit -m "feat(menubar): rotation parameter on the Sharingan icon drawing"
```

---

### Task 3: IconSpinner + menu bar wiring

**Files:**
- Create: `Sources/Sharingan/Services/IconSpinner.swift`
- Modify: `Sources/Sharingan/AppDelegate.swift` (`IconKey` ~line 20, `install` ~line 26, the 1 s timer ~line 73, `updateTitle` ~line 78)

**Interfaces:**
- Consumes: `PomodoroSettings.animateIcon` (Task 1), `menuBarIcon(rotationDegrees:)` (Task 2).
- Produces: `IconSpinner` with `angle: Double`, `enabled: Bool`, `onFrame: ((Double, Bool) -> Void)?` — Task 4's dock animator hangs off `onFrame`.

- [ ] **Step 1: Create IconSpinner.swift**

```swift
import AppKit

/// Drives the spinning Sharingan: one 12 fps clock advancing a clockwise
/// angle, shared by the menu bar icon and the Dock icon so the two marks
/// stay in phase. Idles — timer gone, angle back to 0 — whenever the user
/// switched the animation off, macOS Reduce Motion is on, or the screens
/// are asleep; an idle spinner costs nothing.
@MainActor
final class IconSpinner {
    /// Degrees in [0, 360). 5°/frame at 12 fps = 60°/s: a full turn every
    /// 6 s, one visible cycle every 2 s (the mark is 3-fold symmetric).
    private(set) var angle: Double = 0

    /// Fires on every animation frame, and once more with (0, false) when
    /// the spinner stops so consumers repaint their static mark.
    var onFrame: ((_ angle: Double, _ spinning: Bool) -> Void)?

    /// The settings switch, pushed in by the menu bar's 1 s tick — a toggle
    /// in Settings takes effect within a second.
    var enabled = false {
        didSet { if oldValue != enabled { sync() } }
    }

    private var timer: Timer?
    private var screensAsleep = false {
        didSet { if oldValue != screensAsleep { sync() } }
    }

    init() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                       object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.screensAsleep = true }
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                       object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.screensAsleep = false }
        }
        ws.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                       object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sync() }
        }
    }

    private var shouldSpin: Bool {
        enabled && !screensAsleep
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func sync() {
        if shouldSpin, timer == nil {
            let t = Timer.scheduledTimer(withTimeInterval: 1.0 / 12.0,
                                         repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            t.tolerance = 0.02
            timer = t
        } else if !shouldSpin, let t = timer {
            t.invalidate()
            timer = nil
            angle = 0
            onFrame?(0, false)
        }
    }

    private func tick() {
        angle = (angle + 5).truncatingRemainder(dividingBy: 360)
        onFrame?(angle, true)
    }
}
```

- [ ] **Step 2: Wire it into MenuBarController**

In `AppDelegate.swift`:

Add to `IconKey` (~line 20) and store the spinner:

```swift
    private struct IconKey: Equatable {
        var percent: Int?
        var phase: PomodoroPhase
        var rotationStep: Int
    }
    private var lastIconKey: IconKey?
    private let spinner = IconSpinner()
```

At the end of `install(timer:coordinator:)`, right after `updateTitle()`:

```swift
        spinner.onFrame = { [weak self] _, _ in self?.updateTitle() }
        syncSpinner()
```

Change the 1 s timer body (~line 73):

```swift
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncSpinner()
                self?.updateTitle()
            }
        }
```

Add next to `updateTitle`:

```swift
    /// Pushes the settings switch into the spinner (1 s latency at most).
    private func syncSpinner() {
        spinner.enabled = timer?.settings.animateIcon ?? false
    }
```

In `updateTitle`, guard the title write (it now runs 12×/s) and thread the angle through — replace from `button.title = …` down to the `menuBarIcon` call:

```swift
        let title = show ? String(format: " %02d:%02d", Int(s) / 60, Int(s) % 60) : ""
        if button.title != title { button.title = title }

        // Progress ring around the iris while a session is engaged; the
        // rotation step quantises the spinner angle to the 5° frame grid
        // within the mark's 120° symmetry, so the bitmap is re-rendered
        // only when something visible changed.
        let key = IconKey(percent: engaged ? Int(timer.progress * 100) : nil,
                          phase: timer.phase,
                          rotationStep: Int(spinner.angle.truncatingRemainder(dividingBy: 120) / 5))
        if key != lastIconKey {
            lastIconKey = key
            button.image = Self.menuBarIcon(
                progress: key.percent.map { Double($0) / 100 },
                phase: key.phase,
                rotationDegrees: spinner.angle)
        }
```

- [ ] **Step 3: Build and run the app to see it spin**

```bash
swift build && swift test --filter IconSpinSettings
```

Expected: build + tests pass. Launch check (spinner visible only to the user; sanity: app boots without crash):

```bash
.build/debug/Sharingan & sleep 5; kill %1
```

Expected: process starts and stays alive 5 s, no crash output.

- [ ] **Step 4: Commit**

```bash
git add Sources/Sharingan/Services/IconSpinner.swift Sources/Sharingan/AppDelegate.swift
git commit -m "feat(menubar): the Sharingan tomoe spin (12 fps IconSpinner)"
```

---

### Task 4: DockIconAnimator

**Files:**
- Create: `Sources/Sharingan/Services/DockIconAnimator.swift`
- Modify: `Sources/Sharingan/AppDelegate.swift` (`install`, the `spinner.onFrame` closure from Task 3)

**Interfaces:**
- Consumes: `IconSpinner.onFrame` (Task 3).
- Produces: `DockIconAnimator.apply(angle: Double, spinning: Bool)`.

- [ ] **Step 1: Create DockIconAnimator.swift**

```swift
import AppKit

/// Spins the Dock icon in step with the menu bar mark. The bundled app icon
/// IS the bare Sharingan disc (see IconRenderer), so rotating the whole
/// bitmap is exact. Frames are drawn only while the app is a `.regular`
/// activation-policy app — accessory mode has no Dock tile — and the shipped
/// artwork is restored the moment the spinner idles or the tile disappears.
@MainActor
final class DockIconAnimator {
    /// The artwork as shipped, captured before the first spun frame.
    private let base: NSImage? =
        Bundle.main.image(forResource: "AppIcon") ?? NSApp.applicationIconImage
    private var showingSpunFrame = false

    func apply(angle: Double, spinning: Bool) {
        guard let base else { return }
        guard spinning, NSApp.activationPolicy() == .regular else {
            if showingSpunFrame {
                NSApp.applicationIconImage = base
                showingSpunFrame = false
            }
            return
        }
        let side: CGFloat = 256
        let frame = NSImage(size: NSSize(width: side, height: side),
                            flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.translateBy(x: rect.midX, y: rect.midY)
            // Negative = visually clockwise in the y-up context, matching
            // the menu bar's tomoe direction.
            ctx.rotate(by: -angle * .pi / 180)
            base.draw(in: CGRect(x: -side / 2, y: -side / 2, width: side, height: side))
            return true
        }
        NSApp.applicationIconImage = frame
        showingSpunFrame = true
    }
}
```

- [ ] **Step 2: Wire it into the spinner**

In `AppDelegate.swift`, add the property next to `spinner`:

```swift
    private var dockAnimator: DockIconAnimator?
```

In `install(...)`, replace the Task 3 closure:

```swift
        dockAnimator = DockIconAnimator()
        spinner.onFrame = { [weak self] angle, spinning in
            self?.updateTitle()
            self?.dockAnimator?.apply(angle: angle, spinning: spinning)
        }
        syncSpinner()
```

- [ ] **Step 3: Build, run, verify Dock spin**

```bash
swift build && .build/debug/Sharingan & sleep 3
```

Then open the main window (popover → "Open window" or `open -a` route) — the Dock icon appears and spins; close the window — the tile leaves; quit. (No Screen Recording permission for automated capture: this is a manual eyeball step, plus the crash-free boot check.)

```bash
kill %1
```

- [ ] **Step 4: Commit**

```bash
git add Sources/Sharingan/Services/DockIconAnimator.swift Sources/Sharingan/AppDelegate.swift
git commit -m "feat(dock): the Dock Sharingan spins while the window is open"
```

---

### Task 5: Settings toggle

**Files:**
- Modify: `Sources/Sharingan/Views/SettingsView.swift` (~line 360, "Menu bar" section)

**Interfaces:**
- Consumes: `PomodoroSettings.animateIcon` (Task 1). SettingsView already binds `$settings`; persistence is the existing mechanism.

- [ ] **Step 1: Add the toggle**

Replace the "Menu bar" section:

```swift
                Section("Menu bar") {
                    ToggleRow(title: "Show countdown in menu bar",
                              isOn: $settings.showMenuBarCountdown)
                    ToggleRow(title: "Spin the Sharingan",
                              isOn: $settings.animateIcon)
                    Text("The tomoe rotate slowly in the menu bar and Dock. Pauses when macOS Reduce Motion is on.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
```

- [ ] **Step 2: Build; toggle round-trip**

```bash
swift build && swift test
```

Expected: clean build, full suite green. Manual: flip the toggle in Settings — the menu bar mark freezes within a second and snaps back to the canonical orientation; flip on — spins again.

- [ ] **Step 3: Commit**

```bash
git add Sources/Sharingan/Views/SettingsView.swift
git commit -m "feat(settings): Spin the Sharingan toggle"
```

---

### Task 6: Docs, verification sweep, push

**Files:**
- Modify: `docs/TECHNICAL.md` (feature-doc upkeep rule)
- Modify: `CHANGELOG.md` (entry under the unreleased/topmost section, matching its existing style)

- [ ] **Step 1: Full test + build sweep**

```bash
swift build 2>&1 | tail -3 && swift test 2>&1 | tail -5
```

Expected: build succeeds, all tests pass.

- [ ] **Step 2: Update docs**

`docs/TECHNICAL.md`: in the menu-bar / services section, document IconSpinner (12 fps, 60°/s, idle conditions), DockIconAnimator (regular-policy gate, base restore), `animateIcon` setting, and the extended `--render-menubar-icon <path> [rotation]` flag.

`CHANGELOG.md`: one user-facing line, e.g. "The Sharingan now spins — menu bar and Dock; Settings → Menu bar → Spin the Sharingan to turn it off. Honors macOS Reduce Motion."

- [ ] **Step 3: Commit and push**

```bash
git add -f docs/TECHNICAL.md docs/superpowers/plans/2026-07-14-animated-sharingan-icon.md
git add CHANGELOG.md
git commit -m "docs: spinning Sharingan icon (TECHNICAL, changelog)"
git push
```

Expected: push succeeds to `github.com/bakhod1r/Blink` main. (Recheck `git log` first — other agents share this checkout.)
