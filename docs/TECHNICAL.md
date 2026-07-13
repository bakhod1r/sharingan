# Sharingan (Blink) — Feature Reference

> Every feature of the app, described in plain terms. **Keep this up to date:
> whenever a feature is added, changed, or removed, update this document in the
> same change.**

- Version: 1.0.0
- Platform: macOS 14+, lives in the menu bar

---

## Timer / Pomodoro

- Configurable focus, short break, and long break durations (25 / 5 / 15 by default). Settings' "Pomodoro sizes" section renders as a compact grid (Small/Normal/Big rows × Focus/Break/Long break columns); each size can override its own long-break length, falling back to the global long-break minutes when not overridden.
- Countdown and count-up modes.
- Long break automatically after every N pomodoros.
- Auto-start focus and auto-start break toggles.
- Repeat: run focus sessions back-to-back with a delay, or loop focus↔break endlessly.
- Natural-language time input: `5 min`, `2h 30m`, bare `25`, clock targets like `5pm`, deltas like `+5m` / `-1h`, and `reset` / `stop`.
- Screen flash warning in the last 5 seconds; a "5 minutes left" notification.
- Sleep-aware: closing the lid during focus doesn't wrongly credit hours; a break still completes when you wake the Mac.
- Custom one-off session length that survives mode changes.

---

## Tasks & planning

- Full task system: title, priority (P1–P4), tags, projects, categories, due dates, notes, and estimates.
- Subtasks with their own estimates — reorder them, or promote a subtask into a full task.
- Recurrence: none, daily, weekdays, weekly, every N days, or monthly (on a chosen day). Completing a recurring task spawns the next occurrence.
- Natural-language quick add in the **world's 25 most-spoken languages** at once, e.g. `ertaga 15:00 p1 #ish @blink ~2 hisobot yozish` — with live parse chips while you type, in both the main composer and the menu-bar quick-add. Recognizes:
  - **Dates** — today / tomorrow / day-after-tomorrow / yesterday, weekday names, next week / next month / next year, this week, weekend, and month-name dates like `march 5` / `5 mart` (plus numeric `12.08`).
  - **Times** — clock (`15:00`, `5pm`) and parts of day (`morning`, `noon`, `afternoon`, `evening`, `tonight`, `midnight`), which combine with a day — "tomorrow evening" = tomorrow 18:00.
  - **Recurrence** — daily / weekly / monthly / weekdays / every N days.
  - **Relative offsets** — `in 2 hours`, `in 3 days`, `in 2 months`, plus postpositional forms (`2 soatdan keyin`, `2 saat sonra`, `2 घंटे में`).
  - **Priority words** — `urgent` / `muhim` → P1.
  Works across Latin, Cyrillic, Arabic, Indic, and space-less CJK scripts (Chinese/Japanese matched by substring). All languages are live simultaneously, so a line may mix them. Compositional offsets and month-name dates are fullest in the Latin/Cyrillic set; every language still accepts numeric dates.
- Smart views: Today, Upcoming, All, Completed — each with counts. Free-text search over title, tags, project, and notes.
- Snooze a task to tomorrow, next week, or a picked date; overdue badges.
- Due reminders with a configurable pre-reminder (default 10 minutes before, or off).
- Templates: save any task as a reusable template and instantiate it later. Duplicate tasks too.
- Completed history grouped by day, with restore.
- CSV export.
- **Focus queue**: line up several tasks — each finished pomodoro advances to the next one, the break screen shows "Next: …", and after a break a picker asks what to work on next.
- **Eisenhower matrix** view: tasks sorted into do-first / schedule / delegate / eliminate by urgency and importance.
- **Weekly board**: drag tasks between days to reschedule.
- **Today panel**: a floating desktop card showing today's tasks and the timer.
- Optional guard that requires an active task before focus can start.

---

## Breaks & eye health

