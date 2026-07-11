# Menu-bar progress ring — design

Approved 2026-07-11.

## Goal

The menu-bar Sharingan icon shows session progress as a thin ring around the
iris (like segmented-ring timer icons), so a glance at the menu bar answers
"how far along am I" without opening the popover.

## Behavior

- **Engaged session** (running, or paused mid-way — same `engaged` predicate
  `updateTitle()` already uses): iris insets ~2.5 pt, a 1.5 pt ring draws
  around it — dim white track (20% alpha) + bright elapsed arc from 12 o'clock
  clockwise, driven by `timer.progress` (already count-up-aware).
- **Colors:** focus = warm red-orange, breaks = green, paused = current arc
  dimmed. Idle/reset = today's plain icon, no ring.
- **Redraw discipline:** inside the existing 1 s `updateTitle()` tick; the
  bitmap re-renders only when the integer percent, phase, or engaged state
  changes (cached tuple).
- **MM:SS text** keeps obeying `showMenuBarCountdown`. No new setting.

## Touch points

- `Sources/Blink/AppDelegate.swift` — `MenuBarController.menuBarIcon()` gains
  `(progress: Double?, phase: PomodoroPhase, paused: Bool)`; `updateTitle()`
  computes state and swaps `button.image` when the cache key changes.

## Verification

`swift build` warning-free; launch the app, start focus → ring fills red,
skip to break → ring turns green, reset → ring gone. Drawing-only change, no
unit tests.
