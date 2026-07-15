# Changelog

All notable changes to Sharingan are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/); versions follow [SemVer](https://semver.org/).

## [Unreleased]

## [1.6.1] — 2026-07-15

### Fixed
- Hovering a task row to reveal its edit/delete buttons could flicker
  on/off in a loop — inserting them shifted the Play button under the
  cursor, which toggled hover state right back off.
- The menu-bar popover's translucent tab bar and stats strip let the main
  window's sidebar bleed through when both were open at once, garbling
  the tab labels. The main window now hides itself while the popover is
  showing and comes back when it closes.
- Widened the popover from 360 to 460pt — task rows and the composer's
  filter chips needed more room than that and were clipping on both edges.

### Changed
- Replaced the flat segmented tab picker (Pomodoro/Tasks/Week/Report)
  with a custom liquid-glass pill that glides to the selected tab.
- Skip / Reset / +5m / -5m / Exit break now share the Start button's
  theme-accent capsule treatment instead of neutral glass, so the control
  stack reads as one themed family.

## [1.6.0] — 2026-07-15

### Fixed
- A break mirrored from another Mac showed a frozen "time left" — the
  overlay was presented at focus-complete against a *pending* break with no
  live deadline yet. It now comes up when the owner Mac's break record
  actually arrives, so the countdown ticks from the start.
- Settings changes (timer mode, durations, theme, anything in the synced
  blob) made on one Mac now actually reach the other Mac's running app: the
  applied value used to land only in `UserDefaults`, which the live
  `PomodoroTimer` never re-read until relaunch.
- iCloud settings sync stopped a slow ping-pong: pushing/applying identical
  values back and forth (remote change → apply → local-change observer →
  push the same bytes back) is now skipped by value comparison.

### Changed
- Local settings edits push to iCloud immediately (2 s debounced) instead of
  only at the next explicit `SettingsSync.start()`.
- The sync fallback poll dropped from 15 minutes to 60 seconds — mirrored
  timers, breaks, and settings now land in about a minute worst-case instead
  of a quarter hour.
- Sparkle updates are fully silent: checked and downloaded automatically in
  the background, then installed (with a relaunch) the moment no focus/break
  session is running — no "update available" dialog, no manual step.
- Settings' segmented controls (Timer mode, Floating widget size/position,
  import template format) and the plain action buttons (ambience Preview/
  Stop, Check Now…) now render as the app's liquid-glass capsule style
  instead of the stock AppKit controls.

## [1.5.0] — 2026-07-15

### Added
- A break synced in from another Mac now blocks this screen too: the mirrored
  Mac shows the same full-screen break overlay (eye exercises, ambience, dim,
  app blocker) instead of just counting the break down in the corner.

### Changed
- Timer mirroring no longer clobbers a session you started locally: each Mac
  can run its own independent session (different tasks, different lengths),
  and a remote session is mirrored only while this Mac's timer is idle.
- A mirrored phase completes passively: the Mac that owns the session decides
  (and publishes) what comes next, so the mirroring Mac no longer auto-starts
  a surprise pomodoro right after a synced break, and no longer double-credits
  the synced task's pomodoro count or advances the focus queue a second time.

### Fixed
- SharinganCoordinator now only reacts to its own timer's phase completions
  (the subscription was unfiltered, so preview/test timers could tear down the
  real break overlay).

## [1.4.0] — 2026-07-15

### Added
- Floating widget shows a pomodoro dot row next to the time: the active
  task's estimate when it has one (filled by its completed pomodoros),
  otherwise the user's finite Repeat ×N selection, otherwise 3 dots —
  capped at 8 so a big estimate can't stretch the pill.

## [1.3.1] — 2026-07-15

### Fixed
- iCloud sync actually connects now. CloudKit requires the app's sealed
  entitlements to carry `com.apple.application-identifier` — the provisioning
  profile alone isn't consulted — so 1.3.0 builds were denied with "Could not
  determine iCloud account status" even when everything in the portal was
  right. Verified live: the container is approved and records upload.
- Floating widget's task picker closes itself a second after the pointer
  leaves it.

## [1.3.0] — 2026-07-15

### Added
- **iCloud sync** (opt-in, off by default): tasks, categories, tags, templates,
  focus statistics and settings follow you between Macs through your private
  iCloud database. Turn it on in Settings → iCloud sync. Conflicts never lose
  data — the newest edit of a task wins, statistics from two Macs add up
  instead of overwriting each other, and a delete never swallows an edit made
  after it elsewhere.
