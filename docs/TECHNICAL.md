# Sharingan (Blink) — Technical Documentation

> Complete feature and subsystem reference. **Keep this document up to date:
> whenever a feature is added, changed, or removed, update the relevant
> section here in the same commit.**

- App version: 1.0.0 (see `CHANGELOG.md`)
- Platform: macOS 14+, menu-bar app (`LSUIElement` / accessory)
- Stack: Swift 5.9+, SwiftUI + AppKit, Vision, AVFoundation, Carbon, SwiftCharts, SQLite — pure SwiftPM, no Xcode project
- Naming: user-facing name **Sharingan**, repo/URLs **Blink**, persistence namespace `com.blink.*` / `blink.*`

---

## 1. Package layout & targets (`Package.swift`)

| Target | Kind | Purpose |
|---|---|---|
| `SharinganCore` | library | All testable models + services. Bundles `Resources/Sounds/*.caf`. |
| `Sharingan` | executable | The `.app` — AppKit/SwiftUI UI, window managers, views. Bundles `AppIcon.png`. |
| `tired` | executable | Terminal CLI that controls the running app. |
| `SelfTest` | executable | Standalone assertion harness (`swift run SelfTest`). |
| `SharinganTests` | tests | swift-testing suites in `Tests/SharinganTests/`. |

`ResourceBundle.swift` (in both Core and app targets) resolves resource bundles
from `Contents/Resources` inside the assembled `.app` (codesign-safe), falling
back to `Bundle.module` for `swift run` / tests.

---

## 2. Timer / Pomodoro

**Core state machine — `Sources/SharinganCore/Services/PomodoroTimer.swift`**
(`@MainActor ObservableObject`)

