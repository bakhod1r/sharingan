# Simple / Advanced Settings — Design

**Date:** 2026-07-13
**Status:** Approved for planning

## Problem

Settings has 9 categories and ~85 controls. Most are power-user knobs
(`stepHoldScale`, `kalibIntervalSeconds`, `wallpaperIdleDelay`, …). A new
user opening Settings faces the full wall at once. We split the surface into
a **Simple** tier (most-used essentials, ~32 rows) and an **Advanced** tier
(everything, the current ~85), selected by one global switch.

## Mechanism

- A segmented switch **Simple | Advanced** sits under the Settings title on
  the root list (visible on category pages too, or reachable via back).
- The choice persists in `@AppStorage("settingsTier")` — it is UI state, not
  part of the `PomodoroSettings` JSON blob.
- Every row keeps a single source of truth: advanced rows/sections are
  wrapped in `if advanced { }` conditionals in place (see Code structure
  for why a modifier doesn't work here). No duplicated view code.
- **Hidden ≠ disabled.** Advanced values persist and stay in effect while
  hidden. Switching to Simple never resets or deactivates anything.

## Default tier

- Fresh install → **Simple**.
- Existing user (a saved settings JSON blob already exists at first launch
  after update) → **Advanced**, so nothing they already saw disappears.
- One-shot migration; after that the stored choice wins.

## Later decisions

- **2026-07-13:** General moved to the top of the root list; Theme moved
  from Timer to General/Appearance (user decision).
- **2026-07-13 (Task 8):** The global Simple|Advanced switch and
  `SettingsTier` were removed entirely, after seeing the built UI. All 9
  categories are now always visible on the root list; each category page
  shows its essentials always, with the former Advanced rows moved into a
  per-page collapsible "Advanced settings" accordion at the bottom (closed
  by default, resets to closed on every page switch). Timer's Pomodoro
  sizes grid (Small/Normal/Big) is now always visible — the two-stepper
  "Durations" Simple substitute was deleted. The Eye Care "Spoken
  instructions" bridge toggle was removed since Voice Guidance is now
  always reachable from the root. See `task-8-brief.md` for the exact
  per-category section split.
- **2026-07-13 (Task 10):** Timer's "Pomodoro sizes" section is now a
  compact `Grid` (rows = Small/Normal/Big, columns = Focus/Break/Long
  break) instead of 6 stacked stepper rows, and each size can now override
  the long-break length (`PomodoroKindConfig.longBreakMinutes`, optional;
  nil falls back to the global `PomodoroSettings.longBreakMinutes`). The
  "Long break" section's global minutes stepper was removed — only "Long
  break every N pomodoros" remains there; the stored global value silently
  stays as the fallback for sizes never overridden, so old settings blobs
  behave identically. See `task-10-brief.md`.

## Category visibility

Simple shows 7 of 9 categories (starting with **General**, which includes
an "Appearance" section with the Theme picker—both tiers). **Voice
Guidance** and **Shortcuts** are Advanced-only (their one essential
control — "Spoken instructions" on/off — is surfaced in Eye Care).

Row counts below are indicative (control groups counted as one row); the
row-by-row split is the authority.

| Category | Simple rows | Advanced adds |
|---|---|---|
| General | 6 | — |
| Timer | 7 | +18 |
| Tasks & Planning | 3 | +3 |
| Breaks | 4 | +5 |
| Focus & Blocking | 3 | +7 |
| Eye Care | 6 | +4 |
| Sharingan Eyes | 3 | +9 |
| Voice Guidance | — | 3 (whole category) |
| Shortcuts | — | 7 (whole category) |

## Row-by-row split

### General
**Both tiers:** Appearance section with Theme picker (six themes: Liquid
Glass, Frosted, Midnight, Cream, Neon, Mono).
**Simple:** auto-start focus, auto-start break, launch at login, notify
5 min left, alarm sound (toggle + picker).

### Timer
**Simple:** focus length, break length (both for the *active* pomodoro kind
— see below), long break minutes, long break every N, floating timer
on/off, Today panel on/off, menu bar countdown.
**Advanced:** timer mode, time format, flash at 5 s, the full
Small/Normal/Big per-kind duration grid (6 steppers), repeat block
(enabled/endless/count/delay), floating timer details (size preset,
opacity, always-on-top, dots, task pill).

*Simple duration steppers:* instead of the 3×2 per-kind grid, Simple shows
two steppers bound to `settings.focusMinutes` / `settings.shortBreakMinutes`
(the active kind's config). Advanced shows the full grid as today.

### Tasks & Planning
**Simple:** require a task to start focus, daily pomodoro goal, due
pre-reminder picker.
**Advanced:** week starts on Monday, default subtask estimate, show 🍅
badges.

### Breaks
**Simple:** break message text, block screen during break, show "Exit
break" button, ambience (toggle + sound picker + preview).
**Advanced:** brightness dim (toggle, level, smooth), warm colors /
Night Shift (toggle, strength).

### Focus & Blocking
**Simple:** block distracting apps on break + the app list (presets ship
sensible defaults), reminders enabled.
**Advanced:** also block during focus, force-quit, Do Not Disturb block
(toggle, on/off shortcut names, test), reminders detail (during-focus-only,
per-reminder rows, add reminder).

### Eye Care
**Simple:** 20-20-20 / gaze / blink toggles, exercise rounds, camera eye
tracking on/off, spoken instructions on/off (mirrors
`ttsSettings.enabled`), preview break screen button.
**Advanced:** step hold scale, kalib interval, per-direction instruction
editor, strict exercise validation.

### Sharingan Eyes
**Simple:** iris style picker (single), break background, eyes-on-desktop
wallpaper toggle.
**Advanced:** per-eye style, pattern animation speed, mixed patterns,
pattern spin, wallpaper spin trigger/speed/idle delay/doze.

### Voice Guidance (Advanced-only category)
Voice rate, voice pitch, global kalib pool. (The master on/off lives in
Eye Care for Simple users; it is the same underlying setting.)

### Shortcuts (Advanced-only category)
Global shortcuts toggle + 6 recorder rows.

## Discoverability bridges

1. **Search always spans both tiers.** In Simple mode a match on an
   Advanced-only category/row still appears, marked with an "Advanced"
   chip; opening it switches the tier to Advanced.
2. **Footer link on each Simple category page:** "*More settings in
   Advanced →*". Tapping switches tier in place. (No hidden-row count: the
   variadic `SettingsCard` row layout would render a preference-carrying
   placeholder as an empty row with a stray divider, so the link is
   countless by design.)
3. Hidden settings keep working (e.g. a wallpaper spin configured in
   Advanced continues after switching to Simple).

## Code structure

- `SettingsTier` enum (`simple`/`advanced`) in `SharinganCore` so it is
  testable; UI persistence via `@AppStorage("settingsTier")`.
- `SettingsCategory.tier` property → `.voice`/`.shortcuts` return
  `.advanced`.
- Rows/sections gated in place with `if advanced { }` conditionals in
  `SettingsView.categorySections` — a modifier whose body conditionally
  omits content still counts as a variadic child in `SettingsCard` and
  would leave an empty padded row with a divider; a false `if` yields
  zero children (the pattern the file already uses for conditional rows).
- First-launch migration: if the settings blob file exists and no tier has
  been chosen yet → seed `advanced`; else `simple`.
- Tests: Simple root shows exactly 7 categories; search in Simple finds
  Voice/Shortcuts keywords; migration seeds the right default; hidden
  advanced values survive a tier round-trip unchanged.
- Update `docs/TECHNICAL.md` with the tier concept and the split table.

## Error handling

No new failure modes: the tier is a plain enum with a safe default
(`simple`); unknown stored values fall back to `simple`. Settings decoding
is untouched.

## Out of scope

- No per-category "Advanced" disclosure sections (superseded by the global
  switch).
- No re-ordering or renaming of existing settings keys; no data migration
  of values.
