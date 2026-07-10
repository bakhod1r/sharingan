# Premium UI Animations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One consistent, premium motion language across the whole Blink UI: shared `DS.Motion` tokens, no janky static surfaces, animated window presentation, and celebratory hero moments — all honoring Reduce Motion.

**Architecture:** Add a motion-token namespace to the existing `DS` design system and migrate every inline animation timing to it. Fix the static surfaces (countdown ring, stats extras, streak badge). Add one shared AppKit `WindowAnimator` used by all three window managers. Sprinkle `symbolEffect` hero moments (unlocked by bumping the platform floor to macOS 14).

**Tech Stack:** SwiftUI + AppKit, SwiftPM (no Xcode project). Build with `make build`, test with `make test` from the repo root `/Users/mrb/Desktop/Blink`.

**Spec:** `docs/superpowers/specs/2026-07-10-premium-ui-animations-design.md`

## Global Constraints

- Platform floor becomes `.macOS(.v14)` (Task 1); no `#available` guards needed after that.
- DO NOT touch `MoveEyesView.swift`, `BreakView.swift`, `WallpaperWindowManager.swift`, `SharinganStyle.swift`, `PomodoroSettings.swift` — they hold unrelated in-flight work (uncommitted). `SettingsView.swift` also has uncommitted hunks: edit only the line called out in Task 2 and stage hunks carefully (`git add -p` or exact-line edit is fine since the whole file gets committed — see Task 2 note).
- Every task ends with `make build` (expect `Build complete!`) and a commit. After each commit, `git push` (user works across multiple Macs).
- All new animations must be disabled under Reduce Motion (`@Environment(\.accessibilityReduceMotion)` in SwiftUI, `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` in AppKit).
- Commit messages end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: Platform bump + `DS.Motion` tokens

**Files:**
- Modify: `Package.swift:6`
- Modify: `Sources/Blink/Views/DesignSystem.swift`

**Interfaces:**
- Produces: `DS.Motion.snappy`, `DS.Motion.standard`, `DS.Motion.gentle`, `DS.Motion.hover`, `DS.Motion.celebrate` (all `Animation`) — every later task uses these names.

- [ ] **Step 1: Bump platform floor**

In `Package.swift` line 6, change:

```swift
    platforms: [.macOS(.v13)],
```

to:

```swift
    platforms: [.macOS(.v14)],
```

- [ ] **Step 2: Add motion tokens**

In `Sources/Blink/Views/DesignSystem.swift`, inside `enum DS` (after the `Space` enum, before the closing brace at line 23), add:

```swift
    /// Motion tokens — one shared animation "hand". Every surface had its own
    /// hand-tuned spring/ease before this (20+ distinct timings); these five
    /// roles cover them all. Deliberate one-offs (breathing loops, celebration
    /// flights, continuous TimelineView drivers) stay hand-tuned.
    enum Motion {
        /// Numeric counters, small state flips.
        static let snappy = Animation.snappy(duration: 0.3)
        /// Tab switches, list insert/remove, layout moves, drag targets.
        static let standard = Animation.spring(response: 0.35, dampingFraction: 0.85)
        /// Fades, disclosures, section cross-fades.
        static let gentle = Animation.easeInOut(duration: 0.25)
        /// Hover highlights and press states.
        static let hover = Animation.easeOut(duration: 0.15)
        /// Streak / completion celebrations.
        static let celebrate = Animation.bouncy(duration: 0.45)
    }
```

- [ ] **Step 3: Build and test**

Run: `make build && make test`
Expected: `Build complete!`, all tests pass (the suite tests `BlinkCore` only; the bump must not break it).

- [ ] **Step 4: Commit and push**

```bash
git add Package.swift Sources/Blink/Views/DesignSystem.swift
git commit -m "feat(motion): DS.Motion token layer + macOS 14 floor

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push
```

---

### Task 2: Migrate inline timings to `DS.Motion`

**Files:**
- Modify: `Sources/Blink/Views/MenuBarView.swift`, `MenuBarWeekView.swift`, `MainWindowView.swift`, `TasksView.swift`, `WeeklyBoardView.swift`, `SettingsView.swift`, `StatsChartView.swift`, `GlassComponents.swift`

**Interfaces:**
- Consumes: `DS.Motion.*` from Task 1.
- Produces: nothing new — behavior-preserving substitution.

- [ ] **Step 1: Apply the substitutions**

