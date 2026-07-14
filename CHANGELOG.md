# Changelog

All notable changes to Sharingan are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/); versions follow [SemVer](https://semver.org/).

## [Unreleased]

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
  first launch.

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