- Phases: `focus` / `shortBreak` / `longBreak` / `paused` (`Models/PomodoroPhase.swift` — label, SF Symbol, gradient, glow per phase).
- Publishes `phase`, `remainingSeconds`, `elapsedSeconds`, `isRunning`, `cyclesCompletedInRound`, `repeatIndex`, `stats`, `isFlashing`.
- 200 ms internal tick, but publishes only on whole-second changes (perf).
- **Countdown and count-up modes** (`Models/TimerExtras.swift` → `TimerMode`); time display formats MM:SS / H:MM:SS / compact (`TimeDisplayFormat`).
- **Sleep-gap handling** (`effectiveTickDelta`): wall-clock gaps > 30 s collapse to a single tick during focus (closed lid doesn't credit hours) but count fully during breaks (break completes on wake).
- Long break every `longBreakEvery` pomodoros (divide-by-zero guarded).
- Auto-start focus / break toggles; **endless repeat** loops focus↔break forever; **finite repeat** runs focus sessions back-to-back with a configurable delay and skips breaks in between (`RepeatConfig`).
- `durationOverride` lets CLI / URL / quick input set a custom one-off session length.
- Controls: `start / pause / stop / skip / toggle / addTime / removeTime / setCustomDuration / setTargetTime / applyParsed`.
- Fires `.focusFiveMinLeft` at ≤ 5 min and a screen-flash warning at ≤ 5 s; on focus completion registers stats and posts `.streakUpdated` / `.dailyGoalReached` / `.phaseDidComplete`.

**Natural-language timer input — `Services/NaturalLanguageParser.swift`**
Pure parser → `ParsedTimerInput`. Understands durations (`5 min`, `2h 30m`, bare `25`),
clock targets (`5pm`, `2:15am`), deltas (`add 5m`, `+5m`, `-1h`), `reset` / `stop`.
Shared by the app's quick input, the `tired` CLI, and the URL scheme.

**Settings — `Models/PomodoroSettings.swift`**
One `Codable` struct (~70 fields) stored as a single JSON blob in
`UserDefaults` under `com.blink.settings`. Every field decodes with
`decodeIfPresent` + default, so adding fields never resets user settings.
Covers durations, auto-start, timer mode/format, repeat, break
message/background, floating timer appearance, Today panel, shortcuts, camera
+ strict validation, alarm, TTS, exercises, reminders, ambience, brightness
dim, Night Shift, launch-at-login, app blocker, `requireTaskForFocus`,
`blockAppsDuringFocus`, `dailyPomodoroGoal` (default 8), `weekStartsOnMonday`,
priority/tag styling, `showMenuBarCountdown`, DND.

---

## 3. Tasks

**Model — `Models/TaskItem.swift`**
`TaskItem`: title, category, tags, done, pomodorosDone, createdAt, dueDate,
sortOrder, estimatedPomodoros, plannedDate, notes, subtasks, recurrence,
project, priority (P1–P4, Todoist-style colors), completedAt. Defensive
decoding prevents silent task loss. `Subtask` supports its own estimate and
pomodoro attribution. `Recurrence`: none / daily / weekdays / weekly /
everyNDays(N) / monthly(day), persisted as compact strings (`"everyNDays:3"`).
`TaskCategory`: name + color + icon, 5 presets (Work/Study/Personal/Health/Other) plus custom.

**Store — `Services/TaskStore.swift`** (`@MainActor` singleton)
- Persistence: **SQLite** at `~/Library/Application Support/Blink/blink.sqlite`
  (`Services/TaskDatabase.swift` — bundled libsqlite3, WAL, transactional
  DELETE+INSERT saves, column-add migrations). Env override `BLINK_DB_PATH`.
  Migrates legacy `tasks.json` / `categories.json` on first launch.
- Smart views (`TaskFilter`): Today / Upcoming / All / Completed with counts;
  free-text search over title, tags, project, notes.
- Mutations: add, insert, duplicate (deep copy, " (copy)"), drag reorder,
  planned date (weekly board), toggle done (spawns next recurrence occurrence),
  subtask ops (add / toggle / delete / reorder / **promote to full task**),
  notes, recurrence, priority, project, tag management, delete,
  `incrementPomodoro` (credits task + active subtask).
- **Snooze**: tomorrow / next week / arbitrary date (keeps time-of-day); overdue count badge.
- **Due reminders**: due-time notification + configurable pre-reminder
  (`blink.task.preReminderMinutes`, default 10 min, 0 = off), re-synced on due-date changes.
- CSV export. Active task/subtask are transient (never persisted).

**Quick-add parser — `Services/TaskInputParser.swift`**
Natural-language task entry → title, `#tag`, `@project`, `~N` estimate,
`p1..p4`, dates (today/tomorrow/weekday names/`12.08`), times (`15:00`, `5pm`),
recurrence phrases — **English and Uzbek** (`ertaga`, `har kuni`, `har N kunda`,
`ish kunlari`, `har hafta`, `har oy`). Leading `\` escapes parsing.
Used by the composer, quick-add panel, CLI, and URL scheme.

**Templates — `Services/TemplateStore.swift`** — save any task as a reusable
template (progress/dates stripped), rename/delete/instantiate; stored in the
same SQLite file (`templates` table).

**Focus queue — `Services/FocusQueue.swift`** — ordered task-id queue
(UserDefaults key `blink.focusQueue`). Deduped enqueue, reorder, validated
reads that drop stale/done entries. Each completed focus session advances the
queue; the break screen shows "Next: …"; after a break the **task picker**
(`TaskPickWindowManager`) asks what to work on next when nothing is queued.

**Views** (`Sources/Sharingan/Views/`)
- `TasksView.swift` — full list UI: filters, categories, tags, projects, subtasks, snooze, completed-history grouped by day with restore.
- `TaskEditorView.swift` — task editor (also opened by clicking a card on the week board).
- `WeeklyBoardView.swift` — drag-to-reschedule weekly planner.
- `EisenhowerView.swift` + `Models/EisenhowerQuadrant.swift` — Eisenhower matrix: urgency (overdue / due ≤ 48 h / planned today) × importance (P1/P2) → do-first / schedule / delegate / eliminate.
- `TodayPanelView.swift` + `TodayPanelWindowManager` — floating desktop glass card with today's tasks + timer.
- `QuickAddWindowManager` — global-hotkey quick-add panel (⌃⌥N).
- **Task guard**: `requireTaskForFocus` blocks starting focus without an active task (pops quick-add instead).

---

## 4. Breaks, eye exercises & eye health

**Break overlay** — `BreakWindowManager`: full-screen borderless `NSPanel` on
**every screen** at `.screenSaver` level, joins all Spaces, blocks ⌘Q/⌘W/⌘Tab,
fade in/out. Owns the break-session lifecycle (camera, validator, TTS,
ambience, dim, Night Shift). `BreakView.swift`: animated eye pair following the
exercise gaze, time-left chip, instruction caption + step dots, "Next: …"
queued task, camera privacy badge, exit/skip button.

**Exercises** — `Models/BreakExercise.swift`: built-in library —
`twentyRule` (20-20-20), `gaze` (8 directions + circles + figure-8), `blink`.
`Models/ExerciseSequenceSettings.swift`: per-exercise toggles, hold-time scale,
rounds. `Services/ExerciseValidator.swift` drives step progression: hold
timers, retry signal, 5 s fail-safe auto-advance, **strict validation** mode
(camera-validatable steps wait for real gaze/blink confirmation).

**Camera & Vision** (on-device only, runs **only during breaks**)
- `Services/CameraService.swift` — front camera via AVFoundation, `AsyncStream` frames, permission handling.
- `Services/EyeTracker.swift` — Vision face landmarks → eye open-ratio, blink detection (edge-counted), per-minute blink rate, 8-way gaze estimation from pupil position.

**Voice guidance (TTS)** — `Models/TTSInstruction.swift` (editable per-step
text + rotating "kalib" reminder pool, interval default 20 s),
`Services/TTSService.swift` (AVSpeechSynthesizer, rate/pitch),
`Services/TTSKalibrator.swift` (speaks each step, rotates reminders).

**Break comfort**
- `Services/BreakAmbienceService.swift` — looping ambience: white noise / rain / forest / lo-fi (generated `.caf` in Core resources).
- `Services/BrightnessService.swift` — screen dim via gamma ramp (`CGSetDisplayTransferByFormula`), cubic-ease 1.2 s animation, level default 35 %, restored on quit.
- `Services/NightShiftService.swift` — optional warmth via **private** CoreBrightness `CBBlueLightClient` (dlopen, fail-soft), prior state restored.
- `Services/AlarmSoundService.swift` — phase-completion alarm: glass / chime / soft bell / silent.
- `Services/ReminderService.swift` + `Models/ReminderItem.swift` — posture / water / custom interval reminders (60 s ticker), optional focus-only, paused during breaks.

---

## 5. Sharingan eyes, wallpaper & visuals

- `Models/SharinganStyle.swift` — **18 iris styles** drawn as vector code (tomoe 1/2/classic, Mangekyō / Kamui / Eternal, Itachi, six-star, blade, orbit, crescent, four-blade, Madara, shuriken, swirl, triangle-tomoe, ring-crescents, Rinnegan); break background styles (pure black / graphite / slate); pattern-transition speeds; wallpaper spin triggers (off / idle / click / both / always).
- `Views/MoveEyesView.swift` — the almond-eye vector renderer (Bézier lids, glossy iris, blink/wink). `Views/PatternEvolution.swift` — tomoe → Mangekyō → Rinnegan evolution math.
- **Live wallpaper** — `Services/WallpaperWindowManager.swift`: desktop-level eyes that follow the cursor (60 Hz mouse polling, no permissions), blink/wink when idle, doze when away, wake with the next pattern; restored on launch.
- **Menu-bar icon** — CoreGraphics-drawn Sharingan iris with rotating tomoe + progress arc (red-orange focus / green break / dimmed paused), optional countdown text (`showMenuBarCountdown`).

---

## 6. Stats, streaks & rewards

- `Models/PomodoroStats.swift` — daily counts (400-day history), today count, hour-of-day histogram (best focus hour), weekly/monthly aggregations, week-over-week change, best day/weekday, average per active day. Stored in `UserDefaults` under `com.blink.stats`.
- `Models/StreakStore.swift` — consecutive-day streak with gap reset; `Models/StreakBadge.swift` — milestones 1/7/14/30/90/365 (✨🔥⚡🏆💎👑); `Models/StreakRewardCenter.swift` — announces only newly-unlocked milestones (spring banner `StreakRewardBanner`).
- `Models/TaskBreakdown.swift` — pomodoro attribution **by project / by tag** for stats cards.
- Views: `StatsChartView` / `StatsSummaryView` / `StatsExtrasView` (SwiftCharts), `MenuBarWeekView`, daily goal progress (`dailyPomodoroGoal`).

---

## 7. UI, theming & app structure

- **Themes** — `Models/SharinganTheme.swift`: Liquid Glass, Frosted, Midnight, Cream, Neon, Mono (gradient + accent each). `Models/Palette.swift` + hex parser + glass tints. Glass design system components (`GlassComponents`, `GlassButton`, `VisualEffectBlur`, `CountdownRing`, `ShortcutRecorder`, `QuickInputField`, …).
- **Bootstrap** — `Sharingan/main.swift`: explicit `NSApplication` accessory app. Headless render flags for tooling: `--render-icon`, `--render-menubar-icon`, `--render-iris-grid`, `--render-eyes-preview`, `--render-anim-previews`, `--render-break-preview`, `--render-gaze-grid`, `--render-site-assets` (renders real UI screenshots for the marketing site).
- **`AppDelegate.swift`** — wires timer + coordinator + window managers, dark appearance, notification auth, wallpaper restore, `sharingan://` URL handling, **confirm-quit guard** while focus is running, DND deactivate on quit. `MenuBarController` = `NSStatusItem` + `NSPopover` hosting `MenuBarView` (timer / tasks / week tabs + today's goal).
- **`AppRouter.swift`** — main-window sections: Timer / Tasks / Week / Progress / Settings, with deep-link state for filters.
- **Window managers**: Main, Break, Floating timer (always-on-top, all Spaces, draggable, size presets, auto show/hide on break), Today panel, Quick add, Task pick, Wallpaper.
- **Settings UI** — `SettingsView.swift`, searchable categories: Timer, Tasks & Planning, Breaks, Focus & Blocking, Eye Care, Sharingan Eyes, General, Voice Guidance, Shortcuts.

**Orchestration — `Services/SharinganCoordinator.swift`** (`@MainActor`)
The conductor: installs shortcuts and the CLI bridge, per-slice settings
diffing (`syncChanged` — slider drags don't re-register hotkeys), and
`handlePhaseComplete` — on focus end credits the active task, advances the
focus queue, plays the alarm, presents the break (overlay + ambience + dim +
Night Shift + blocker + TTS); on break end tears everything down, resumes
reminders, and evaluates the post-break task pick. Also drives streak/reward
and daily-goal notifications and DND sync.

---

## 8. Integrations

**`tired` CLI — `Sources/tired/main.swift`**

```
tired start [25 | 5pm | 2h 30m]   # NL input
tired pause | resume | skip | reset | stop
tired add 5m | remove 10m | set 45m
tired status                      # live countdown, stale-app detection
tired task add <NL text> | list | done N | start N | queue N
tired help | version
```

IPC (`Services/CLIBridge.swift`): Darwin notifications (`com.blink.cli.*`) +
JSON state files in `~/Library/Application Support/Blink/cli/`
(`snapshot.json`, `tasks.json`) — no XPC or App Groups. `status` reconstructs
the running countdown from `updatedAt` offline.

**URL scheme — `Services/URLCommandRouter.swift`** (for Shortcuts / Raycast)
`sharingan://start?minutes=25`, `start?input=<NL>`, `pause`, `resume`, `skip`,
`reset`, `show`, `toggle-floating`, `add-task?text=<NL, percent-encoded>`.
Case-insensitive; malformed URLs are ignored.

**Global hotkeys — `Services/KeyboardShortcutsService.swift`** (Carbon
`RegisterEventHotKey`, rebindable via `ShortcutRecorder`):
⌃⌥Space toggle · ⌃⌥F skip · ⌃⌥R reset · ⌃⌥= +5 min · ⌃⌥L floating timer · ⌃⌥N quick-add task.

**App blocking — `Models/AppBlocker.swift` + `Services/AppBlockerService.swift`**
Hide or force-quit distracting apps (presets: Chrome, Safari, VS Code, Slack,
Telegram, Messages) — during breaks, during focus (`blockAppsDuringFocus`), or always.
Watches `NSWorkspace.didActivateApplication`; un-hides on end.

**Do Not Disturb — `Services/DNDShortcutService.swift`** — toggles macOS Focus
by running user-created Shortcuts (`/usr/bin/shortcuts run "Blink Focus On/Off"`)
since there is no public Focus API; edge-triggered.

**Other**: `LaunchAtLoginService` (`SMAppService`, needs a real `.app` bundle),
`NotificationService` (`UNUserNotificationCenter` wrapper, safe when unbundled).

**Sync — `Services/SyncService.swift`** ⚠️ **Intentionally a no-op stub.**
iCloud/CloudKit sync is disabled: an ad-hoc-signed app without an iCloud
entitlement crashes on `CKContainer.default()`. `isAvailable` is always false.
*Note: the README and marketing site still advertise iCloud sync — that is
aspirational, not implemented in this build.*

---

## 9. Data storage map

| Data | Location |
|---|---|
| Settings | `UserDefaults` → `com.blink.settings` (single JSON blob) |
| Stats | `UserDefaults` → `com.blink.stats` |
| Tasks, categories, templates | SQLite `~/Library/Application Support/Blink/blink.sqlite` (override: `BLINK_DB_PATH`) |
| Focus queue | `UserDefaults` → `blink.focusQueue` |
| Task pre-reminder minutes | `UserDefaults` → `blink.task.preReminderMinutes` |
| CLI IPC state | `~/Library/Application Support/Blink/cli/*.json` |

---

## 10. Marketing site (`site/`, GitHub Pages)

- `index.html` — single-page landing: hero, break-enforcement section, feature grid, interactive live-wallpaper WebGL demo with pattern picker, CLI/URL-scheme animated terminal, FAQ, download CTA (latest GitHub Release dmg). SEO: OpenGraph/Twitter meta, `SoftwareApplication` + `FAQPage` JSON-LD.
- `js/eyes.js` — three.js/WebGL port of the app's eye renderer: Bézier-lid almond eyes, iris textures sampled from the app's own headless renders (`assets/app/iris/*.png`), gaze-follow / blink / wink / doze.
- `js/main.js` — light/dark theme toggle (localStorage, dark default), lazy WebGL init after first paint, IntersectionObserver reveals, reduced-motion support.
- `js/config.js` — the only editable constants (version, download/GitHub URLs).

---

## 11. Build, release & CI

```bash
swift build                # all targets
swift run Sharingan        # run the app
swift test                 # swift-testing suites
swift run SelfTest         # standalone assertion harness
make app | dmg | install   # see Makefile
```

- `Scripts/make-app.sh` — release build → `dist/Sharingan.app`; copies SwiftPM resource bundles into `Contents/Resources`, builds `.icns`, stamps build number from git commit count, **ad-hoc codesigns** and hard-fails unless `--strict`-valid. `--universal` optional.
- `Scripts/make-dmg.sh` — `dist/Sharingan.dmg` (UDZO, `/Applications` symlink).
- `Scripts/install.sh` — install to `/Applications`, strip quarantine, launch.
- `Scripts/install-cli.sh` — install `tired` to `/usr/local/bin`.
- CI: `.github/workflows/release.yml` — on tag `v*`, macOS runner builds the dmg, extracts CHANGELOG notes, publishes a GitHub Release. `.github/workflows/pages.yml` — on push to `main` touching `site/**`, deploys the site to GitHub Pages.

---

## 12. Tests

- `Tests/SharinganTests/` (swift-testing): timer models/state machine, NL parsers (EN + Uzbek), recurrence, focus queue + coordinator wiring, break teardown & sleep-gap, Eisenhower, floating-timer settings, Night Shift, stats attribution, subtask ops, task archive & DB migration, snooze, templates, Today panel, URL commands, CLI snapshots, audit regressions.
- `Sources/SelfTest/main.swift` — standalone assertion harness covering models, timer, parsers, streaks, gaze, exercises, SQLite persistence, JSON migration, Codable round-trips.

---

## 13. Known discrepancies

- **iCloud sync**: advertised in README/site, but `SyncService` is a deliberate no-op stub (see §8).
- **License**: README says "Private © 2026 mrb"; the site calls the app "free and open source".
- **Naming**: Sharingan (app/bundle) vs Blink (repo, data directory, persistence keys).

---

*Maintenance rule: any PR/commit that adds or changes a feature must update
this file (and `CHANGELOG.md`) in the same change.*