Exact replacements (line numbers are pre-edit anchors; match on content). Leave everything not listed alone — in particular the `repeatForever` breathing loops (`MenuBarView:903-907`, `CircularRunButton`), `FloatingTimerView` (TimelineView-driven, already tokens-adjacent and reduceMotion-aware), and `StreakRewardBanner` (deliberate celebration choreography).

| File:line | Old | New |
|---|---|---|
| MenuBarView.swift:88 | `.spring(response: 0.35, dampingFraction: 0.85)` | `DS.Motion.standard` |
| MenuBarView.swift:143 | `.easeInOut(duration: 0.3)` | `DS.Motion.gentle` |
| MenuBarView.swift:262 | `.spring(response: 0.35, dampingFraction: 0.82)` | `DS.Motion.standard` |
| MenuBarView.swift:282 | `.easeInOut(duration: 0.2)` | `DS.Motion.gentle` |
| MenuBarView.swift:374 | `.easeInOut(duration: 0.2)` | `DS.Motion.gentle` |
| MenuBarView.swift:437 | `.spring(response: 0.35, dampingFraction: 0.82)` | `DS.Motion.standard` |
| MenuBarView.swift:517 | `.easeInOut(duration: 0.2)` | `DS.Motion.gentle` |
| MenuBarView.swift:541 | `.easeInOut(duration: 0.15)` | `DS.Motion.hover` |
| MenuBarView.swift:565 | `.easeInOut(duration: 0.15)` | `DS.Motion.hover` |
| MenuBarView.swift:885 | `.snappy(duration: 0.3)` | `DS.Motion.snappy` |
| MenuBarView.swift:890 | `.easeInOut(duration: 0.4)` | `DS.Motion.gentle` |
| MenuBarWeekView.swift:58,73,85 | `.spring(response: 0.3, dampingFraction: 0.8)` | `DS.Motion.standard` |
| MenuBarWeekView.swift:160 | `.spring(response: 0.4, dampingFraction: 0.8)` | `DS.Motion.standard` |
| MenuBarWeekView.swift:238 | `.spring(response: 0.32, dampingFraction: 0.7)` | `DS.Motion.standard` |
| MenuBarWeekView.swift:241 | `.spring(response: 0.45, dampingFraction: 0.8)` | `DS.Motion.standard` |
| MainWindowView.swift:55 | `.easeInOut(duration: 0.24)` | `DS.Motion.gentle` |
| MainWindowView.swift:641 | `.easeInOut(duration: 0.18)` | `DS.Motion.gentle` |
| MainWindowView.swift:738,739 | `.easeOut(duration: 0.15)` | `DS.Motion.hover` |
| TasksView.swift:154,209 | `.easeInOut(duration: 0.15)` | `DS.Motion.gentle` (filter switch, not hover) |
| TasksView.swift:313 | `.easeInOut(duration: 0.2)` | `DS.Motion.gentle` |
| TasksView.swift:592,596 | `.spring(response: 0.3, dampingFraction: 0.7)` | `DS.Motion.standard` |
| TasksView.swift:643,658 | `.easeInOut(duration: 0.15)` | `DS.Motion.hover` |
| TasksView.swift:1040 | `.easeInOut(duration: 0.2)` | `DS.Motion.gentle` |
| TasksView.swift:1088,1108 | `.easeInOut(duration: 0.15)` | `DS.Motion.hover` |
| WeeklyBoardView.swift:97,129 | `.spring(response: 0.42, dampingFraction: 0.85)` | `DS.Motion.standard` |
| WeeklyBoardView.swift:202 | `.spring(response: 0.4, dampingFraction: 0.8)` | `DS.Motion.standard` |
| WeeklyBoardView.swift:273 | `.spring(response: 0.32, dampingFraction: 0.7)` | `DS.Motion.standard` |
| WeeklyBoardView.swift:276 | `.spring(response: 0.45, dampingFraction: 0.8)` | `DS.Motion.standard` |
| WeeklyBoardView.swift:321 | `.easeInOut(duration: 0.2)` | `DS.Motion.gentle` |
| WeeklyBoardView.swift:400 | `.spring(response: 0.3, dampingFraction: 0.7)` | `DS.Motion.standard` |
| SettingsView.swift:24 | `.easeInOut(duration: 0.26)` | `DS.Motion.gentle` |
| StatsChartView.swift:92 | `.spring(response: 0.32, dampingFraction: 0.8)` | `DS.Motion.standard` |
| StatsChartView.swift:169 | `.easeInOut(duration: 0.3)` | `DS.Motion.gentle` |
| GlassComponents.swift:85 | `.spring(response: 0.28, dampingFraction: 0.72)` | `DS.Motion.snappy` |

