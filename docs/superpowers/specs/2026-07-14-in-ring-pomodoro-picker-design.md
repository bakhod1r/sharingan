# In-ring pomodoro size picker — design

**Date:** 2026-07-14 · **Target:** 1.20.0 · **Approved:** owner (option "idle'da picker, ishlaganda label")

## What

In the main window's timer page (`TimerDetailView`, MainWindowView.swift), the
space under the big countdown inside the ring currently always shows the phase
label ("Focus"). Replace it, *only while the timer is idle*, with a compact
Small / Normal / Big pomodoro-size picker so the size can be switched without
reaching for the sidebar.

## Behavior

- **Idle** (`!timer.isRunning && timer.phase == .focus` — fresh or after Reset):
  show three capsule chips — 🐇 Small / ⏱ Normal / 🐢 Big (`PomodoroKind`'s own
  icons/labels), the active kind tinted with the theme accent. Under the chips,
  a small caption shows the selected kind's lengths, e.g. `25′ + 5′`. Tooltips
  carry the full description.
- **Any live session state** (running, paused, or waiting at a break): the
  phase label renders exactly as today. The picker never shows mid-session —
  `applyKind` would only affect the next block anyway, and the sidebar selector
  still exists for that.
- Tapping a chip calls the existing `timer.applyKind(kind)` — while idle this
  already refreshes the countdown to the new focus length (25:00 → 90:00
  instantly). No new state; the sidebar selector and this picker both read
  `settings.activeKind`, so they stay in sync for free.
- Label ↔ picker swap and chip selection animate with `DS.Motion.snappy`,
  consistent with the sidebar selector.

## Architecture

- **Core:** one new computed property on `PomodoroTimer`
  (`isIdleAtFocus`: not running *and* phase == .focus) so the visibility rule
  is a named, testable fact instead of view-local boolean soup.
- **UI:** `TimerDetailView` gets a private `ringKindPicker` view builder;
  the `ZStack`'s inner `VStack` chooses picker vs. phase label off
  `timer.isIdleAtFocus`.
- No settings, no persistence, no new strings beyond what `PomodoroKind`
  already provides.

## Testing

- Unit tests (swift-testing) for `isIdleAtFocus`: true when fresh; false while
  running; false when paused; false when idle at a pending break; true again
  after `stop()`.
- Existing `applyKind` idle-refresh behavior is already covered by core tests.
- Runtime check via the verify skill: launch the app, open the timer page,
  confirm chips render and switch the countdown while idle, and yield to the
  phase label once started.

## Out of scope

- Removing or changing the sidebar selector.
- Showing the picker during breaks/pauses.
- Menu-bar popover, floating pill, notch, and widget surfaces.
