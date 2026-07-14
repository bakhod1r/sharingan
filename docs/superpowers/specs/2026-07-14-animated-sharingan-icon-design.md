# Animated Sharingan Icon — Design

**Date:** 2026-07-14
**Status:** Approved (user: both icons, always spinning, settings toggle)

## Goal

The app's Sharingan mark spins — slowly, continuously — in both places it
appears at runtime: the menu bar status item and the Dock icon. A settings
toggle turns the animation off. The static `.icns` on disk cannot animate
(macOS limitation); this is purely a runtime effect.

## Decisions (from brainstorming)

- **Where:** menu bar icon AND Dock icon.
- **When:** always while the app runs (not only during sessions).
- **Configurable:** yes — one toggle in Settings, default ON.

## Architecture

### 1. IconSpinner (single clock)

One 12 fps `Timer` (tolerance ~0.02 s) owned by `AppDelegate` advances a
rotation angle clockwise at 60°/s — a full revolution every 6 s. The
Sharingan is 3-fold symmetric, so the visible cycle is 2 s: calm, not
distracting. The spinner idles (timer invalidated, angle frozen) when any
of these hold:

- `settings.animateIcon == false`
- `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion == true`
  (re-checked via `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`)
- screens are asleep (`screensDidSleepNotification` /
  `screensDidWakeNotification`)

Both consumers below read the same angle so the two marks stay in phase.

### 2. Menu bar icon

`AppDelegate.menuBarIcon(progress:phase:)` gains a `rotation: Double = 0`
parameter. It offsets ONLY the tomoe head angles (and nothing else): the
radial gradient and pupil are rotation-invariant, and the progress ring
must keep its fixed 12-o'clock anchor. `IconKey` gains a discrete rotation
step (angle quantised to 24 steps per 120° of symmetry) so the existing
"redraw only when the key changes" logic keeps working; at rest no ticks
fire and nothing redraws. Redrawing an 18 pt bitmap at 12 fps is negligible
CPU.

The existing 1 s title timer stays as-is (countdown text + ring percent);
the spinner's tick calls the same `updateTitle()` path, which redraws only
when the key actually changed.

### 3. Dock icon — DockIconAnimator

New service `Sources/Sharingan/Services/DockIconAnimator.swift`:

- Caches the base artwork once (`NSApp.applicationIconImage` at launch —
  the bundled `AppIcon.icns`, which IS the bare Sharingan disc, so rotating
  the whole bitmap is exact).
- On each spinner tick, if `NSApp.activationPolicy() == .regular` (Dock
  icon visible only when the main window is open), draws the base image
  rotated about its centre into a 256×256 canvas and assigns it to
  `NSApp.applicationIconImage`.
- When the policy is `.accessory`, or the spinner idles, it restores the
  original image and does no per-tick work.

### 4. Settings

- `PomodoroSettings.animateIcon: Bool = true`, following the existing
  `decodeIfPresent … ?? default` Codable pattern (old persisted JSON keeps
  working).
- Toggle in `SettingsView` next to the existing "menu bar countdown" toggle
  (~line 362): "Spin the Sharingan (menu bar & Dock)".
- `AppDelegate` re-evaluates the spinner's idle conditions when settings
  change (same channel the countdown toggle already uses — the 1 s tick
  reads settings each pass; the spinner does the same).

## Error handling

- If the base Dock image can't be loaded, the animator stays inert (static
  icon, no crash).
- `menuBarIcon` keeps its existing stopwatch-glyph fallback.

## Testing

- **SharinganCore tests:** `animateIcon` defaults to `true`; JSON round-trip
  preserves `false`; decoding legacy JSON without the key yields `true`.
- **App layer (not unit-testable — executable target):** verified by
  building and running; visual check of menu bar + Dock (headless screenshot
  flags per repo infra notes).

## Out of scope

- Animating the on-disk `.icns` (impossible on macOS).
- Speed/direction settings (one good default; YAGNI).
- Notch HUD / popover artwork (already animated separately via SwiftUI).