Note (SettingsView): the file has unrelated uncommitted hunks (Sharingan pattern settings). Make only the line-24 edit; commit the whole file anyway — those hunks are the user's WIP and SHOULD NOT be committed. So for SettingsView specifically, stage with `git add -p Sources/Blink/Views/SettingsView.swift` and pick ONLY the line-24 hunk.

- [ ] **Step 2: Verify no stragglers**

Run: `grep -rn "spring(response\|easeInOut(duration\|easeOut(duration\|snappy(duration" Sources/Blink/Views --include="*.swift" | grep -v "MoveEyes\|BreakView\|FloatingTimer\|StreakReward\|CircularRun\|CameraIndicator\|repeatForever\|DesignSystem\|ExerciseSequence\|QuickInput\|TaskPicker\|TaskEditor"`
Expected: only MenuBarView:905 (the breathing loop) and any sites deliberately excluded above.

- [ ] **Step 3: Build**

Run: `make build`
Expected: `Build complete!`

- [ ] **Step 4: Commit and push**

```bash
git add Sources/Blink/Views/MenuBarView.swift Sources/Blink/Views/MenuBarWeekView.swift Sources/Blink/Views/MainWindowView.swift Sources/Blink/Views/TasksView.swift Sources/Blink/Views/WeeklyBoardView.swift Sources/Blink/Views/StatsChartView.swift Sources/Blink/Views/GlassComponents.swift
git add -p Sources/Blink/Views/SettingsView.swift   # ONLY the line-24 hunk
git commit -m "refactor(motion): migrate inline timings to DS.Motion tokens

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push
```

---

### Task 3: CountdownRing continuous sweep

**Files:**
- Modify: `Sources/Blink/Views/CountdownRing.swift`

**Interfaces:**
- Consumes: nothing new. `CountdownRing(progress:colors:lineWidth:)` signature unchanged (used at `MainWindowView.swift:829`).

- [ ] **Step 1: Animate the trim**

The arc currently steps once per second because nothing animates `progress`. Replace the body's trimmed circle so each per-tick progress change glides linearly across the tick interval:

```swift
import SwiftUI

struct CountdownRing: View {
    var progress: Double
    var colors: [Color]
    var lineWidth: CGFloat = 18

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: max(0.001, progress))
                    .stroke(
                        AngularGradient(colors: colors + [colors.first ?? .white],
                                        center: .center),
                        style: StrokeStyle(lineWidth: lineWidth,
                                           lineCap: .round, lineJoin: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: colors.first?.opacity(0.55) ?? .clear,
                            radius: 16, x: 0, y: 0)
                    // The timer ticks once a second; a 1s linear glide between
                    // ticks turns the stepping arc into a continuous sweep.
                    // Skips/resets ride the same glide, which reads as intent.
                    .animation(reduceMotion ? nil : .linear(duration: 1),
                               value: progress)
            }
            .frame(width: size, height: size)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `make build`
Expected: `Build complete!`

- [ ] **Step 3: Commit and push**

```bash
git add Sources/Blink/Views/CountdownRing.swift
git commit -m "feat(motion): countdown ring sweeps continuously between ticks

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push
```

---

### Task 4: Stats + streak surfaces come alive

**Files:**
- Modify: `Sources/Blink/Views/StatsExtrasView.swift:179-181, 235-237, 287-289`
- Modify: `Sources/Blink/Views/StreakBadgeView.swift`

**Interfaces:**
- Consumes: `DS.Motion.snappy`, `DS.Motion.standard`, `DS.Motion.celebrate` (Task 1).

- [ ] **Step 1: StatsExtrasView numeric transitions**

Three value labels jump when data changes. Add `numericText` to each:

At `:179-181` (category totals count):

```swift
                            Text("\(row.count)")
                                .font(.system(.caption2, design: .rounded).weight(.bold).monospacedDigit())
                                .foregroundStyle(Color.dsSecondary)
                                .contentTransition(.numericText())
                                .animation(DS.Motion.snappy, value: row.count)
```

At `:235-237` (time-of-day count) — identical two modifiers appended to the same `Text("\(row.count)")` pattern.

At `:287-289` (`recordRow` value):

```swift
            Text(value)
                .font(.system(.caption, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(Color.dsSecondary)
                .contentTransition(.numericText())
                .animation(DS.Motion.snappy, value: value)
```

- [ ] **Step 2: StreakBadgeView — animated fill, counting number, bouncing flame**

In `StreakBadgeView.swift`:

Header (`:12-24`) — flame bounces and count rolls when the streak changes:

```swift
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 18, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .orange)
                    .symbolEffect(.bounce, value: streak.currentStreak)
                Text("\(streak.currentStreak) day streak")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(DS.Motion.celebrate, value: streak.currentStreak)
                Spacer()
                Text("Best: \(streak.longestStreak)")
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .contentTransition(.numericText())
                    .animation(DS.Motion.snappy, value: streak.longestStreak)
            }
