# Dock Widget — design

**Date:** 2026-07-14 · **Target version:** 1.8.0

## Overview

A persistent, "now playing"-style control pill anchored to the Dock, inspired by
the reference video `dock sharingan .mp4` (a Dock music widget). It shows the
active task, the remaining time, and three always-standing transport buttons:
Start, Stop, Reset. macOS does not allow widening the app's real Dock tile
(tiles are always square), so — like the app in the video — this is a
borderless, non-activating panel aligned flush with the Dock's edge so it reads
as part of the Dock.

## Goals

- Control the pomodoro without opening the menu bar popover: see the active
  task and remaining time, and hit Start / Stop / Reset right at the Dock.
- Visually blend with the Dock (material, rounded corners, placement).

## Non-goals (v1)

- Hover-to-expand animation from the video.
- Drag repositioning, per-screen placement choices, multi-display copies.
- Widening or replacing the real Dock tile (impossible on macOS).

## UX

```
                 ┌────────────────────────────────────────┐
                 │ ◉  Design review        [▶︎] [⏸] [⟲]   │
                 │    24:37                               │
                 └────────────────────────────────────────┘
   ══════════[ Dock … Trash ]═══════════════════════════════▲ right-aligned
```

- **Ring (◉):** mini progress ring driven by `timer.progress`, stroked with the
  phase gradient (`timer.phase.gradient`); dimmed/idle when the timer is not
  running.
- **Title:** `TaskStore.shared.activeTask?.title`, else "No task selected".
  Category color dot next to the title (same convention as FloatingTimerView).
- **Time:** `timer.settings.timeFormat.string(timer.remainingSeconds)`,
  monospaced/DS timer font, `contentTransition(.numericText())`.
- **Buttons — all three always visible ("standing"), state-disabled:**
  - ▶︎ Start → `timer.start()` (resumes a paused session) — disabled while running
  - ⏸ Stop → `timer.pause()` — disabled while idle/paused
  - ⟲ Reset → `timer.stop()` (engine's full reset: fresh focus, counters zeroed)
- Panel never steals focus (`.nonactivatingPanel`, `canBecomeKey == false`,
  same as `FloatingMiniPanel`), joins all Spaces, ignores window cycling.
- Shown whenever the setting is on — including while the timer is idle, so
  Start is always reachable. Hidden entirely when the setting is off.

## Placement

Right-aligned near the Trash end of the Dock:

- **Dock at bottom (common case):** width `W ≈ 320`, height `H ≈ 56`;
  origin.y = `screen.visibleFrame.minY + 4` (flush above the Dock),
  origin.x = `screen.visibleFrame.maxX − W − 16`.
- **Dock on left/right:** the pill sits at the bottom end of the Dock's inner
  edge (x flush to `visibleFrame.minX`/`maxX`, y = `visibleFrame.minY + 16`).
- **Dock auto-hidden:** `visibleFrame` ≈ `frame`, so the pill rests at the
  screen's bottom edge — acceptable; no special casing.
- Repositions on `NSApplication.didChangeScreenParametersNotification`, on
  show, and on settings refresh. Main screen only (v1).

## Architecture

Mirrors the existing floating-timer pair — no new patterns:

| Unit | Role |
|------|------|
| `Sources/Sharingan/Services/DockWidgetWindowManager.swift` (new) | Owns the `NSPanel` (borderless, non-activating, clear, no shadow, `.floating` level, `canJoinAllSpaces`). `show(timer:)` / `hide()` / `refresh(timer:)` + the placement math above. Singleton like `FloatingWindowManager`. |
| `Sources/Sharingan/Views/DockWidgetView.swift` (new) | SwiftUI pill: ring + task/time + three buttons. Observes `PomodoroTimer` and `TaskStore.shared`. `.regularMaterial` in a continuous rounded rect, DS fonts/colors. |
| `PomodoroSettings.dockWidgetEnabled: Bool = true` (new field) | On by default, like `floatingTimerEnabled`. Follows the `floating*` conventions: plain `var` + `decodeIfPresent` with default fallback in `init(from:)`. |
| `SettingsView` | One toggle ("Dock widget") in the section that hosts the floating-timer toggles. |
| `AppDelegate` | Wire like the floating timer: on launch and on settings change, show/hide via the manager. |

Data flow: `PomodoroTimer` (published state) → SwiftUI view; button taps call
engine methods directly. No new state stores, no polling.

## Edge cases

- No active task → "No task selected" placeholder (existing convention).
- Timer idle → ring at 0, time shows the pending focus duration (engine
  already publishes this after `stop()`).
- Screen unplugged / resolution change → reposition via the notification.
- Reduce Motion → no continuous animation is used beyond the numeric text
  transition, so nothing extra to gate.

## Versioning & docs (repo rules)

- Bump to **1.8.0**: `CHANGELOG.md` entry, `Info.plist` version,
  `docs/TECHNICAL.md` section for the Dock widget.
- `docs/` is gitignored — spec and TECHNICAL.md changes need `git add -f`.
- Commit + push after completion (multi-Mac workflow).

## Verification

- `swift build` clean.
- Manual: rebuild `Scripts/make-app.sh`, swap `dist/Sharingan.app`, launch;
  check placement vs Dock, button actions against the popover state, no focus
  stealing while typing in another app, setting toggle shows/hides live.