- Full-screen break overlay on **every monitor**, above other windows; ⌘Q / ⌘W / ⌘Tab are blocked until the break ends. Includes a skip button.
- Eye exercises: the 20-20-20 rule, 8-direction gaze (plus circles and figure-8), and blink drills.
- Exercise picker chips at the top of the break screen — tap any exercise to run it on demand; the eyes perform it and the sequence continues from there.
- Configurable exercise sequence: turn individual exercises on/off, scale hold times, set rounds.
- **Camera blink & gaze validation** using on-device face tracking — the camera runs only during breaks, never during focus. Optional strict mode waits for real gaze/blink confirmation before advancing a step; otherwise a fail-safe auto-advances.
- Pulsing camera privacy badge whenever the camera is active.
- **Voice guidance (TTS)**: spoken step instructions plus a rotating pool of reminder phrases, with editable text, rate, and pitch.
- **Ambience sounds**: white noise, rain, forest, or lo-fi — looped during breaks.
- **Screen dim**: smoothly dims the display during breaks to a chosen level, restored afterward.
- **Night Shift warmth**: optional warmer screen tone during breaks.
- **Reminders**: posture, water, and custom interval reminders — optionally focus-only, paused during breaks.
- **Phase alarm**: choose the completion sound (glass, chime, soft bell, or silent).

---

## Sharingan eyes & visuals

- 18 iris styles — 1/2/3-tomoe, Mangekyō variants, Rinnegan, and more, all drawn as smooth vector art.
- Pattern evolution: iris designs evolve from tomoe → Mangekyō → Rinnegan.
- Animated eye pair on the break screen that follows the exercise gaze, blinks, and winks.
- **Live wallpaper**: desktop-level eyes that follow the cursor, blink and wink when idle, doze when you're away, and wake with the next pattern.
- Menu-bar icon: a Sharingan iris with rotating tomoe and a progress ring (red-orange during focus, green during breaks, dimmed when paused), with an optional countdown readout.

---

## Stats, streaks & rewards

- Daily focus history with today's count and a best-focus-hour breakdown.
- Weekly and monthly aggregations: week-over-week change, best day, best weekday, average per active day.
- 7-day and 30-day charts.
- Consecutive-day streak tracking that resets on a missed day.
- Milestone badges at 1, 7, 14, 30, 90, and 365 days, with a spring-animated reward banner when a new one is unlocked.
- Pomodoro breakdown by project and by tag.
- A configurable daily pomodoro goal with progress and a "goal reached" notification.

---

## Themes & interface

- Six themes: Liquid Glass, Frosted, Midnight, Cream, Neon, and Mono.
- Liquid-glass design throughout.
- Main window sections: Timer, Tasks, Week, Progress, and Settings.
- Menu-bar popover with timer, tasks, and week tabs plus today's goal.
- Floating timer: an always-on-top panel that joins all Spaces, is draggable, has size presets, and auto shows/hides around breaks.
- Confirmation prompt before quitting while a focus session is running.
- Searchable settings, grouped into: Timer, Tasks & Planning, Breaks, Focus & Blocking, Eye Care, Sharingan Eyes, General, Voice Guidance, and Shortcuts.

---

## Settings layout (essentials + Advanced accordion)

All 9 categories are always visible on the root list (General first —
`SettingsCategory` declaration order). Each category page shows its
essential rows always; extra rows live in one collapsible "Advanced
settings" disclosure at the bottom of the page. There is no global
Simple/Advanced switch and nothing to seed at launch.

- `SettingsCategory` (SharinganCore/Models) — `hasAdvancedRows` is `true`
  for every category except General, Voice, and Shortcuts (those three
  have no accordion; all their content is always visible). Also owns
  search `matches(_:)`. The `tint` color stays in a SettingsView extension.
- `SettingsView.categorySections(_:)` builds the always-visible rows per
  category; `SettingsView.advancedSections(_:)` builds the accordion
  content, in its own `Section`s, shown when `advancedExpanded` is `true`.
  `advancedExpanded` resets to `false` whenever the open category changes.
- Timer's always-visible part shows the full "Pomodoro sizes" section (the
  Small/Normal/Big grid) — there's no simplified two-stepper substitute.
  The floating-timer detail rows (size, always-on-top, dots, task, opacity,
  drag hint) are Advanced, still gated on `settings.floatingTimerEnabled`,
  with a caption ("Enable the floating timer to configure it.") when it's
  off. Eye Care's Advanced "Camera" section is gated on
  `settings.cameraEyeTrackingEnabled` the same way.