```

Progress fill (`:61-69`) — the capsule width animates to its new fraction:

```swift
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(LinearGradient(colors: [.orange, .yellow],
                                                  startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(3, geo.size.width * pct))
                        .animation(DS.Motion.standard, value: pct)
                }
            }
            .frame(height: 5)
```

(`symbolEffect`/`numericText` are one-shot value-keyed transitions, not loops — safe under Reduce Motion, which SwiftUI already tones down system-side; no explicit gate needed here.)

- [ ] **Step 3: Build**

Run: `make build`
Expected: `Build complete!`

- [ ] **Step 4: Commit and push**

```bash
git add Sources/Blink/Views/StatsExtrasView.swift Sources/Blink/Views/StreakBadgeView.swift
git commit -m "feat(motion): stats counters roll, streak fill sweeps, flame bounces

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push
```

---

### Task 5: Window presentation animator

**Files:**
- Create: `Sources/Blink/Services/WindowAnimator.swift`
- Modify: `Sources/Blink/Services/MainWindowManager.swift:24-27, 43`
- Modify: `Sources/Blink/Services/QuickAddWindowManager.swift:52, 57-61`
- Modify: `Sources/Blink/Services/FloatingWindowManager.swift:67, 93-105`

**Interfaces:**
- Produces: `WindowAnimator.present(_ window: NSWindow, makeKey: Bool = true)` and `WindowAnimator.dismiss(_ window: NSWindow, completion: @escaping () -> Void)`.
- Key/focus semantics must be preserved: `present` calls `makeKeyAndOrderFront`/`orderFrontRegardless` FIRST, then animates alpha/frame only.

- [ ] **Step 1: Create the animator**

`Sources/Blink/Services/WindowAnimator.swift`:

```swift
import AppKit

/// Fades windows in with a subtle scale-up on show and fades them out on
/// dismiss, so panels stop popping into existence. Ordering/key calls happen
/// first and are never animated — only `alphaValue` and the frame move —
/// so focus behavior is untouched. Honors Reduce Motion (instant show/hide).
@MainActor
enum WindowAnimator {
    private static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Order the window front (key or not) with a 0.97→1 scale + fade-in.
    /// Use INSTEAD of a bare makeKeyAndOrderFront/orderFrontRegardless.
    static func present(_ window: NSWindow, makeKey: Bool = true) {
        if makeKey { window.makeKeyAndOrderFront(nil) }
        else { window.orderFrontRegardless() }
        guard !reduceMotion else { return }

        let frame = window.frame
        let inset = window.frame.insetBy(dx: frame.width * 0.015,
                                         dy: frame.height * 0.015)
        window.alphaValue = 0
        window.setFrame(inset, display: false)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            window.animator().setFrame(frame, display: true)
        }
    }

    /// Fade out, then hand back for orderOut/cleanup. Restores alpha so a
    /// reused window presents correctly next time.
    static func dismiss(_ window: NSWindow, completion: @escaping () -> Void) {
        guard !reduceMotion else { completion(); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: {
            completion()
            window.alphaValue = 1
        })
    }
}
```

- [ ] **Step 2: Adopt in MainWindowManager**

In `show()` — the re-show path (`:24-27`) animates only when the window isn't already on screen, and the creation path (`:43`) presents through the animator:

```swift
        if let window {
            if window.isVisible {
                window.makeKeyAndOrderFront(nil)
            } else {
                WindowAnimator.present(window)
            }
            return
        }
```

and replace `win.makeKeyAndOrderFront(nil)` with:

```swift
        WindowAnimator.present(win)
```

- [ ] **Step 3: Adopt in QuickAddWindowManager**

Replace `panel.makeKeyAndOrderFront(nil)` at `:52` with `WindowAnimator.present(panel)` (the `NSApp.activate` line stays). Replace `hideQuickAdd()` (`:57-61`) with:

```swift
    func hideQuickAdd() {
        guard let panel else { return }
        self.panel = nil
        WindowAnimator.dismiss(panel) {
            panel.orderOut(nil)
            panel.contentView = nil
        }
    }
