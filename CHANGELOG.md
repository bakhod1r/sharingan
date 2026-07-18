# Changelog

All notable changes to Sharingan are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/); versions follow [SemVer](https://semver.org/).

## [Unreleased]

## [1.10.0] - 2026-07-18

### Changed
- **Unified Dashboard** — the separate **Progress**, **Analytics**, and
  **Report** sidebar pages are now one **Dashboard** page with scrollable,
  icon-labelled tabs: Overview, Progress, Heatmap, Focus load, Timeline,
  Apps, Report, Export. One shared filter bar drives them all.

### Added
- **Premium Overview** — a hero KPI row (focus time, sessions, day streak,
  active days) with count-up numbers and a staggered card entrance, above
  the Focus/Consistency score rings. All motion honours Reduce Motion.
- **Calendar range picker** — a custom **from → to** date range (popover
  with two date pickers) that overrides the preset ranges across every tab
  and the score averages.
- **Per-Mac analytics** — sessions now record which Mac they ran on
  (`SessionRecord.deviceName`); a device filter in the bar (shown when more
  than one Mac has data) slices every tab by machine.

### Technical
- `AnalyticsFilter` gains `devices`, `customStart/customEnd`, and
  `interval(now:)` / `spanDays` / `heatmapSpanDays` helpers.
- `AnalyticsEngine` gains `appTotals(sessions:)`, `devices(in:)`, and a
  `devices:` argument on `filter(...)`.

## [1.9.0] - 2026-07-17

### Added
- **Active app tracking** — Analytics → **Apps** tab shows which apps you
  were focused in, ranked by time with icons and share bars. App-level
  only (no window titles, no Accessibility permission), stored on your
  Mac. Configurable in Settings → Tasks & Planning → Analytics
  (Off / During focus only / Always; default focus-only).
- **Timeline** tab — a day's sessions laid out across the clock (focus,
  breaks, abandoned) with a session list; the day pager is a **time
  machine** to replay any past day.
- **Burnout detection** — an Overview banner (and a once-a-day
  notification) when recent sessions show warning signs: huge days,
  heavy streaks, skipped breaks, or repeated late-night focus.
- **Smart insights** — templated suggestions on the Overview (best hour,
  best weekday, break/abandon nudges).
- **Export** tab — save the filtered session history as **CSV**, real
  **.xlsx** (dependency-free writer), or a one-page **PDF** summary.

## [1.8.2] - 2026-07-17

### Changed
- **Analytics filters are now multi-select** — pick several categories,
  projects, and tags at once (OR within a facet, AND across facets); each
  choice shows as a removable chip with a "Clear all".
- **GitHub-style heatmap** — month labels along the top, weekday labels
  down the left, rounded cells, and a range-driven span.
- The **time range** now applies to every Analytics tab: it averages the
  Overview scores, sets how far the heatmap spans (4 weeks … 1 year), and
  drives the focus-load chart — Today shows the day's curve with a rolling
  average, a wider range shows the total hourly load across that window.

### Added
- The **Big** pomodoro size is now called **Deep Work** (its saved data is
  unchanged; task search still matches both "deep work" and "big").

### Added
- **Analytics filters** — a filter bar on the Analytics page:
  - **Time range** (Today / 1W / 1M / 3M / 1Y) averages the Overview
    Focus and Consistency scores over the window (past-day plan adherence
    is unknown, so it uses its neutral default; the streak is
    reconstructed from the session log).
  - **Category / Project / Tag** narrows every tab to sessions credited
    to matching tasks, with a "Filtered by …" chip (✕ to clear). The
    heatmap recomputes from the session log while a filter is active.
  - **Completed only** toggle drops skipped/abandoned sessions.

### Changed
- The Analytics page now uses the full window width (like the weekly
  board) and scrolls, with larger score gauges — it was cramped in a
  640pt column before.

## [1.8.0] - 2026-07-17

