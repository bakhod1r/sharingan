# Design: Menu bar countdown toggle, Daily goal, Focus/DND via Shortcuts

Date: 2026-07-10
Status: approved in conversation, pending spec review

Three small, independent conveniences. One plan, three tasks.

## A. Menu bar countdown — Settings toggle

Today `AppDelegate.updateTitle()` always shows `MM:SS` next to the status
icon while a session is engaged. Add an opt-out.

- **Setting:** `PomodoroSettings.showMenuBarCountdown: Bool = true`.
  Default preserves current behavior.
- **Behavior:** `updateTitle()` shows the countdown only when
  `engaged && settings.showMenuBarCountdown`; otherwise title is empty
  (icon only).
- **UI:** Settings → Timer → new "Menu bar" section with a single toggle,
  next to the existing "Floating timer" section.

## B. Daily goal + progress ring

- **Setting:** `PomodoroSettings.dailyGoal: Int = 8`; `0` disables the
  feature entirely (no ring, no notification). Stepper in Settings →
  Timer, range 0–24.
- **Progress source:** `PomodoroStats.completedTodayCount()` — already
  maintained; no new bookkeeping.
- **UI:**
  - Menu bar popover (`MenuBarView`) header: compact `Circle().trim()`
    progress ring with `3/8` text, theme accent color. Hidden when goal
    is 0.
  - Main window stats (`StatsSummaryView`): same data as a larger
    ring/tile.
- **Completion notification:** in `BlinkCoordinator`, immediately after
  `registerFocusCompletion`, if `completedTodayCount() == dailyGoal`
  post one macOS notification ("Daily goal reached — 8/8 🎯") via
  `NotificationService`. The equality check fires exactly once per day
  because the count increments by one per completed focus. Known edge:
  lowering the goal mid-day below the current count means no
  notification that day — acceptable.

## C. Focus/DND — Shortcuts.app integration, configured in Settings

macOS has no public API to toggle Focus. The stable route is running
user-created Shortcuts via `/usr/bin/shortcuts run <name>`.

- **Settings** (Settings → Focus → new "Do Not Disturb" section):
  - `dndEnabled: Bool = false`
  - `dndShortcutOn: String = "Blink Focus On"`
  - `dndShortcutOff: String = "Blink Focus Off"` (both editable text fields)
  - "Test" button per shortcut, a link that opens Shortcuts.app, short
    setup instructions, and a last-run status indicator
    (✓ ran / ⚠︎ shortcut not found) so a wrong name is visible instantly.
- **Service:** new `DNDShortcutService` in BlinkCore/Services. Runs
  `Process` on `/usr/bin/shortcuts run <name>` asynchronously, reports
  success/failure. The process runner is injected for tests.
- **Hooks** (`BlinkCoordinator`):
  - focus session starts → run the On shortcut
  - focus ends / skip / reset → run the Off shortcut
  - app terminates during focus → best-effort Off in
    `applicationWillTerminate`.
- All hooks are no-ops when `dndEnabled` is false.

## Testing

BlinkCore unit tests:
- settings defaults + Codable round-trip for the new fields
- goal-notification trigger (fires at exact equality, once, not at 0)
- `DNDShortcutService` with a mock runner: correct executable path and
  arguments, error surfaced when the runner fails.

UI (toggle visibility, ring rendering) verified manually.
