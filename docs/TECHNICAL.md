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

- Full task system: title, priority, tags, projects, categories, due dates, notes, and estimates.
- **Extensible priority levels.** The four built-ins (P1 Urgent … P4 No priority) ship by default, but the sidebar's Priority section has a "+" to add your own levels *above* P1 (each requires a name + flag color); a custom row's context menu deletes it, moving its tasks back to No priority. `TaskPriority` is an `Int`-backed struct (was an enum) that Codes as a bare `Int`, so old tasks.json / SQLite rows decode byte-for-byte unchanged. **Renumbering semantic:** chip labels are rank-based, not fixed — adding one custom level makes it "P1" and pushes the built-in Urgent to "P2", etc. Everything above P2 (medium) counts as *important* in the Eisenhower matrix, so custom levels are always important.
- Sidebar Tags section has a "+" to precreate a tag (name only, no color UI) before it's ever typed on a task; it shows dimmed with 0 uses until applied, and its own "Remove tag" (distinct from the destructive "Delete label" that strips a tag off every task) drops it again.
- Per-task pomodoro type (Small/Normal/Big, or Auto to inherit the app default) — shown as a small icon+label badge in the task row's metadata line when set (nil/Auto shows nothing); subtasks can override it too, shown as an icon-only badge next to the subtask row.
- Subtasks with their own estimates — reorder them, or promote a subtask into a full task. A task's displayed estimate (row badges, editor summary, menu-bar rows) is its own estimate when it has no subtasks, or the **sum of its subtasks' estimates** when it does (falling back to its own estimate if no subtask carries one); the stored per-task estimate is unchanged and still what the editor/composer/parser write.
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
- Menu-bar popover with timer, tasks, and week tabs plus today's goal. The
  popover pins its own `NSAppearance` to dark: `NSApp.appearance` does not reach
  it because an `NSPopover` resolves appearance from its anchor view (the
  status-item button in the system menu bar), so under Light mode the dark-glass
  content used to render white-on-light.
- Text fields submit through a single `.onSubmit` — the legacy
  `TextField(onCommit:)` initializer is banned (`SubmitWiringTests` lints for
  it). On macOS `onCommit` fires on Return *and again* on end-editing with the
  field editor's stale text re-synced into the binding, which double-added
  every quick-add task; some fields even had the same handler wired through
  both `onCommit:` and `.onSubmit`.
- Floating timer: an always-on-top panel that joins all Spaces, is draggable, has size presets, and auto shows/hides around breaks.
- Notch HUD: an island over the MacBook camera housing — live ears while a session runs, the user's open tasks and quick actions on hover. Configurable (see below); absent, and disabled in Settings, on a Mac without a notch.
- Confirmation prompt before quitting while a focus session is running.
- Searchable settings, grouped into: Timer, Tasks & Planning, Breaks, Focus & Blocking, Eye Care, Sharingan Eyes, General, Voice Guidance, and Shortcuts.

---

## Settings layout (essentials + Advanced accordion)

All 10 categories are always visible on the root list (General first,
Notch HUD right after Timer — `SettingsCategory` declaration order). Each category page shows its
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
- The **Notch HUD** is its own category (declared right after Timer, so it
  sits under Timer in the sidebar), not buried in Timer's Advanced tier. Its
  essential rows are the master "Show the notch HUD" toggle and the ears
  picker; its Advanced tier ("Notch HUD details") holds the live-activity
  toggle and the four "what the panel shows" switches plus the 3–5 task-row
  stepper. Everything but the master toggle greys out while the HUD is off —
  and on a Mac with **no camera housing the whole category renders disabled**
  (visible, greyed, inert) with a note saying so, rather than being hidden.
  The notch search terms (notch, island, ears, camera housing, menu bar, …)
  route to `.notch`, not Timer. `hasNotch` is answered by
  `NotchWindowManager.hudScreen()`, re-asked on screen-parameter changes.
- The old `settingsTier` UserDefaults key is a harmless leftover on
  upgraded installs; nothing reads or writes it anymore.

---

## Notch HUD

A black island over the MacBook camera housing (`NotchWindowManager`, an
`NSPanel` above the menu-bar window level). It exists **only** on a display with
a real hardware notch: `hudScreen()` (a top safe-area inset *and* both auxiliary
top areas) is the single source of truth, and there is deliberately no synthetic
pill and no simulate flag. Settings asks the same function, so it can never
disagree with the HUD about whether the Mac has a notch; it re-asks on
`didChangeScreenParametersNotification`.