- The Sharingan "Desktop wallpaper" section (and its `.onChange` chain that
  re-applies `WallpaperConfig`) stays in `categorySections` — always
  visible — so it keeps observing even while the Advanced accordion
  (which holds the wallpaper spin/idle/doze rows) is collapsed.
- The old `settingsTier` UserDefaults key is a harmless leftover on
  upgraded installs; nothing reads or writes it anymore.

---

## Storage identifiers

- All on-disk identifiers are namespaced `com.sharingan.*` / `sharingan.*`
  (settings `com.sharingan.settings`, stats `com.sharingan.stats`, CLI
  snapshot `com.sharingan.cliSnapshot`, CLI darwin commands
  `com.sharingan.cli.*`, floating-timer/today-panel position keys, the focus
  queue, and the task pre-reminder-minutes setting). Task/template data lives
  in `~/Library/Application Support/Sharingan/` (SQLite db + the `tired` CLI's
  shared `cli/` snapshot files).
- `RebrandMigration` (SharinganCore/Services) performs a one-shot Blink →
  Sharingan copy/move at launch — called by both `AppDelegate` and the
  `tired` CLI entry point. Old `UserDefaults` keys are copied to the new keys (old
  kept, never deleted); the old `Blink/` Application Support directory is
  moved (renamed) to `Sharingan/`, never merged into an existing `Sharingan/`
  dir. Safe to call on every launch — a copy/move only happens once, the
  first time the new location is still empty. Stored `dndShortcutOn/Off`
  values inside a user's settings blob are deliberately NOT rewritten (they
  name real user-created Shortcuts.app shortcuts); only the code defaults for
  fresh installs changed, to "Sharingan Focus On/Off".
- `TaskStore.sweepLegacyNotificationsIfNeeded()` (run once post-upgrade from
  `AppDelegate`, flag `sharingan.migration.notificationsSwept`) removes
  pending `blink.task.*` due/pre-reminder notification requests — their IDs
  were renamed to `sharingan.task.*`, so the old ones had become
  uncancelable — then reschedules open due-dated tasks through the normal
  `syncDueNotifications` path.

---

## Focus enforcement & integrations

- **App blocking**: hide or force-quit distracting apps (presets include Chrome, Safari, VS Code, Slack, Telegram, Messages) — during breaks, during focus, or always.
- **Do Not Disturb**: toggles a macOS Focus mode automatically at the start and end of sessions.
- **Global keyboard shortcuts** (rebindable): start/pause, skip, reset, +5 minutes, toggle floating timer, and quick-add task.
- **`tired` CLI** — control the app from Terminal: start (with natural-language input), pause, resume, skip, reset, add/remove/set time, check live status, and manage tasks (add, list, mark done, start, queue).
- **`sharingan://` URL scheme** for Shortcuts / Raycast: start, pause, resume, skip, reset, show, toggle floating timer, and add a task.
- **Launch at login** toggle.

---

## Sync

- iCloud sync is planned but **not active** in this build.

---

## Marketing site

- A single landing page focused on the three pillars — Pomodoro, Tasks, Eye health — each with a hand-built animated **CSS mock** of the app's UI (no videos, GIFs, or app renders): a counting timer ring, a Today panel that checks tasks off and slides new ones in, and the break screen with app-shaped almond eyes (MoveEyeShape Béziers via clip-path) running a guided drill with a spinning Sharingan iris.
- A "Top features" grid of 12 cards, each with its own mini CSS animation (menu-bar timer, floating timer, focus queue, streak chart, app blocking, ambience equalizer, voice arcs, screen dim, reminders, weekly board, six themes, CLI).
- One live demo: the natural-language quick-add parser, in-page. Animated CLI terminal, FAQ (honest about sync being planned, not shipped), download.
- Hero sits over the live WebGL eyes (loaded after window "load" so they never touch the critical path); below-fold animations stay paused until their section is revealed.
- Light/dark theme toggle that remembers your choice; respects reduced-motion preferences.

---

*Maintenance rule: any change that adds or alters a feature must update this
document (and the changelog) in the same change.*
