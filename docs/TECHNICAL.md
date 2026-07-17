# Sharingan (Blink) — Feature Reference

> Every feature of the app, described in plain terms. **Keep this up to date:
> whenever a feature is added, changed, or removed, update this document in the
> same change.**

- Version: 1.8.1
- Platform: macOS 14+, lives in the menu bar

---

## Timer / Pomodoro

- Configurable focus, short break, and long break durations (25 / 5 / 15 by default). Settings' "Pomodoro sizes" section renders as a compact grid (Small/Normal/Deep Work rows × Focus/Break/Long break columns); each size can override its own long-break length, falling back to the global long-break minutes when not overridden.
- Countdown and count-up modes.
- Long break automatically after every N pomodoros.
- Auto-start focus and auto-start break toggles.
- Repeat: run focus sessions back-to-back with a delay, or loop focus↔break endlessly.
- Natural-language time input: `5 min`, `2h 30m`, bare `25`, clock targets like `5pm`, deltas like `+5m` / `-1h`, and `reset` / `stop`.
- Screen flash warning in the last 5 seconds; a "5 minutes left" notification.
- Sleep-aware: closing the lid during focus doesn't wrongly credit hours; a break still completes when you wake the Mac.
- Custom one-off session length that survives mode changes.
- Skip kills the tick loop before transitioning (like pause/stop/complete) — a live in-flight tick used to overwrite the fresh phase's countdown with the skipped phase's leftover time.
- Main-window timer page: while idle, the ring hosts the Small/Normal/Deep Work size switch (accent-tinted active chip + the selected size's lengths caption) instead of the phase label; a live/paused/pending-break session shows the label. Chips call the same `applyKind` as the sidebar selector, so both stay in sync and an idle tap refreshes the countdown instantly.

---

## Tasks & planning

- Full task system: title, priority, tags, projects, categories, due dates, notes, and estimates.
- **Extensible priority levels.** The four built-ins (P1 Urgent … P4 No priority) ship by default, but the sidebar's Priority section has a "+" to add your own levels *above* P1 (each requires a name + flag color); a custom row's context menu deletes it, moving its tasks back to No priority. `TaskPriority` is an `Int`-backed struct (was an enum) that Codes as a bare `Int`, so old tasks.json / SQLite rows decode byte-for-byte unchanged. **Renumbering semantic:** chip labels are rank-based, not fixed — adding one custom level makes it "P1" and pushes the built-in Urgent to "P2", etc. Everything above P2 (medium) counts as *important* in the Eisenhower matrix, so custom levels are always important.
- Sidebar Tags section has a "+" to precreate a tag (name only, no color UI) before it's ever typed on a task; it shows dimmed with 0 uses until applied, and its own "Remove tag" (distinct from the destructive "Delete label" that strips a tag off every task) drops it again.
- Per-task pomodoro type (Small/Normal/Deep Work, or Auto to inherit the app default) — shown as a small icon+label badge in the task row's metadata line when set (nil/Auto shows nothing); subtasks can override it too, shown as an icon-only badge next to the subtask row.
- Subtasks with their own estimates **and their own priority flag** (set in the editor's per-step flag menu or imported via `p1`…`p4` tokens; shown as a colored rank chip on subtask rows) — reorder them, or promote a subtask into a full task (the step's own flag and pomodoro size carry onto the promoted task, falling back to the parent's priority). A task's displayed estimate (row badges, editor summary, menu-bar rows) is its own estimate when it has no subtasks, or the **sum of its subtasks' estimates** when it does (falling back to its own estimate if no subtask carries one); the stored per-task estimate is unchanged and still what the editor/composer/parser write.
- Recurrence: none, daily, weekdays, weekly, every N days, or monthly (on a chosen day). Completing a recurring task spawns the next occurrence.
- Natural-language quick add in the **world's 25 most-spoken languages** at once, e.g. `ertaga 15:00 p1 #ish @blink ~2 hisobot yozish` — with live parse chips while you type, in both the main composer and the menu-bar quick-add. Recognizes:
  - **Dates** — today / tomorrow / day-after-tomorrow / yesterday, weekday names, next week / next month / next year, this week, weekend, and month-name dates like `march 5` / `5 mart` (plus numeric `12.08`).
  - **Times** — clock (`15:00`, `5pm`) and parts of day (`morning`, `noon`, `afternoon`, `evening`, `tonight`, `midnight`), which combine with a day — "tomorrow evening" = tomorrow 18:00.
  - **Recurrence** — daily / weekly / monthly / weekdays / every N days.
  - **Relative offsets** — `in 2 hours`, `in 3 days`, `in 2 months`, plus postpositional forms (`2 soatdan keyin`, `2 saat sonra`, `2 घंटे में`).
  - **Priority words** — `urgent` / `muhim` → P1.
  Works across Latin, Cyrillic, Arabic, Indic, and space-less CJK scripts (Chinese/Japanese matched by substring). All languages are live simultaneously, so a line may mix them. Compositional offsets and month-name dates are fullest in the Latin/Cyrillic set; every language still accepts numeric dates.
- Smart views: Today, Upcoming, All, Completed — each with counts. Free-text search over title, tags, project, and notes.
- **Sort menu** (↑↓ in the view bar): Manual / Priority / Due date / A–Z / Newest, applied inside each category group (`TaskSortMode` in SharinganCore, threaded through `TaskStore.grouped(filter:search:sort:)`). Every mode keeps open tasks above done ones and tiebreaks with the manual order, so equal keys never shuffle; priority ranks most-urgent first (custom levels sit above P1), due date puts dateless tasks last, titles compare case-insensitively. Persisted across launches (`tasks.sortMode` default) and **shared by every sorted surface** — the Tasks list, the focus-task picker, and the weekly board follow one ordering (`TaskSortMenuItems` in TaskComponents supplies the menu entries everywhere). Drag-to-reorder and Move up/down keep editing the *manual* order underneath a non-manual sort; the Done view's day grouping and the Eisenhower matrix are unaffected.
- **Filter menu** (funnel in the view bar): narrow the list to one category, tag, or priority — the same narrowing dimension the sidebar deep-links set, so the pick shows the existing "Filtered by …" chip (its ✕ clears). One dimension at a time; picking the active entry again toggles it off. The same menu (`TaskFilterMenuItems` + `narrowTasks`) also lives in the focus-task picker (chip bar under the header, with a "No tasks match the filter" state) and the weekly board (circle button by the week nav — narrows cards across all columns, and the header’s planned-count follows).
- **Subtask sort & filter**: expanded step panels (main window and popover) carry a slim header — step progress plus two quiet menus. Sort steps by Priority / A–Z / Estimate (biggest first, unestimated last) or the manual drag order (`SubtaskSortMode.apply`, done steps always sink, manual position as the stable tiebreak); filter by status (All / Open / Done) or one priority level (`[Subtask].narrowed(status:priority:)`). The step ordering is one shared preference (`tasks.subtaskSortMode`) that the focus picker's step rows follow too; the task editor has the same filter but deliberately **no sort** — it is where the manual order is edited (drag to reorder).
- **Report sort & filter** (circles in the day pager, main window and popover Report tab): order rows by Focus time (the canonical most-focus-first), Pomodoros, or A–Z (`ReportSortMode`, time order as tiebreak; persisted as `report.sortMode`), and narrow to one category — deleted-task rows carry no category so any pick hides them, and the Total footer then sums exactly the rows on screen.
- Snooze a task to tomorrow, next week, or a picked date; overdue badges.
- Due reminders with a configurable pre-reminder (default 10 minutes before, or off).
- Templates: save any task as a reusable template and instantiate it later. Duplicate tasks too.
- **Bulk import (Markdown + JSON)** — paste a document into Tasks → import (the ↓ button in the view bar, or the link in the empty state), drop a `.md`/`.json`/`.txt` file on the task list, or paste it straight into **any add-a-task field** (main composer, menu-bar quick add, quick-add hotkey window, weekly-board backlog, task picker): `TaskStore.importIfDocument` routes multi-line / fenced / JSON submissions through the importer and single lines fall through to the normal quick add (in the task picker, focus starts on the first imported task). **Duplicate guard:** a document import never silently duplicates — incoming tasks whose normalized (trimmed, case-folded) title matches an *open* task, or an earlier task in the same batch, are held back and an "N tasks already exist — Skip Duplicates / Add Anyway" prompt decides (`TaskStore.partitionByDuplicateTitle` + `ImportDuplicatePrompt`); completed tasks don't block a title from coming back, and the headless `sharingan://`/CLI path skips duplicates silently. The import sheet's live counter appends "· N already exist". Format auto-detected (`{`/`[` ⇒ JSON) after stripping a UTF-8 BOM and one surrounding ```` ```lang ```` code-fence pair, so LLM answers paste as-is; `TaskImportParser` (SharinganCore) is pure and unit-tested. Copyable templates for both flavors live in Settings → Tasks & Planning → "Import template" (`TaskImportParser.markdownTemplate/.jsonTemplate`).
  - **Markdown**: every `#`/`##` heading starts a task; the heading line goes through `TaskInputParser`, so quick-add tokens (`p1 #tag @proj ~4 ertaga 15:00`) work in all 25 languages. Under a heading: `key: value` lines refine the task (keys case-insensitive, English + Uzbek aliases — category/kategoriya, project/proyekt/loyiha, tags/teglar, priority/muhimlik, due/muddat, planned/reja, estimate/baho, repeat/takror, pomodoro, notes/eslatma, done); `- [ ] Step ~2 (big) p1` lines are subtasks (`~N` = step estimate, `(small|normal|big)` = step pomodoro size, exact `p1`…`p4` tokens = step priority — bare words like "high" stay in the title); any other text becomes notes. Date values accept `YYYY-MM-DD [HH:mm]`, ISO-8601, or any natural-language phrase the quick-add parser knows. A document with **no headings** imports as a flat checklist — top-level `- …` lines are tasks, indented ones their subtasks; no bullets at all ⇒ one task per non-empty line.
  - **JSON**: an array of task objects (single object and `{"tasks": [...]}` also parse), decoded leniently via `JSONSerialization` — `tags` may be an array or comma string, `priority` accepts "P1"…"P4"/high/medium/low/none or an int P-number, `subtasks` entries are strings or `{title, estimate, done, pomodoro, priority}`. Pasted-JSON damage is tolerated: smart/curly quotes (Notes/TextEdit) and trailing commas (LLM output) are normalized on a retry that runs only when the strict parse fails, so valid documents are never rewritten.
- Completed history grouped by day, with restore.
- CSV export.
- **Focus queue**: line up several tasks — each finished pomodoro advances to the next one, the break screen shows "Next: …", and after a break a picker asks what to work on next.
- **Eisenhower matrix** view: tasks sorted into do-first / schedule / delegate / eliminate by urgency and importance.
- **Weekly board**: drag tasks between days to reschedule; sort & filter controls in the header order every column and narrow the whole board. The menu-bar popover’s Week tab carries the same two controls.
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

## Analytics

- **Per-session focus log** (`SessionRecord` + `FocusSessionLog`, SharinganCore): every really-ended session — completed, or skipped/stopped after ≥1 minute (`PomodoroTimer.shouldLogAbandoned`) — is appended as `{start, end, phase, completed, taskID/subtaskID/title snapshot, plannedSeconds, appUsage}` to `focus-sessions.json` in Application Support (400-day retention). The timer posts `.sessionDidEnd` (task-less record) from its complete/skip/stop paths; the coordinator attaches the active task and appends. Session start survives pause/resume; mirrored sessions never post (the owner Mac logs them). Writes are fire-and-forget on a background queue (never block the timer); a corrupt file is renamed `focus-sessions.corrupt.json` and the log restarts empty. `appUsage` is reserved for active-app tracking (phase 2).
- **Analytics page** (sidebar `AppSection.analytics`, gauge icon) with pill tabs:
  - **Overview** — two ring gauges. **Focus Score** (0–100, `AnalyticsEngine.focusScore`): focus volume vs the daily pomodoro goal (fallback 8) 40%, completed/abandoned ratio 25%, break compliance 20%, deep blocks (longest run of consecutive completed pomodoros, 4 caps it) 15%. **Consistency Score** (`consistencyScore`): today's-plan completion ratio 40% (Today-view members incl. those completed today; no plan ⇒ neutral 0.7), start-hour regularity vs the median first-start of up to 14 prior logged days 30% (full within ±1 h, zero at ±4 h; <3 prior days ⇒ neutral), streak 30% (7 days caps). Empty day ⇒ "—" (nil), never zero.
  - **Heatmap** — GitHub-style 52-week grid from `PomodoroStats.recentDays(364)` (so it's full for long-time users regardless of the new log), Monday-first columns via the pure `AnalyticsEngine.heatmapWeeks` mapper, 5-step accent intensity scaled to the year's peak day, hover shows "N 🍅 · date", Less→More legend.
  - **Focus load** — Swift Charts area chart of focus minutes per hour of day (`AnalyticsEngine.hourlyLoad`, sessions split proportionally across hour boundaries; breaks excluded), with a dashed 30-day-average line (averaged over days that have data) and a ◀ ▶ day pager clamped at today.
- **Filter bar** (`AnalyticsFilter`, SharinganCore): a time **range** (Today/1W/1M/3M/1Y) averages the Overview scores over the window via per-day computation (`AnalyticsEngine.average` over daily scores; past-day plan adherence is unknown ⇒ neutral default, streak reconstructed from the log's completed-focus days); one **attribution dimension** (category/project/tag, resolved to a `Set<UUID>` of matching task IDs by the view and applied via `AnalyticsEngine.filter`) with a "Filtered by …" chip; and a **completed-only** toggle. While a filter narrows sessions the heatmap can't use the aggregate history, so it recomputes from `AnalyticsEngine.dailyCounts(from:)`. Deleted tasks aren't in the live list, so their sessions drop from an attribution filter (same as the Report tab).
- All score/grid/load/filter math is pure and unit-tested (`AnalyticsEngineTests`, `SessionLogTests`).

---

## Stats, streaks & rewards

- Daily focus history with today's count and a best-focus-hour breakdown.
- Weekly and monthly aggregations: week-over-week change, best day, best weekday, average per active day.
- 7-day and 30-day charts.
- Consecutive-day streak tracking that resets on a missed day.
- Milestone badges at 1, 7, 14, 30, 90, and 365 days, with a spring-animated reward banner when a new one is unlocked.
- Pomodoro breakdown by project and by tag.
- **Per-task daily focus log.** Every completed focus session is attributed to
  its task — and, when one was targeted, its subtask — as a per-day row
  (pomodoro count + the session's real seconds, `focus_log` table). The task
  row is the aggregate and already includes subtask credits; consumers never
  sum the two. Titles are snapshotted so history survives deletion; no
  backfill before the feature shipped. Surfaced in the main window's
  **Report** section (day pager, expandable subtask rows, day totals), a
  "By task — today" Progress card, and a 14-day history block in the task
  editor. `--render-dev-preview` seeds credits through `incrementPomodoro`
  (the timer's own writer) and shoots all three surfaces:
  `report{,-empty}.png`, `stats-extras.png`, and `editor.png` — the editor
  hosted in a real window, since `ImageRenderer` photographs its `ScrollView`
  as an empty rectangle.
- A configurable daily pomodoro goal with progress and a "goal reached" notification.

---

## Themes & interface

- Six themes: Liquid Glass, Frosted, Midnight, Cream, Neon, and Mono.
- Liquid-glass design throughout.
- Main window sections: Pomodoro, Tasks, Week, Progress, Report, and Settings.
- **Main menu bar** (`MainMenu.swift`, visible while the main window holds the app in `.regular`): App menu (About, Settings… ⌘, → `AppRouter.openSettings`, Quit ⌘Q); File — New Task… ⌘N (the quick-add panel), Import Tasks… ⇧⌘I (opens Tasks with the bulk-import sheet via the one-shot `AppRouter.openTaskImport`), Export Tasks as CSV…, Close ⌘W; Edit — the standard first-responder six; View — the five sections on ⌘1–⌘5 plus Search Tasks ⌘F; Timer — Start/Pause Focus ⌘⏎, Skip Phase ⇧⌘⏎, Add/Remove 5 Minutes ⌘+/⌘−; Window — Minimize/Zoom + the system windows list (`NSApp.windowsMenu`); Help — website and releases (`NSApp.helpMenu`). Actions dispatch through the same singletons the in-app buttons use; delegate-targeted items set `target:` explicitly since the app delegate is outside the responder chain.
- Menu-bar popover with timer, tasks, week, and report tabs plus today's
  goal — the report tab is the main window's day-paged `ReportView` reused
  unchanged, scrolling inside the popover's fixed tab area (560 pt). The
  Pomodoro tab is plan-first: no phase + countdown header (the menu bar
  and the Floating widget already show the time) — the goal bar and
  task list take that space (list cap 360 pt), with the transport controls
  pinned below the scroll. The
  popover pins its own `NSAppearance` to dark: `NSApp.appearance` does not reach
  it because an `NSPopover` resolves appearance from its anchor view (the
  status-item button in the system menu bar), so under Light mode the dark-glass
  content used to render white-on-light.
- **Since 1.6.1**: the tab bar (Pomodoro/Tasks/Week/Report) is a custom
  liquid-glass control (`MenuBarView.liquidGlassTabBar`) — a translucent
  capsule track with a `matchedGeometryEffect` pill that glides to the
  selected tab, filled with the same `[accent, accent.opacity(0.82)]`
  gradient as the Start button — replacing the flat `.segmented` Picker.
  The tab bar and the Today/Cycle/Streak stats strip are capped to 640 pt
  and centered so the wider Week-tab popover doesn't stretch them
  edge-to-edge. The standard (non-Week) popover width grew from 360 to
  460 pt — task rows plus the composer's filter chips needed more room
  and were clipping on both edges at 360. `GlassButton`'s non-prominent
  style (Skip/Reset/+5m/-5m/Exit break) now tints with the theme accent
  instead of neutral glass, matching Start's capsule language.
  `MenuBarController` orders the main window out while the popover is
  showing and restores it on close (`MainWindowManager.hideTemporarily`/
  `restore`) — with both open at once, the popover's translucent
  materials sampled the main window behind it, bleeding its sidebar color
  through the tab bar and stats text.
- Popover task rows degrade whole, never squash: the title (layout-priority 1,
  one line) wins width first; step + pomodoro progress badges are `fixedSize`
  and never drop; the decorations sit in one `ViewThatFits` ladder of
  `fixedSize` tiers (category + tags + due + state icons → due + icons →
  icons → nothing), so each tier renders complete or yields to the next.
  Without the ladder, SwiftUI compressed chips in place — empty capsule
  slivers and count labels wrapped onto two overlapping lines (the
  metadata-maxed seed row in `--render-dev-preview`'s `menubar.png` is where
  this is checked).
- Menu-bar icon visibility is self-healing (`MenuBarController`): the item is
  created by `makeStatusItem()` (autosave `sharingan.menubar`), and the
  "Show menu bar icon" setting (`showMenuBarIcon`, Settings → Pomodoro →
  Menu bar) is applied by `syncVisibility()` on the 1 s tick — turning it on
  clears a stale `NSStatusItem Visible … = false` that macOS persists when
  the icon is ⌘-dragged off the bar. `rescueFromNotchIfHidden()` (2 s after
  install, and 1 s after the setting turns the icon back on) detects the
  button's window overlapping a notched screen's camera housing (between
  `auxiliaryTopLeftArea`/`auxiliaryTopRightArea`) — the invisible slot a
  crowded menu bar parks new items in — then seeds
  `NSStatusItem Preferred Position sharingan.menubar = 6` (points from the
  right edge) and rebuilds the item, which macOS re-reads at creation. The
  rebrand's defaults migration cannot heal Macs that launched a renamed
  build before it existed (the new key already holds the bad slot), hence
  the runtime rescue.
- Text fields submit through a single `.onSubmit` — the legacy
  `TextField(onCommit:)` initializer is banned (`SubmitWiringTests` lints for
  it). On macOS `onCommit` fires on Return *and again* on end-editing with the
  field editor's stale text re-synced into the binding, which double-added
  every quick-add task; some fields even had the same handler wired through
  both `onCommit:` and `.onSubmit`.
- The menu-bar and Dock marks follow `settings.sharinganStyle` (Settings →
  Sharingan): `.classic` keeps the launch-safe hand-drawn CG mark;
  every other style rasterizes `MoveIrisView` (the same view the eyes,
  wallpaper and `AppIconArtwork` use) via `ImageRenderer` and composites it
  inside the CG progress ring (`MenuBarController.menuBarIcon(style:)`,
  scale 8 at 18 pt). A styled render during `applicationDidFinishLaunching`
  can come out empty (long-standing ImageRenderer quirk), so `install`
  forces one settled re-render 2 s in; a nil render falls back to the CG
  classic mark. The Dock side is `DockIconAnimator.syncStyle` — styled
  512 px re-render of `AppIconArtwork`, shipped .icns for classic (Finder
  always keeps the classic mark), synced from `updateTitle`'s 1 s tick. The
  spin quantisation is 120° only for the classic mark's 3-fold symmetry —
  other styles quantise per full turn.
- Spinning Sharingan icon: the menu-bar tomoe and (while the main window is
  open) the Dock icon rotate slowly — one `IconSpinner` clock (12 fps, 60°/s
  clockwise; the mark's 3-fold symmetry makes the visible cycle 2 s) drives
  both so they stay in phase. `menuBarIcon(rotationDegrees:)` spins only the
  tomoe (the progress ring keeps its 12-o'clock anchor); `DockIconAnimator`
  redraws the bundled icon bitmap rotated into `NSApp.applicationIconImage`
  only under the `.regular` activation policy and restores the shipped
  artwork when the tile disappears or the spinner idles. Controlled by
  `settings.animateIcon` (Settings → General → Appearance → "Spin the
  Sharingan", default on); the spinner also idles under macOS Reduce Motion
  and while screens sleep. Preview frames:
  `--render-menubar-icon <path> [rotationDegrees]`.
- Notch HUD: an island over the MacBook camera housing — live ears while a session runs, the user's open tasks and quick actions on hover. Configurable (see below); absent, and disabled in Settings, on a Mac without a notch.
- Confirmation prompt before quitting while a focus session is running.
- Searchable settings, grouped into: Pomodoro, Tasks & Planning, Breaks, Focus & Blocking, Eye Care, Sharingan Eyes, General, Voice Guidance, and Shortcuts.

---

## Settings layout (essentials + Advanced accordion)

All 10 categories are always visible on the root list (General first,
Notch HUD right after Pomodoro — `SettingsCategory` declaration order). Each category page shows its
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
  Small/Normal/Deep Work grid) — there's no simplified two-stepper substitute. The
  "Floating widget" section (master toggle, then size / position / expand-on-
  hover / opacity once it's on, gated on `settings.dockWidgetEnabled`) is
  also essentials-tier — it isn't behind the Advanced accordion. Eye Care's
  Advanced "Camera" section is gated on `settings.cameraEyeTrackingEnabled`
  the same way.
- The Sharingan "Desktop wallpaper" section (and its `.onChange` chain that
  re-applies `WallpaperConfig`) stays in `categorySections` — always
  visible — so it keeps observing even while the Advanced accordion
  (which holds the wallpaper spin/idle/doze rows) is collapsed.
- The **Notch HUD** is its own category (declared right after Pomodoro, so it
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
- **A row's title opens the task in the app.** Clicking the title (the done box
  and play button keep their jobs either side of it) calls
  `MainWindowManager.show()` + `AppRouter.revealTask(id)`: a one-shot
  `pendingRevealTaskID` deep-link that lands the main window on the Tasks
  section, clears whatever would hide the row (search, sidebar narrowing, the
  Eisenhower matrix — and picks the Done view for a completed task), scrolls it
  to centre (`ScrollViewReader`, ids on both the category and Done rows) and
  flashes it with the category accent for ~2s. Photographed end-to-end by the
  dev-preview `main-reveal.png` shot: the revealed row is seeded behind fourteen
  backlog rows, so the row being in frame is the scroll having worked.
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

## Floating widget

A "now playing"-style pill — active task, remaining time, and
always-standing ▶︎ Start / ⏸ Stop / ⟲ Reset buttons — that docks flush
against the Dock's inner edge by default and can be dragged anywhere on
screen. It is the app's **one** timer window: an earlier "floating timer"
card existed alongside it, but that card was deleted outright and this
widget absorbed every one of its jobs (transport controls, size presets,
opacity, drag-anywhere placement). Same philosophy as the today panel: it
shows the controls, not a status light, so a session can be started without
opening the app. Settings adds four appearance knobs — preset size, which
end of the Dock it hugs while docked, opacity, and an "expand on hover"
dynamic mode.

- **Naming.** The feature is user-facing "Floating widget" (Settings
  section, shortcut label, category subtitle) and its Swift types follow:
  `FloatingWidgetView`/`FloatingWidgetTaskPickerView`
  (Sources/Sharingan/Views), `FloatingWidgetWindowManager`
  (Sources/Sharingan/Services), `FloatingWidgetController` (protocol,
  SharinganCore/Services/SharinganCoordinator.swift),
  `FloatingWidgetGeometry`/`FloatingWidgetStartAction`
  (SharinganCore/Models). `PomodoroSettings`' five stored properties
  (`dockWidgetEnabled`/`dockWidgetSize`/`dockWidgetAlignment`/
  `dockWidgetOpacity`/`dockWidgetExpandOnHover`) and the
  `sharingan.dockwidget.x`/`.y` UserDefaults position keys deliberately KEEP
  their historical `dockWidget`/`dockwidget` prefix, so existing settings
  JSON blobs and dragged-in positions decode unchanged across the rename —
  only the types and user-facing copy moved to "Floating widget".
- **The square-tile limitation and the flush-panel trick.** The Dock itself
  cannot be widened or grow a custom tile — every Dock icon is a fixed square
  slot the system owns. The widget is therefore not a Dock tile at all: it is
  an ordinary borderless `NSPanel` (`FloatingWidgetWindowManager`) positioned
  immediately above the Dock's own rectangle, by default, so it *reads* as
  part of it without the Dock ever knowing it exists.
- **Three code units.** `FloatingWidgetWindowManager`
  (Sources/Sharingan/Services) owns the panel's lifecycle and placement;
  `FloatingWidgetView` (Sources/Sharingan/Views) is the SwiftUI pill itself —
  a mini progress ring, the active task title (or "No task selected"), the
  remaining time, a pomodoro dot row, and the three transport buttons, which
  disable rather than hide so the pill never changes shape under the pointer.
  The dot row's count is decided by `FloatingWidgetPomodoroDots`
  (SharinganCore/Models), a pure unit-tested helper: the active task's
  `effectiveEstimate` wins (filled by its `pomodorosDone`), else the user's
  finite Repeat ×N selection (filled by `repeatIndex`), else 3 dots (filled
  by `cyclesCompletedInRound`); totals clamp to 1…8 (`maxDots`) so a huge
  estimate can't stretch the pill.
  `FloatingWidgetController` (protocol,
  SharinganCore/Services/SharinganCoordinator.swift) is the seam
  `SharinganCoordinator` calls through (`showFloatingWidget(timer:)` /
  `hideFloatingWidget()`), same pattern as `TodayPanelController` —
  `AppDelegate` wires
  `coord.floatingWidgetController = FloatingWidgetWindowManager.shared`, and
  tests swap in a spy instead of touching AppKit.
- **`dockWidgetEnabled` is a settings-flag-only switch, on by default.**
  `PomodoroSettings.dockWidgetEnabled` (default `true`) is read by
  `SharinganCoordinator.syncFloatingWidget()` alone — like the today panel,
  the pill's visibility follows the flag, never `timer.isRunning`, so Start
  stays reachable even when nothing is counting down. `syncFloatingWidget()`
  runs once from `syncAll()` at launch and again from `syncChanged(_:)`
  whenever `dockWidgetEnabled`, `dockWidgetSize`, `dockWidgetAlignment`,
  `dockWidgetOpacity`, or `dockWidgetExpandOnHover` changes; the Settings
  toggle and its controls sit in their own "Floating widget" section.
- **Four appearance fields on `PomodoroSettings`, decoded defensively.**
  `dockWidgetSize: FloatingWidgetSize` (`.small`/`.medium`/`.large`, default
  `.medium`; width/height 280×48, 320×56, 380×68) and
  `dockWidgetAlignment: FloatingWidgetAlignment`
  (`.leading`/`.center`/`.trailing`, default `.trailing`) decode with the
  same double-optional idiom as `notchEars` — an unknown raw value (an older
  or newer build's blob) falls back to the default instead of throwing the
  whole settings object away. `dockWidgetOpacity: Double` (0.3…1.0, default
  `1.0`) and `dockWidgetExpandOnHover: Bool` (default `true`) decode with
  plain `decodeIfPresent ?? default`.
- **Docked placement is `visibleFrame` vs. `frame` math, extracted into a
  pure, unit-testable model** — `FloatingWidgetGeometry`
  (SharinganCore/Models), the same precedent as `NotchGeometry`.
  `NSScreen.main`'s `frame` is the full display; `visibleFrame` excludes the
  Dock (and the menu bar). `FloatingWidgetGeometry.side(visibleFrame:fullFrame:)`
  compares the two on each edge (`visibleFrame.minX > frame.minX` → `.left`,
  `visibleFrame.maxX < frame.maxX` → `.right`, else `.bottom`, returned as
  the top-level `DockSide` type — it names the real Dock's edge, not the
  widget) to tell `FloatingWidgetWindowManager.reposition()` where the Dock
  actually is, and
  `FloatingWidgetGeometry.origin(size:alignment:visibleFrame:fullFrame:)`
  turns that into a window origin. The window is always sized to the FULL
  preset (`dockWidgetSize.width/height`) regardless of the hover state — only
  the pill drawn inside it resizes — so `reposition()` never has to reconcile
  a resizing window with its anchor:
  - Dock on the bottom (the common case): the x position follows
    `dockWidgetAlignment` — `.leading` → `visibleFrame.minX + 16`, `.center`
    → `visibleFrame.midX − width / 2`, `.trailing` (default) →
    `visibleFrame.maxX − width − 16`. Either way the pill sits at
    `visibleFrame.minY + 4`.
  - Dock on the left (`visibleFrame.minX > frame.minX`): pill sits flush
    beside the Dock's inner edge, **vertically centered** —
    `visibleFrame.minX + 8, visibleFrame.midY − height / 2` — instead of
    wedged into the bottom-left corner (the bug this replaced). The Position
    setting is a horizontal-Dock concept, so a vertical Dock always centers
    regardless of what it says — the simplest deliberate look.
  - Dock on the right (`visibleFrame.maxX < frame.maxX`): mirrored —
    `visibleFrame.maxX − width − 8, visibleFrame.midY − height / 2`.
  - **Auto-hide** falls out of the same comparison for free: when the Dock is
    set to auto-hide, `visibleFrame` and `frame` (nearly) coincide since macOS
    stops reserving Dock space, so `side()` reads `.bottom` and the pill's
    computed origin lands at the screen edge instead of hovering over empty
    space where the Dock used to be — no separate auto-hide detection needed.
  - `reposition()` re-runs on `NSApplication.didChangeScreenParametersNotification`,
    so moving the Dock, resizing a display, or toggling auto-hide re-anchors
    a docked pill live. `FloatingWidgetWindowManager` keeps a `weak var timer`
    (set in `showFloatingWidget`) and a `NSHostingView<FloatingWidgetView>`
    reference (`hosting`, nilled in `hideFloatingWidget()`) so `reposition()`
    and `applySettings()` always read the live settings rather than a
    snapshot from when the panel was created, and can push a fresh `anchor`
    into the hosted view without recreating the panel.
  - `showFloatingWidget(timer:)` on an already-showing panel live-applies
    settings instead of a no-op: `applySettings()` (resizes to the current
    preset, reclamps opacity) then `reposition()` — so flipping size,
    position, or opacity in Settings updates the on-screen pill immediately.
  - Opacity clamps to `0.3…1.0`:
    `panel.alphaValue = CGFloat(min(max(opacity, 0.3), 1.0))`.
  - `hasShadow = false` (the pill draws its own material; an OS shadow would
    frame the transparent window in a visible rectangle), and
    `canBecomeKey`/`canBecomeMain` both `false` (`FloatingWidgetPanel`) so
    clicking its buttons never steals focus from whatever app is in front.
- **Draggable pill + "Return to Dock".** The panel is `isMovable = true` /
  `isMovableByWindowBackground = true` (borderless panels only drag from
  their body with the latter set), so dragging it anywhere sets a CUSTOM
  position. `FloatingWidgetWindowManager` registers an
  `NSWindow.didMoveNotification` observer on the panel — AFTER
  `WindowAnimator.present(panel:)`, so the initial placement and its
  0.97→1 settle animation aren't mistaken for a drag — that persists the
  panel's origin to `UserDefaults` (`sharingan.dockwidget.x`/`.y`, plain
  `Double`s, checked for presence via `object(forKey:) != nil` since `0` is a
  valid dragged-to coordinate) whenever the panel moves. Every
  *programmatic* `setFrame` (dock-anchored placement in `reposition()`,
  settings-driven resize in `applySettings()`) brackets itself with a private
  `isRepositioning` flag the move observer checks first; it also requires
  `NSEvent.pressedMouseButtons & 1 != 0` (the left button physically down) —
  a settle-animation or other programmatic move that forgot to bracket
  itself with `isRepositioning` still fires `didMoveNotification` with no
  button held, so the button check is a second, independent guard against
  mistaking it for a drag — so only real user drags get persisted. The same
  guarded branch immediately re-derives the hover-expand anchor (below) from
  the just-moved origin and pushes a fresh `hosting?.rootView` (no
  `setFrame`), so a pill dragged across the screen midline flips its expand
  direction mid-drag instead of waiting for the next `reposition()`. With a
  custom position stored: `reposition()` skips dock-anchored placement
  entirely and instead reads the stored origin, clamps it into the current
  `visibleFrame` with `FloatingWidgetGeometry.clamp(origin:size:visibleFrame:)`
  (keeps a dragged-off-screen pill on screen after a display change — same
  min/max-per-axis idiom as `FloatingWidgetWindowManager`), and picks a hover-expand
  anchor with `FloatingWidgetGeometry.expandAnchor(customOrigin:size:visibleFrame:)`:
  whichever half of the screen the pill's midX falls in — left half →
  `.leading` (expands rightward), right half → `.trailing` — since there's no
  Dock edge to hug once the pill is off on its own. The pill's context menu
  gains a **"Return to Dock"** item (`FloatingWidgetWindowManager.returnToDock()`)
  that removes both `UserDefaults` keys and calls `reposition()`, snapping it
  straight back to the Dock-anchored placement above; while docked (no custom
  position saved) the menu item is a harmless no-op re-deriving the same spot.
- **Start → mini task picker.** ▶︎ no longer always starts immediately.
  `FloatingWidgetView.handleStart()` asks
  `FloatingWidgetStartAction.decide(isPaused:todayTaskCount:)` (SharinganCore,
  pure and unit-tested) what to do: a **paused** session always resumes in
  place (`.startImmediately`, `timer.startFocusSession()`) — never re-routed
  through task selection — and an **idle** session with today's open-task
  list empty also starts immediately, since a picker with nothing to choose
  from is just a dialog in the way. Only when idle AND today has open tasks
  does it show `.showPicker`, which pops `FloatingWidgetTaskPickerView` as a
  `.popover` anchored off the ▶︎ button. The picker lists the exact same set
  `TodayPanelView` shows (`TaskStore.grouped(filter: .today)` — planned
  today OR due today OR overdue, always open — so "today" never drifts
  between the two surfaces), each row a category dot + title + optional
  🍅-done count, active task highlighted, capped at 8 rows with a "+N more"
  footer. A top "Start without task" row calls plain `startFocusSession()`
  with the active task left untouched. Choosing a task row activates it
  (`TaskStore.setActive(id)`) then starts with its resolved pomodoro size
  (`timer.startFocusSession(kind: tasks.resolvedActiveKind)`) — the same
  entry point every task-row play button uses. The popover may take key
  focus while open (a deliberate exception); the widget panel itself stays
  non-activating, and Esc / click-away dismisses it without starting
  anything — Start is never blocked by the picker.
- **Hover-expand ("dynamic") pill.** `FloatingWidgetView` scales every metric
  (ring, stroke width, timer/title font sizes, dot, button circle, icon,
  padding, spacing) by `k = dockWidgetSize.height / 56`, so the whole layout
  is a linear scale off the medium preset rather than three hand-tuned
  layouts. The view sits inside a full-preset-size transparent container,
  `.frame(width:height:alignment:)`-anchored per its `anchor` parameter
  (`.leading`/`.center`/`.trailing`, default `.trailing`) — the edge
  `FloatingWidgetWindowManager` computes (Dock-nearest edge while docked via
  `FloatingWidgetGeometry.expandAnchor(alignment:...)`, screen-half while
  custom-positioned via `expandAnchor(customOrigin:...)`), not the raw
  `dockWidgetAlignment` setting; the pill itself carries the `.onHover` (not
  the container), so empty container space neither expands the pill nor
  swallows clicks. When `dockWidgetExpandOnHover` is on, the pill rests
  compact — progress ring + remaining time only, width `height * 2.6` — and
  springs to the full task-title-and-transport-buttons layout
  (`.spring(response: 0.32, dampingFraction: 0.78)`, width only — height
  stays pinned to the preset so the pill never bobs) while the pointer is
  over it; off, the pill is always fully open. `accessibilityReduceMotion`
  suppresses the spring — the pill flips instantly.

---

## Desktop widget (WidgetKit)

- A real system widget (widget gallery / desktop / Notification Center),
  small + medium families: progress ring and remaining time in the phase
  color, phase label, and today's 🍅 count; medium adds the active task
  title, `n / goal`, 🔥 streak, and ▶︎ ⏸ ⟲ transport glyphs.
- **No AppIntents** (pure-SwiftPM appex — same constraint as the CLI): the
  widget is display + deep links. Small opens the app (`sharingan://show`);
  the medium transport glyphs hit `sharingan://start|pause|reset` through the
  existing `URLCommandRouter`.
- **Process split**: the widget can't observe `PomodoroTimer`.
  `WidgetSnapshotPublisher` (app side, wired in `AppDelegate`) debounces
  timer/task changes, fingerprints them (end date bucketed to 5 s so per-second
  ticks don't spam chronod), writes a `WidgetSnapshot` JSON, and pokes
  `WidgetCenter`. A running session needs **no** rewrites: seconds tick via
  `Text(timerInterval:)`, the ring re-fills from one timeline entry per
  minute. `applicationWillTerminate` parks the widget in the idle state so a
  quit app never leaves a counting widget behind.
- **Snapshot location — the widget's own container, NOT the app group**
  (diagnosed live 2026-07-14): containermanagerd on macOS 26 REJECTS a
  team-ID-less (ad-hoc) signature's claim to a TCC-protected group container
  ("group container identifiers should be prefixed by requestor's team ID"),
  so the sandboxed appex can never read `group.com.sharingan.app` under this
  repo's signing. `WidgetSnapshotStore` therefore targets
  `~/Library/Containers/com.sharingan.app.widget/Data/Library/Application
  Support/widget-snapshot.json` — the appex reaches it home-relative, the
  unsandboxed app writes the explicit path, but only once the container has
  been materialized by a first widget launch (never fabricate directories
  containermanagerd owns; `containerFileURL(home:directoryExists:)` is pure
  and unit-tested). Writes go to the container **and** the group (a real
  team-ID build keeps working); reads try container → group. A widget placed
  while the app idles seeds via `WidgetSnapshotStore.needsSeed` + the
  publisher's 30 s tick, bypassing the fingerprint once.
- **Appex entry point is `_NSExtensionMain`** (the `-Xlinker -e` flag in
  `make-app.sh`, matching what Xcode links appex targets with): the extension
  runtime must own the process from the first instruction — launchd check-in,
  XPC listener — before widget code runs. Entering through Swift `@main`
  instead let the process boot to WidgetKit's "Extension Type:" log line and
  then `exit(0)`, chronod logged `query failed … connection invalidated`, the
  extension stayed in `extensionsPendingDescriptorRefetch` (in the
  `com.apple.chronod` defaults) forever, and the widget never reached the
  gallery. `@main` stays: swiftc still emits the `WidgetBundle` metadata that
  WidgetKit's host locates at runtime. Direct-run smoke signature changed
  accordingly: healthy is now `An XPC Service cannot be run directly.`
  (SIGABRT), no longer the old `Unrecognized extension type` fatal.
- **Reading-side repair** (`WidgetSnapshot.normalized`, unit-tested): a
  "running" snapshot whose end date passed (app force-killed) renders idle; a
  snapshot written on a previous day shows 0 today; corrupt/missing/newer-schema
  files fall back to a placeholder.
- **Model/store live in SharinganCore** (`Models/WidgetSnapshot.swift`,
  `Services/WidgetSnapshotStore.swift`); the appex compiles those two files
  plus `Sources/SharinganWidget/*` directly — the widget target is deliberately
  **outside Package.swift** (see Packaging below), so `swift build`/`swift run`
  are untouched by it.

- All on-disk identifiers are namespaced `com.sharingan.*` / `sharingan.*`
  (settings `com.sharingan.settings`, stats `com.sharingan.stats`, CLI
  snapshot `com.sharingan.cliSnapshot`, CLI darwin commands
  `com.sharingan.cli.*`, Floating widget/today-panel position keys, the focus
  queue, and the task pre-reminder-minutes setting). Task/template data lives
  in `~/Library/Application Support/Sharingan/` (SQLite db + the `tired` CLI's
  shared `cli/` snapshot files). Since 1.13.0 the bundle identifier itself is
  `com.sharingan.app` (widget appex `com.sharingan.app.widget`, app group
  `group.com.sharingan.app`) — renaming it moved the `UserDefaults` domain,
  handled by the migration below.
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
  first time the new location is still empty. The 1.13.0 bundle-id rename
  (`com.blink.app` → `com.sharingan.app`) added `migrateDomain`: everything
  persisted under the old `com.blink.app` defaults domain is copied into the
  new domain (existing new-domain values win; app process only — the CLI and
  tests are excluded by a bundle-id guard), EXCEPT `NSStatusItem …` keys.
  Those carried a stale mid-bar menu-bar slot that macOS 26's menu-bar item
  hiding collapsed behind the chevron — the slot is instead re-seeded at the
  far right next to the system icons (6 pt from the right edge, the same spot
  `rescueFromNotchIfHidden` uses). The rename also resets TCC identity:
  notification/camera permissions are asked once more, and a Launch-at-login
  registration re-registers under the new id. Stored `dndShortcutOn/Off`
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

- **App blocking**: hide or force-quit distracting apps (presets include Chrome, Safari, VS Code, Slack, Telegram, Messages) — during breaks, during focus, or always. The "Add apps…" picker (`BlockAppPickerSheet` + `InstalledAppsCatalog`, Settings → Focus) lists every installed app — /Applications top level + one folder deep, /System/Applications, ~/Applications, plus running `.regular` apps — deduped by bundle id with icons and search; Block adds an enabled `BlockedApp`, tapping again removes it. Names come from `CFBundleDisplayName`/`CFBundleName` (the filename fallback strips ".app"). The dev-preview shot `block-app-picker.png` checks the layout (its rows vary per machine).
- **Do Not Disturb**: toggles a macOS Focus mode automatically at the start and end of sessions.
- **Global keyboard shortcuts** (rebindable): start/pause, skip, reset, +5 minutes, toggle Floating widget, and quick-add task.
- **`tired` CLI** — control the app from Terminal: start (with natural-language input), pause, resume, skip, reset, add/remove/set time, check live status, and manage tasks (add, list, mark done, start, queue).
- **`sharingan://` URL scheme** for Shortcuts / Raycast: start, pause, resume, skip, reset, show, toggle the Floating widget (compat host `toggle-floating`), and add a task.
- **Launch at login** toggle.

---

## Sync

- **iCloud sync since 1.3.0** — opt-in (Settings → iCloud sync, `sync.enabled`, default off), private-database CloudKit via `CKSyncEngine` (container `iCloud.com.bakhod1r.sharingan`, zone `SharinganData`). Fully degradable: no entitlement/profile, no iCloud account, or the toggle off ⇒ the app behaves exactly as before, with the Settings section reporting why.
- **Shadow-diff architecture** (`Sources/SharinganCore/Services/Sync/`): the store persists whole collections (DELETE-all + re-INSERT in `TaskDatabase.save*`), so there are no per-row change events and no delete events. `sync_shadow` records each record's content hash + CKRecord system fields as of the last *confirmed* sync; diffing the new collection against it yields `(created, changed, deleted)` — that diff is the only source of deletes (without it, a deleted task would be indistinguishable from one created elsewhere and would resurrect forever), and the content hash keeps a 300-row rewrite from becoming a 300-record upload. The shadow is written only after CloudKit confirms a save/fetch, never speculatively, so an interrupted sync resumes instead of dropping changes.
- **Merge rules** (`MergePolicy`, pure, unit-tested without an account): tasks resolve record-level by `modifiedAt` — newest edit wins (field-level merging rejected: a task's fields aren't independent, interleaving two edits can synthesize a task neither Mac had); focus-log statistics merge additively (max per field — two Macs logging the same day converge on the larger truth, worst case undercounts simultaneous work rather than double-counting); a delete only wins if nothing edited the record after it.
- **What syncs**: tasks, categories, tags, templates, focus_log (one record per day/task/subtask triple), the active timer (a single `ActiveTimer` record, newest `updatedAt` wins; with "Mirror timer across Macs" on — `sync.timerMirror`, default on — the other Macs apply it in lockstep via `PomodoroTimer.applyMirroredSession`, aligned to the wall-clock `endsAt` so every Mac ends the phase at the same instant; paused sessions freeze `endsAt` relative to `updatedAt` and are never clock-stale; echoes of a Mac's own write are rejected by deviceID and a running record whose deadline passed is ignored as history. **Since 1.5.0** mirroring is one-way onto *idle* Macs only: `SharinganCoordinator.applyRemoteTimer` ignores remote records while a locally-owned session is running or paused, so two Macs can run independent sessions side by side; a mirrored session sets `PomodoroTimer.isMirroredSession` (cleared by any local start/stop/skip, which takes ownership back), which makes phase completion passive — no auto-start of the next phase, no repeat scheduling, and the coordinator skips task-pomodoro crediting and queue advancement (`"mirrored"` in the `.phaseDidComplete` userInfo) since the owner Mac already credits the synced task. A mirrored break drives the full break side effects — overlay with eye exercises, TTS, ambience, dim, app blocker — via `beginBreakSideEffects`/`endBreakSideEffects` from `applyRemoteTimer`, since mirrored phase changes post no `.phaseDidComplete`. **Since 1.6.0**: `handlePhaseComplete` no longer presents the break overlay for a mirrored focus completion (that lands on a *pending* break with no live `endsAt` yet — the countdown read as frozen); the overlay comes up only once the owner Mac's actual break record applies. A mirrored phase completion also triggers an immediate `syncEngine?.fetchChanges()` instead of waiting for the poll, so the owner's next record (break start, or the following focus) lands in seconds), and an allowlist of settings via `NSUbiquitousKeyValueStore` (`SettingsSync` — the `PomodoroSettings` blob, sort modes, reminder lead; deliberately NOT window geometry, one-shot flags, device identity, or Sparkle bookkeeping, which would fight between Macs). **Since 1.6.0**: local edits push within 2s (debounced `UserDefaults.didChangeNotification` observer) instead of only at `start()`, both `pushLocal`/`applyRemote` skip a key whose value already matches (via `isEqual`) to stop identical bytes ping-ponging between Macs, and `applyRemote` posts `SettingsSync.didApplyRemoteNotification` when something actually changed — `AppDelegate` observes it and reassigns `timer.settings = PomodoroTimer.savedSettings()` so a remote settings change (timer mode, durations, theme, …) reaches the live running app without a relaunch.
- **Push**: a silent `CKDatabaseSubscription` makes remote changes fetch near-instantly; wake/foreground and a 60-second fallback timer (was 15 minutes before 1.6.0 — the Developer ID build carries no `aps-environment` entitlement, so this poll is in practice the primary delivery path, not just a fallback) cover the rest.
- **Release checklist**: promote the CloudKit schema dev→production in the console before shipping a build that syncs, and run the two-Mac checklist (create/edit/delete propagate, delete does not resurrect, offline conflict resolves to the newer edit, same-day stats sum, remote timer mirrors, signing out degrades gracefully).

---

## Packaging & releases

- `Scripts/make-app.sh` assembles `dist/Sharingan.app`: builds `AppIcon.icns` from `Resources/AppIcon.appiconset/icon_1024.png` (sips + iconutil), stamps `CFBundleVersion` with the commit count, compiles the WidgetKit appex with `swiftc` straight into `Contents/PlugIns/SharinganWidget.appex` (`Resources/Widget-Info.plist`, versions stamped in lockstep), then signs **inside-out**: the appex first with `Resources/Widget.entitlements` (sandbox + app group — chronod won't load an unsandboxed widget), the outer app with `Resources/App.entitlements` and **without `--deep`**, which would re-sign the appex and strip its entitlements.
- `Scripts/make-dmg.sh` wraps it in `dist/Sharingan.dmg` with an /Applications drag-install symlink. The image is built read-write first so the mounted **volume** gets the Sharingan icon (`.VolumeIcon.icns` + Finder custom-icon bit — it lives inside the image, so downloaded DMGs keep it), then converted to compressed UDZO; the `.dmg` **file** also gets the icon via Rez/SetFile (local copies only — resource forks don't survive internet downloads).
- **Branded install window**: the app renders its own 560×400 @2x background (`Sharingan --render-dmg-background <png>` — ghost classic iris, title, arrow, "Drag into Applications to install") into the volume's `.background/`, and an AppleScript poses Finder — icon view, no toolbar/statusbar, 100pt icons, app at (140,195), Applications at (420,195) — so the written `.DS_Store` persists into the compressed image. Best-effort: without Finder Automation permission the DMG still builds, just unstyled.
- **Universal binaries**: anything distributed carries both arm64 and x86_64 slices, or it won't launch on an Intel Mac. `make-dmg.sh` therefore passes `--universal` by default (`--host`/`--debug` opts out for fast local builds); `make-app.sh --universal` builds the app via `swift build --arch arm64 --arch x86_64` and — since `swiftc` emits one slice per invocation — compiles the appex **once per arch** and `lipo -create`s them together. The script asserts both slices are present before exiting, so a half-universal bundle can't ship silently.
- Releases: push a `v*` tag → `.github/workflows/release.yml` builds the DMG on a macOS runner (`macos-15` — `macos-14`'s Swift 5.10 type-checker rejected code the dev toolchain accepts) and attaches it, notes from CHANGELOG.md.

### Signing & notarization

- **Signed and notarized since 1.2.0.** Both packaging scripts are env-driven, so a checkout with no credentials still builds: unset `SIGN_IDENTITY` ⇒ ad-hoc signing exactly as before (local dev, no certificate needed); set it to `Developer ID Application: … (89LCRZKZ48)` ⇒ real signing plus `--options runtime --timestamp` (hardened runtime and a secure timestamp are notarization requirements, and notarytool — not codesign — is what rejects a bundle missing them).
- `Scripts/notarize.sh <file>` is the single notarization path (`make-dmg.sh` calls it for the app and again for the image): it zips a bundle for submission — notarytool takes archives only, and a zip cannot carry a ticket, so the staple goes back onto the bundle itself — waits for the verdict, **checks the status line explicitly** (notarytool exits 0 even on an Invalid verdict) and prints the notary log when Apple rejects. It runs only when `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8` are set; `make-dmg.sh` fails hard if `SIGN_IDENTITY` is set without them, since a signed-but-unnotarized DMG looks shippable and still trips Gatekeeper. A stapled app clears Gatekeeper even offline. The DMG is signed **after** the Rez icon step, which rewrites the file and would invalidate an earlier signature. `spctl --assess` on both artifacts gates the build on Gatekeeper's actual verdict.
- Identity: bundle ID `com.bakhod1r.sharingan`, Team ID `89LCRZKZ48`, app group `89LCRZKZ48.com.bakhod1r.sharingan` (Team-ID-prefixed — containermanagerd rejects an unprefixed group container claim from a team-signed app). `RebrandMigration` moves the 1.1.x `com.sharingan.app` defaults domain and Application Support directory across, so existing users keep their settings.
- CI secrets: `MACOS_CERT_P12` (base64 of the exported Developer ID identity) + `MACOS_CERT_PASSWORD`; `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_P8` (App Store Connect API key — `ASC_KEY_P8` is the key's raw contents, not base64) for notarytool; `SPARKLE_ED_PRIVATE_KEY` for the appcast. Certificates and keys are gitignored (`*.cer`, `*.p12`, `*.p8`, `*.provisionprofile`) — they must never enter the public repo.
- **One repo.** Since 1.2.0 the only remote is the public `bakhod1r/sharingan`. This is load-bearing for updates, not tidiness: Sparkle's feed, the Pages deploy, the release asset and the appcast commit must all live in the same repo, or the feed lands where Pages never serves it and every installed copy silently 404s on update. The release workflow asserts this (it compares `SUFeedURL`'s host/path against `GITHUB_REPOSITORY` and fails if they disagree).

### Auto-updates (Sparkle)

- Sparkle 2 ships as an SPM dependency; `make-app.sh` embeds `Sparkle.framework` into `Contents/Frameworks`, adds the `@executable_path/../Frameworks` rpath, and signs the framework's nested code (XPC services, `Autoupdate`, `Updater.app`) inside-out with the same identity — each is a separate code object and notarization checks all of them.
- `UpdaterService` (Sources/Sharingan/Services) wraps `SPUStandardUpdaterController`. It is inert outside a real `.app` bundle, so `swift run` and the test suite are unaffected. Surfaces: "Check for Updates…" in the status-item menu and Settings → Updates (auto-check toggle, version, Check Now). **Since 1.6.0**: fully silent — `automaticallyDownloadsUpdates = true`, and the `SPUUpdaterDelegate.willInstallUpdateOnQuit` hook takes the immediate-install handler (suppressing every "update available"/"restart to update" dialog) and holds it as `pendingInstall`. `AppDelegate` wires `UpdaterService.isSafeToInstall` to the live timer (`timer.isIdleAtFocus && !BreakWindowManager.shared.isBlocking`) and calls `installOpportunity()` whenever `timer.$isRunning` goes false, so a staged update installs (with a relaunch, no UI) the moment no focus/break session is in flight — never mid-pomodoro. No "update ready" affordance is shown; this is deliberately invisible to the user.
- The feed is `site/appcast.xml`, published by GitHub Pages at `https://bakhod1r.github.io/sharingan/appcast.xml` (`SUFeedURL`); updates are verified against `SUPublicEDKey` (EdDSA), independently of the Apple signature. `Scripts/update-appcast.sh` signs the DMG with `sign_update` and inserts the release item; the release workflow runs it and pushes the updated feed to main, so publishing a tag both ships the DMG and offers it to installed copies.
- The first Sparkle-enabled release (1.2.0) must still be installed by hand — earlier builds have no updater to offer it.

## Marketing site

- A single landing page focused on the three pillars — Pomodoro, Tasks, Eye health — each with a hand-built animated **CSS mock** of the app's UI (no videos, GIFs, or app renders): a counting timer ring, a Today panel that checks tasks off and slides new ones in, and the break screen with app-shaped almond eyes (MoveEyeShape Béziers via clip-path) running a guided drill with a spinning Sharingan iris.
- A "Top features" grid of 14 cards, each with its own mini CSS animation (menu-bar timer, Notch HUD island that expands, WidgetKit desktop-widget tile, Floating widget, focus queue, streak chart, app blocking, ambience equalizer, voice arcs, screen dim, reminders, weekly board, six themes, CLI). Pillar bullets cover the 1.x feature wave: per-task pomodoro sizes, custom priority levels, 25-language quick add, Markdown/JSON bulk import, sort/filter, and the per-task Report. Advertised version lives in `site/js/config.js` (+ the hero's static `cta-meta` fallback).
- One live demo: the natural-language quick-add parser, in-page. Animated CLI terminal, FAQ (honest about sync being planned, not shipped), download.
- Hero sits over the live WebGL eyes (loaded after window "load" so they never touch the critical path); below-fold animations stay paused until their section is revealed.
- Light/dark theme toggle that remembers your choice; respects reduced-motion preferences.

---

*Maintenance rule: any change that adds or alters a feature must update this
document (and the changelog) in the same change.*