- **The wide states are a T, not a slab.** `activity` and `expanded` used to be
  rectangles anchored to the top of the screen, so their black — and, since the
  mask follows the drawn shape, their dead hit region — covered the menu-bar
  titles either side of the notch. The silhouette is now a **stem** the width of
  the hardware cutout occupying the menu-bar row (space the camera housing
  already took), and a **body** that begins at `menuBarHeight` and hangs below
  it, centered under the cutout. `NotchSilhouette` (SharinganCore) carries the
  numbers — `stemWidth`, `bodyTop`, the bottom radius, the body's outer top
  radius and the **concave fillet** where the body flares out of the stem — and
  `NotchGeometry.islandPath(in:silhouette:)` cuts one non-convex path from them
  that both `IslandShape` draws and `hitTest` masks against. The menu-bar strip
  either side of the stem is outside the path, so it is outside the mask: a click
  on `File` while the island is expanded reaches `File`. The short states
  (`idle`, `live`) are unchanged — a stem as wide as the island degenerates the T
  to the rounded-bottom rectangle they always drew, so the ears still sit in the
  menu-bar row. Only the corner radius animates on `IslandShape`; the stem width
  and body top are deliberately non-animatable, so they flip with the mask while
  the frame springs, keeping the drawn shape inside the mask through the morph.

- **The window hugs the current state's silhouette.** The panel used to be the
  union of every state (`panelSize`, ~356×290) at all times, giving everything
  below the island back through `hitTest` + alpha click-through — which the
  window server caches, and the stale cache left a dead click zone over the
  browser tab strip after an expand-and-collapse even with the island closed.
  The window keeps the union *width* (the live ears span it; its side margins
  are menu-bar row the mask hands back) but its **height** is the state's own
  `NotchGeometry.panelHeight` — `layout.island.maxY`, top edge pinned, bottom
  edge the only mover, so no geometry coordinate shifts. `syncPanelFrame`
  follows every `state.size` change: **grow before** the opening spring
  (synchronously, off `model.$state`'s willSet emission), **shrink after** the
  closing one (`NotchMotion.windowShrinkDelay`, 0.45s, cancelled by the next
  state change), `.hidden` orders the panel out entirely. A closed island
  leaves *no window* below the menu-bar row — nothing to swallow a click. The
  view's root fills the hosting view (`maxWidth/maxHeight: .infinity`,
  top-leading) instead of fixing itself to `panelSize`, or `NSHostingView`
  would center the oversized root in the shorter window; `panelSize` remains
  the geometry's canvas (all x-coordinates) and the dev preview's frame.
- **The live ears are dark glass; the cutout span stays black.** `earGlass`
  (`NotchHUDView`) paints the two slabs either side of the cutout with the
  expanded body's recipe — `.regularMaterial`, the theme wash, the hairline —
  driven off the layout's ear rects, so a dropped ear drops its glass. The
  cutout column stays pure black: it imitates hardware. Visual only — no rect
  the mask is cut from changes.
- **The closed island paints nothing beyond the housing.** Idle is exactly the
  hardware cutout (`NotchGeometry.layout`, `.idle`): the old 4pt lip read as
  hardware over a dark menu bar but showed as a black droplet under the notch
  over a light one (light wallpaper). The lip survives only in `.live` —
  `NotchGeometry.liveLipHeight`, the strip the progress line runs along — so
  `panelHeight(.idle) == notchHeight` and the hover target is the cutout
  itself (the pointer still tracks through the notch region).