```

(The early-refocus path at `:14-17` stays a bare `makeKeyAndOrderFront` — the panel is already visible.)

- [ ] **Step 4: Adopt in FloatingWindowManager**

Replace `panel.orderFrontRegardless()` at `:67` with `WindowAnimator.present(panel, makeKey: false)` (a non-activating panel must not steal key). In `hideFloating()` (`:93-105`), keep the observer teardown, then:

```swift
        guard let panel else { return }
        self.panel = nil
        WindowAnimator.dismiss(panel) {
            panel.orderOut(nil)
            panel.contentView = nil
        }
```

Caution: `present` mutates the frame, and this manager persists frame origin on `didMoveNotification`. The observers are registered AFTER `orderFrontRegardless()` today — keep that order (present first, observers after) so the 0.97→1 settle isn't persisted as a user drag.

- [ ] **Step 5: Build**

Run: `make build`
Expected: `Build complete!`

- [ ] **Step 6: Commit and push**

```bash
git add Sources/Blink/Services/WindowAnimator.swift Sources/Blink/Services/MainWindowManager.swift Sources/Blink/Services/QuickAddWindowManager.swift Sources/Blink/Services/FloatingWindowManager.swift
git commit -m "feat(motion): windows fade+scale in, fade out — no more popping

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push
```

---

### Task 6: Hero micro-moments (symbol effects)

**Files:**
- Modify: `Sources/Blink/Views/TasksView.swift:986-991`
- Modify: `Sources/Blink/Views/MainWindowView.swift:602-618` (`footerStat`)
- Modify: `Sources/Blink/Views/CircularRunButton.swift:43`

**Interfaces:**
- Consumes: macOS 14 floor (Task 1) for `.symbolEffect` / `.contentTransition(.symbolEffect(.replace))`.

- [ ] **Step 1: Task checkbox bounces on completion**

`TasksView.swift` row checkbox (`:986-991`) — the circle→checkmark morphs and bounces:

```swift
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(task.isDone ? Color.green
                                     : (prio ?? (hovered ? Color.dsPrimary : Color.dsSecondary)))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: task.isDone)
                    .animation(DS.Motion.celebrate, value: task.isDone)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
```

- [ ] **Step 2: Sidebar footer stats bounce on increment**

`MainWindowView.swift` `footerStat` (`:602-618`) — icon bounces whenever its number changes (today count ticks up, streak extends):

```swift
    private func footerStat(icon: String, tint: Color, value: Int, label: String) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .symbolEffect(.bounce, value: value)
                Text("\(value)")
                    .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(DS.Motion.snappy, value: value)
            }
            Text(label)
                .font(.system(.caption2, design: .rounded).weight(.medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }
```

- [ ] **Step 3: Run button play↔pause morph**

`CircularRunButton.swift:43` — the icon replaces with a symbol morph instead of a hard swap:

```swift
                    Image(systemName: isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 24, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                        .animation(DS.Motion.snappy, value: isRunning)
```

- [ ] **Step 4: Build**

Run: `make build`
Expected: `Build complete!`

- [ ] **Step 5: Commit and push**

```bash
git add Sources/Blink/Views/TasksView.swift Sources/Blink/Views/MainWindowView.swift Sources/Blink/Views/CircularRunButton.swift
git commit -m "feat(motion): symbol hero moments — checkbox bounce, stat bounce, play/pause morph

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push
```

---

### Task 7: Final verification

**Files:** none (verification only)

- [ ] **Step 1: Full build + tests**

Run: `make build && make test`
Expected: `Build complete!`, all tests pass.

- [ ] **Step 2: Assemble and launch the app**

Run: `make app && make open`
Expected: `dist/Sharingan.app` assembles and launches.

- [ ] **Step 3: Visual checklist (launch the app and drive each surface)**

- Main window opens with fade+scale (no pop); timer ring sweeps continuously while running; play↔pause icon morphs.
- Menu bar popover: tab switch, timer digits, hover — all still smooth, timings feel unified.
- Tasks: completing a task bounces the checkmark green before the row animates out.
- Stats section: numbers roll on data change; streak badge fill animates, flame bounces.
- Quick-add (hotkey): fades in centered, Esc fades it out.
- Floating timer: fades in at its remembered position; toggling off fades it out; position persistence still works after a drag.
- System Settings → Accessibility → Display → Reduce Motion ON: windows appear instantly, ring steps, no bounces.

- [ ] **Step 4: Report**

Report any checklist failures with the surface and symptom; fix-forward small issues (wrong token choice, missing gate) in a `fix(motion):` commit, push.
