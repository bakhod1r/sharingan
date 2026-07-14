# Dock widget unification — design addendum

**Date:** 2026-07-14 · Builds on `2026-07-14-dock-widget-design.md`.
Owner decisions (chat): the Dock widget ABSORBS the floating timer (the
floating card is removed outright), Start opens a mini task list, and the
widget becomes draggable.

## 1. Draggable widget

- The pill's panel becomes movable (`isMovable`, `isMovableByWindowBackground`,
  same as the old `FloatingMiniPanel`). Dragging it anywhere sets a CUSTOM
  position, persisted in UserDefaults (`sharingan.dockwidget.x/y`) via
  `NSWindow.didMoveNotification` — but ONLY for user drags, not programmatic
  `setFrame` calls (guard with an `isRepositioning` flag around programmatic
  moves, or register the observer the way FloatingWindowManager did, after
  presenting).
- With a custom position: dock-side placement is skipped; on screen changes
  the frame is clamped into `visibleFrame` (FloatingWindowManager.clamped
  precedent). Hover-expand anchor: pill on the left half of the screen →
  `.leading` (opens rightward), right half → `.trailing`.
- Context menu on the pill gains **"Return to Dock"**: clears the stored
  position and reverts to `DockWidgetGeometry` placement. While docked
  (no custom position), behavior is exactly today's.

## 2. Start → mini task picker

- ▶︎ opens a small anchored list (NSPopover on the widget's hosting view) of
  **today's open tasks** — the same task set the Today panel shows, reusing
  its exact filter — active task highlighted, row = category dot + title
  (+ 🍅 count). Choosing a row: `TaskStore.setActive(id)` then
  `timer.startFocusSession(kind: <task's pomodoro kind>)` — the same entry
  point every task-row play button uses (find the exact precedent in
  TasksView/MenuBarView and mirror it). Top row: "Start without task" →
  plain `startFocusSession()` with the active task left as-is.
- Owner refinement: if today's open-task list is EMPTY, ▶︎ starts immediately
  (no empty picker). Starting must never be blocked by the picker — Esc /
  click-away dismisses without starting, and "Start without task" always
  works. ⏸ and ⟲ are unchanged.
- The popover may take key focus while open (it's a deliberate interaction);
  the widget panel itself stays non-activating.

## 3. Floating timer removal

The floating card feature is deleted end-to-end: `FloatingWindowManager`,
`FloatingTimerView`, the `FloatingTimerController` protocol +
`floatingController` + `syncFloating()` + the `$isRunning` show/hide sink arm
in `SharinganCoordinator`, AppDelegate wiring, the Settings "Floating timer"
section(s) and any popover/menu toggles, and the `floating*` fields +
`FloatingTimerSize` in `PomodoroSettings` (dropping stored fields is
decode-safe — unknown JSON keys are ignored).

Compatibility rules:
- A persisted `.showFloating` shortcut binding or a `floating` URL command
  must NOT crash or fail decode. Keep the raw case/command recognized and
  make it a no-op (or retarget it to toggling `dockWidgetEnabled`) — whichever
  the existing decode structure makes cheaper; document the choice.
- `RebrandMigration`'s copying of old floating defaults keys stays as-is
  (it migrates raw domains, not feature code).
- Tests: `FloatingTimerSettingsTests` is deleted; URL/shortcut/settings-
  category tests are updated to the new surface, keeping their decode-
  tolerance assertions.

## 4. Rename: "Dock widget" → "Floating widget" (owner, after the removal)

Once the floating card is gone, the unified pill takes the "Floating widget"
name (owner: "floating widget — dock widget emas"): user-facing labels
(Settings section, hints, menus, CHANGELOG, TECHNICAL.md) and Swift
types/files (`FloatingWidgetView`, `FloatingWidgetWindowManager`,
`FloatingWidgetController`, `FloatingWidgetGeometry`,
`FloatingWidgetSize/Alignment/StartAction`, tests). The PERSISTED
`PomodoroSettings` property names keep the historical `dockWidget*` prefix so
existing settings blobs decode unchanged — noted with a comment at the
declarations. Settings hint copy drops "near the Trash" (the pill is
draggable now; docked placement is just its home position).

## 5. Versioning

One minor version for the whole unification (next free after the in-flight
1.17.0), CHANGELOG entries under Added (drag, picker) and Removed (floating
timer), TECHNICAL.md rewritten accordingly, dist rebuilt from a clean
worktree and relaunched.