- **The island dresses for the theme.** The body's and ears' surface wash is
  `timer.settings.theme.gradient` at 0.20 over the dark material (the Today
  panel's recipe, so light themes tint rather than lighten), read in `body` so
  a Settings change restyles it live. Phase-*semantic* marks stay
  phase-colored — the progress line, the phase dot, the clock glow, the
  active-row tint — except on Mono, where `SharinganTheme.notchPhaseAccent`
  (`NotchHUDView`) desaturates the glow/row/running-control/announcement-icon
  to the near-white accent (line and dot stay phase-colored as the two pinned
  phase reads). Interactive accents (hover hairline, streak flame, a 0.22
  stroke on the quick-action chips) take `theme.accent`; Neon alone trades the
  neutral `dsHairline` rim for its own gradient (`islandHairline`). Paint
  only — no geometry changes; `--render-dev-preview` shoots
  `notch-{expanded,live}-<theme>.png` for all six themes.
- **Quick actions are ＋ and ⚙ only** (quick add, open Blink). The blocker
  toggle and the Today-panel toggle were cut on user feedback; blocking state
  still shows in the status strip. The row keeps its measured
  `quickActionsHeight`.

- **Configurable content.** `PomodoroSettings.notchShow{TimerControls,Tasks,
  QuickActions,StatusStrip}` + `notchTaskRows` (3–5), projected through
  `settings.notchContent` into `NotchContentConfig` (SharinganCore) — the one
  value the layout, the drawn shape, the panel's sections and the hit-test mask
  all read, off `NotchHUDModel.config`.
- **The island is sized from that config**, not from a constant:
  `NotchGeometry.expandedSize(_:menuBarHeight:)` = `menuBarHeight + body`, where
  the body is the whole crossbar below the menu bar,
  `body = 10 + Σ(sections) + 8 × count + 4 top-and-bottom` (`10` top padding, `10`
  bottom, `4` slack). Every constant (`timerRowHeight` 51, `taskRowHeight` 28 + 2
  spacing, `quickActionsHeight` 24, `statusStripHeight` 13) was **measured** off a
  structural SwiftUI replica of `NotchExpandedPanel` at the island's 340pt width
  via `fittingSize` — full panel, five rows = **288pt of body** (the T moved the
  content out of the menu-bar row and gave it a 10pt top padding of its own, where
  it used to clear the camera housing with a 6pt gap: 278 → 288). The island is
  that body plus the menu-bar row the stem passes through. Guessing here clips the
  content at the `.clipShape` or hangs dead black over the screen; changing the
  panel's stack, fonts, spacing or width means re-measuring.
  Floored at `activitySize(menuBarHeight:).height`, so `NotchHUDSize.growthRank`'s
  promise that `.expanded` is the biggest shape survives an all-sections-off
  config.
- **The list is the user's real open work, not just dated tasks.** `NotchTaskRows`
  merges four tiers, deduped and capped: the active task (`TaskStore.activeTaskID`)
  first, then the focus queue in order, then today's `.today` tasks, then a
  fallback to the rest of the open (not-done) list — newest-created first, the
  closest stand-in for "recently relevant" absent a touched-at stamp. The fallback
  is why an all-undated task list still fills the island: the `.today` filter
  (planned/due/overdue) can't see a dateless task, but the open-tasks tier can. The
  empty caption therefore means *no open tasks at all*, not merely "nothing dated".
- **The task list is sized from the rows that exist, not from the cap.**
  `notchTaskRows` (3–5) is only a *bound*; `NotchWindowManager` counts the
  rows off the same `NotchTaskRows` call the panel renders from and stamps it
  into `NotchContentConfig.taskCount`, and the island follows
  `min(cap, count)` — so four tasks no longer sit in an island built for five.
  Zero tasks is not zero height: the panel draws its "No open tasks"
  caption, measured at 30pt (taller than one 28pt row, shorter than two), so the
  body is 170pt at an empty list against 288pt at five rows (island = that plus
  the menu-bar row). The island resizes
  live as tasks are ticked off (`NotchMotion.resize`, critically damped like every
  other spring on the frame). The *open* window stays pinned to the cap
  (`panelHeight`, like `panelSize`, reads `config.sizedForRowCap`): resizing the
  window under an island that is still springing would clip it, so the list
  churning never moves the window — only a state change does.
- **The panel's task rows say what the main window's rows say.** Each row carries
  the done box, the title, the subtask badge (`2/2`), the pomodoro ring and a
  play button that is a *pause* button when that task is the one the timer is
  running (`toggleRespectingTaskGuard()`; any other row starts a focus session on
  itself via `setActive` + `startFocusSession(kind: resolvedActiveKind)`). The
  badge and the ring are `SubtaskProgressBadge` / `TaskPomodoroBadge` in
  `TaskComponents.swift` — the *same* views the Tasks window and the menu-bar
  popover draw, not a copy (the ring came out of `TasksView.estimateRing`, and it
  still handles a task with no estimate the way it always did: a plain 🍅 count).
  There is no disclosure chevron: the island cannot expand subtasks inline.
  The row's height is **pinned** to `taskRowContentHeight` (22pt, the ring's
  diameter) + `taskRowPadding` × 2 = the 28pt `taskRowHeight` the geometry sizes
  the island from. Unpinned it would measure 21pt for a task with no badges and
  28 for one with them, and a list of bare tasks would sit 35pt short of the black
  reserved for it — the island is sized from the row *count*, which knows nothing
  about what any row carries.
- **`notchEars` changes the silhouette, not just the labels.** `.both` → cutout +
  2 ears, `.trailingOnly` → cutout + 1 (the island is anchored to the cutout's
  left edge, never centred), `.none` → the cutout alone with the progress line.
  `hitTest` masks against that same island path, so a dropped ear gives its
  menu-bar pixels back — clicks included. The panel still reserves an ear's width
  on both sides (it is centred on the cutout, and a one-eared island is not
  symmetric about it); the mask, not the panel's width, is what frees the menu
  bar.
- Settings changes reach the panel through the existing filter on
  `PomodoroTimer.objectWillChange` (`refreshIfSettingsChanged`), whose snapshot
  includes the whole `notchContent` — every switch resizes the island, and the
  panel's frame is cut from that size.

---

## Storage identifiers

- All on-disk identifiers are namespaced `com.sharingan.*` / `sharingan.*`
  (settings `com.sharingan.settings`, stats `com.sharingan.stats`, CLI
  snapshot `com.sharingan.cliSnapshot`, CLI darwin commands
  `com.sharingan.cli.*`, floating-timer/today-panel position keys, the focus
  queue, and the task pre-reminder-minutes setting). Task/template data lives
  in `~/Library/Application Support/Sharingan/` (SQLite db + the `tired` CLI's
  shared `cli/` snapshot files).
- **A headless render never touches that database.** `--render-dev-preview` and
  `--render-site-assets` seed sample tasks into `TaskStore.shared` to have
  something to photograph, and `TaskStore.shared` persists — so `HeadlessRender`
  (SharinganCore/Services) redirects the *shared* store to a throwaway SQLite
  under the temp dir whenever the process was launched with one of those flags.
  The seam is the process's own argv and nothing else — no environment variable,
  no preference, no UI — and `main.swift` parses the flag through the same call
  that redirects the store, so a process cannot redirect its database and then go
  on to run as the app. A normal launch passes no arguments and is unaffected.
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