- The active timer is mirrored read-only across Macs: start a focus session on
  one Mac and the other shows it.
- Near-instant sync via CloudKit silent push, with wake/foreground and
  periodic fetch fallbacks when push can't reach the app.

### Note
- Sync requires the app to be signed with an iCloud-capable provisioning
  profile. Builds without one (including local `make app` builds) run exactly
  as before — the Settings section simply reports sync as unavailable.

## [1.2.0] — 2026-07-15

### Added
- **Auto-updates.** Sharingan now updates itself: "Check for Updates…" in the
  menu, an Updates section in Settings (automatic checks, current version,
  check now), and a signed Sparkle appcast published alongside every release.
  Each update is verified against the app's EdDSA key on top of Apple's own
  signature check.

### Changed
- **Signed and notarized.** Releases carry a Developer ID signature, a
  hardened runtime and an Apple notarization ticket stapled to both the app
  and the DMG — the "Sharingan can't be opened / Apple could not verify" wall
  on first launch is gone, with no `xattr` incantation or Privacy & Security
  detour. The release build fails if Gatekeeper would reject the artifact, so
  an unopenable DMG can no longer ship.
- Bundle identity moved onto developer-scoped identifiers
  (`com.bakhod1r.sharingan`, app group `89LCRZKZ48.com.bakhod1r.sharingan`) as
  signing requires. Settings and data from 1.1.x migrate automatically on
  first launch. Two things the migration can't carry over automatically:
  desktop widgets placed under 1.1.x need to be re-added (the widget's bundle
  identity changed too, so macOS treats it as a new widget), and Launch at
  Login may need a one-time re-enable in Settings.

### Note
- This release must be installed by hand one last time — 1.1.x has no updater
  to offer it. Updates from 1.2.0 onward install in-app.

## [1.1.0] — 2026-07-14

### Added
- **Universal binary.** The app and its WidgetKit extension now ship both
  arm64 and x86_64 slices, so Sharingan runs on Intel Macs as well as Apple
  silicon. `make-dmg.sh` builds universal by default (a DMG is what other
  people download; an arm64-only bundle simply refuses to launch on an Intel
  Mac) and fails loudly if either slice is missing. Local `make-app.sh` stays
  host-arch for speed — pass `--universal` to match a release build.

### Fixed
- The bundle version now matches the public release line: the v1.0.0 DMG's app
  still reported the pre-public `1.20.0` internal version.

## [1.0.0] — 2026-07-14

Initial public release.

### Added

- **Pomodoro timer** — configurable focus / short break / long break durations
  (25 / 5 / 15 defaults), countdown and count-up modes, three quick-switch
  sizes (Small `10′+3′`, Normal `25′+5′`, Big `90′+15′`, each editable and
  reachable from a picker inside the timer ring while idle), auto-start
  toggles, long break every N pomodoros, natural-language time input
  (`5 min`, `2h 30m`, `5pm`, `+5m`), and `±5m` on the fly.
- **Enforced breaks** — full-screen, multi-monitor break screen at
  screen-saver level with ⌘Q/⌘W/⌘Tab blocked, a liquid-glass countdown ring,
  and a skip button.
- **Eye health** — 20-20-20, 8-direction gaze, and blink exercises with
  animated guides and voice instructions; optional camera-based blink/gaze
  verification via Vision, with a privacy indicator. Break eyes render as an
  animated Sharingan — 18 iris styles from classic tomoe to Rinnegan.
- **Tasks & planning** — natural-language quick add in English and Uzbek
  (`ertaga 15:00 p1 #ish ~2 hisobot yozish`), priorities, projects, tags, due
  dates, notes, subtasks, recurrence, templates, a focus queue, Eisenhower
  matrix, weekly board, and per-project/tag reports.
- **Six surfaces** — menu-bar popover, main window, notch HUD with live
  "ears", draggable floating pill timer, a WidgetKit desktop widget, and a
  glass Today panel on the desktop.
- **Streaks & stats** — daily streak tracking with milestone badges (1→365
  days) and SwiftCharts history.
- **Break comfort** — ambience sounds (white noise, rain, forest, lo-fi),
  smooth screen brightness dim, optional Night Shift warmth, and
  posture/water/custom reminders.
- **Focus enforcement** — hide or force-quit distracting apps during breaks.
- **Automation** — global hotkeys, the `sharingan://` URL scheme for
  Shortcuts/Raycast, and the `tired` command-line tool.
- **Six themes** — Liquid Glass, Frosted, Midnight, Cream, Neon, Mono.

iCloud sync is planned but not shipped in this release.
