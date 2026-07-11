# Tasks Roadmap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans
> to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Implement the full tasks roadmap (docs/ROADMAP.md): Phase 1
foundation, Focus queue + post-break picker, capture channels, focus
integration, system integration.

**Architecture:** All logic lands in `BlinkCore` (testable, SwiftPM), UI in
`Blink` views. Persistence via the existing `TaskDatabase` (SQLite) and
`UserDefaults` patterns. Every model change uses defensive decoding.

**Tech Stack:** Swift 5.9, SwiftUI/AppKit, swift-testing, SQLite, Carbon
hotkeys, UserNotifications.

## Global Constraints

- macOS 14+, pure SwiftPM — no Xcode project.
- New `TaskItem`/`Recurrence` fields must decode from old rows (defensive
  `init(from:)`, see TaskItem).
- Every task: swift-testing tests in `Tests/BlinkTests` + `swift test` green
  before commit. Commit + push per task.
- Uzbek + English NL tokens where user-facing parsing is involved.

## Known platform constraints (Phase 4)

- **App Intents / WidgetKit need an Xcode-built extension bundle** — not
  available in pure SwiftPM. Substitutes: URL scheme (`sharingan://`) +
  `tired` CLI for Shortcuts/Raycast; a floating "Today" panel instead of a
  WidgetKit widget.
- **Night Shift** has no public API — use CoreBrightness
  `CBBlueLightClient` via ObjC runtime, fail soft if unavailable.

---

### Task 1: TaskInputParser (NL quick add core)
- Create: `Sources/BlinkCore/Services/TaskInputParser.swift`
- Test: `Tests/BlinkTests/TaskInputParserTests.swift`
- Produces: `TaskInputParser.parse(_ raw: String, now: Date) -> ParsedTaskInput`
  with `title, tags, project, priority, dueDate, estimatedPomodoros, recurrence`.
- Tokens per spec §1 (en+uz): `#tag @project p1..p4 ~3`, dates
  (today/bugun, tomorrow/ertaga, weekdays en/uz, `12.08`), times
  (`15:00`, `5pm`), recurrence words, leading `\` escape.

### Task 2: Extended Recurrence
- Modify: `Sources/BlinkCore/Models/TaskItem.swift` (Recurrence)
- Test: `Tests/BlinkTests/RecurrenceTests.swift`
- `case everyNDays(Int)`, `case monthly(Int)`; string coding
  `"everyNDays:3"`/`"monthly:15"`, old raw strings still decode;
  `nextDate` math with month clamping; `label` strings.

### Task 3: completedAt + archive/restore
- Modify: `TaskItem` (+`completedAt: Date?`), `TaskStore.toggleDone`,
  `spawnNextOccurrence` (copy must not inherit), `csv()`.
- Test: `Tests/BlinkTests/TaskArchiveTests.swift`.

### Task 4: Snooze + notification v2 (store level)
- Modify: `TaskStore` — `snooze(_:to:)` keeping time-of-day,
  `snoozeTomorrow/nextWeek` helpers; centralize `syncDueNotifications(for:)`
  (due + pre-reminder `blink.task.pre.<uuid>`); overdue digest count API
  `overdueCount(now:)`. `PomodoroSettings` — `taskPreReminderMinutes: Int`
  (default 10), `overdueDigestEnabled: Bool` (default false).
- Test: `Tests/BlinkTests/TaskSnoozeTests.swift`.

### Task 5: Templates + duplicate
- Modify: `TaskDatabase` (+`templates` table), `TaskStore.duplicate(_:)`.
- Create: `Sources/BlinkCore/Services/TemplateStore.swift`
  (`TaskTemplate {id, name, item}`, add/instantiate/rename/delete).
- Test: `Tests/BlinkTests/TemplateTests.swift`.

### Task 6: Subtask reorder + promote
- Modify: `TaskStore` — `reorderSubtasks(_:from:to:)`,
  `promoteSubtask(_:_:) -> UUID?` inheriting category/project/tags/priority.
- Test: `Tests/BlinkTests/SubtaskOpsTests.swift`.

### Task 7: Focus queue core + post-break hook
- Create: `Sources/BlinkCore/Services/FocusQueue.swift` — ordered task IDs,
  `enqueue/dequeue/advance/current/clear`, persisted in UserDefaults,
  auto-skips done/deleted tasks (validated against TaskStore).
- Modify: `BlinkCoordinator` — on focus-phase completion credit active task
  and `advance()`; expose `needsTaskPick` signal when a break ends and no
  queue entry remains.
- Test: `Tests/BlinkTests/FocusQueueTests.swift`.

### Task 8: Phase-1 + queue UI wiring
- Modify: `TasksView` (composer live chips via TaskInputParser; snooze
  context menu; overdue chip; Done view grouped by completion day with
  Restore + confirmed Clear; templates menu; queue multi-select),
  `TaskEditorView` (recurrence picker incl. new cases; subtask `onMove` +
  "Make a task"), `SettingsView` (pre-reminder offset, digest toggle),
  `BreakView`/`BreakPresenter` ("next: …" + post-break picker modal via
  `TaskPickerSheet`), `FloatingTimerView` untouched.
- Manual verify: `swift build` + `swift run SelfTest`.

### Task 9: `tired task` CLI
- Modify: `Sources/tired/main.swift`, `CLIBridge` (+task commands:
  `task add <nl>`, `task list`, `task done <n>`, `task start <n>`),
  app-side handler in coordinator using TaskInputParser.
- Test: parser-level tests + `Tests/BlinkTests/CLITaskTests.swift` for
  command encoding.

### Task 10: Global quick-capture hotkey
- Modify: `KeyboardShortcutsService` (+⌃⌥T binding),
- Create: `Sources/Blink/Views/QuickCaptureWindow.swift` — small floating
  NSPanel with one TextField, parses via TaskInputParser, Enter saves,
  Esc closes.

### Task 11: Stats by project/tag
- Modify: `Sources/Blink/Views/StatsExtrasView.swift` (+project/tag
  pomodoro breakdown sections), `PomodoroStats` if per-task attribution
  needs a new counter keyed by project/tag at increment time.
- Test: `Tests/BlinkTests/StatsAttributionTests.swift`.

### Task 12: Eisenhower matrix view
- Create: `Sources/Blink/Views/EisenhowerView.swift` — 4 quadrants
  (urgent = due today/overdue; important = P1/P2), tap → editor, shown as
  a smart-view toggle in TasksView header.
- Test: quadrant classification function in BlinkCore
  (`Tests/BlinkTests/EisenhowerTests.swift`).

### Task 13: URL scheme + Shortcuts story (App Intents substitute)
- Modify: `Resources/Info.plist` (CFBundleURLTypes `sharingan://`),
  app delegate URL handler → commands (start/pause/skip/add-task NL).
- Test: URL→command mapping unit test.

### Task 14: Floating Today panel (widget substitute)
- Create: `Sources/Blink/Views/TodayPanelView.swift` + window service —
  optional always-on-desktop glass panel: today's tasks + timer state,
  toggle in Settings.

### Task 15: Night Shift scheduler
- Create: `Sources/BlinkCore/Services/NightShiftService.swift` —
  CBBlueLightClient via NSClassFromString; enable-during-break option +
  schedule (sunset-to-sunrise passthrough / custom warmth during breaks);
  Settings toggle. Fail-soft when API unavailable.
- Test: service API surface test (no-crash when framework missing).

### Task 16: Docs + roadmap checkboxes
- Update README features, ROADMAP checkmarks, commit.