### Added
- **Analytics page** (sidebar, between Progress and Report) with three tabs:
  - **Overview** — daily **Focus Score** (0–100: focus volume vs goal,
    completion ratio, break compliance, deep blocks) and **Consistency
    Score** (plan adherence, start-time regularity, streak), drawn as
    accent ring gauges. No sessions yet ⇒ "—", never a fake zero.
  - **Heatmap** — GitHub-style yearly grid of completed pomodoros with a
    5-step intensity legend and hover details, fed from the long-lived
    daily history so it's full even before the new session log grows.
  - **Focus load** — minutes of focus per hour of day ("diqqat
    cho'qqilari") for any day (◀ ▶ pager) with a dashed 30-day-average
    overlay.
- **Per-session focus log**: every really-finished session (completed, or
  skipped/stopped after ≥1 minute) is recorded with start/end, phase,
  completion, planned length, and the focused task — the foundation for
  the timeline/replay, time machine, burnout detection, and export
  features coming next. Stored locally in `focus-sessions.json` (400-day
  retention); writes never block the timer; a corrupt file is set aside,
  never crashes the app. Mirrored (synced-from-another-Mac) sessions are
  logged only by the owning Mac.

## [1.7.3] - 2026-07-17

### Fixed
- The app could freeze at launch — no windows, no menu bar icon — when
  writing the widget snapshot into the group container blocked forever
  (a wedged containermanagerd hangs the `open()` syscall). Snapshot
  writes now run on a background queue, so the menu bar icon always
  comes up no matter what the container daemon is doing.

## [1.7.2] - 2026-07-17

### Changed
- The menu bar icon now always appears at the end of the menu bar (the
  rightmost third-party slot, next to the system icons) on every launch,
  so a stale or notch-parked stored position can never hide it. A ⌘-drag
  still works within a session but no longer survives a relaunch.

## [1.7.1] - 2026-07-17

### Fixed
- Menu bar icon never appeared on notched MacBooks with a fresh install:
  the first-launch position seed wrote `-1.0` (past the screen's right
  edge) instead of the intended far-right slot (`6.0`), so AppKit could
  never place the status item. Now seeds `6.0`, and installs already
  stuck with a negative stored position are repaired on next launch.

## [1.7.0] — 2026-07-17

### Added
- Tasks carry a permanent issue number, shown as "T-42" everywhere a task
  is named — notch, widget, menu bar, board, task list, report. It replaces
  the UUID-derived short code that could collide; existing tasks are
  backfilled oldest-first, and numbers are never reused or renumbered.
- Trash for tasks: deleting soft-deletes with restore, permanent delete,
  Empty Trash, and automatic retention purge on launch.
- Projects: a second colour/icon-tagged axis alongside categories, managed
  from the sidebar (add/rename/recolor/delete).
- Due dates can carry an optional time of day.
- Deadlines can read as a countdown ("2d 4h left") via a new setting; a
  date-only due expires at the end of its day, matching the overdue rule.
- Settings → iCloud sync gained "Retry at most every" (1–15 min) to cap
  sync push retry backoff.

### Changed
- Board cards restyled Jira-like: flat surface, tight radius, a footer lane
  with type square, task code, priority arrow, subtask count and estimate
  pill; the deadline gets its own row. Cards size themselves instead of
  stretching, so long titles no longer spill across neighbouring columns.
- iCloud pushes go through a durable per-record outbox with tombstones that
  survive shadow resets, with exponential-backoff retry.

### Fixed
- Saving task templates wiped every template from the database on the next
  launch: the post-save prune matched template *names* against UUID keys and
  deleted all rows. Templates now prune by their UUID column.
- Sync retry backoff never actually reached its documented 5-minute
  ceiling; the cap is applied (and now configurable).
- The break overlay respects "Auto-start break", and the task picker is
  shown after a break whenever "Auto-start focus" is off.
- A menu-bar icon that AppKit parked off-screen at the bottom-left corner
  (no slot found) stayed invisible for good; that case is now detected and
  repaired alongside the behind-the-notch one.

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
