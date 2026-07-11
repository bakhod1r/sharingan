# Tasks Phase 1 — Model & Parser Foundation

**Date:** 2026-07-11
**Scope:** 7 features that live mostly in `BlinkCore` (models + `TaskStore`)
with light UI in `TasksView` / `TaskEditorView`. No new windows, no new
processes. Phases 2–4 build on this layer (see `docs/ROADMAP.md`).

## Context

The task system already has: priority (P1–P4), tags, category, project,
due date, planned date, notes, subtasks with estimates, recurrence
(daily / weekdays / weekly), smart views (Today / Upcoming / All / Done),
search, SQLite persistence (`TaskDatabase`), due-time notification
(`TaskStore.scheduleDueNotification`), CSV export, CloudKit sync of the
JSON-encoded store.

All new model fields MUST follow the existing defensive-decoding pattern
(see `TaskItem.init(from:)`) so older SQLite rows keep loading.

---

## 1. Natural-language quick add

New `TaskInputParser` enum in `BlinkCore/Services` (separate from the
timer-oriented `NaturalLanguageParser`).

**Input:** one composer line. **Output:**

```swift
struct ParsedTaskInput: Equatable, Sendable {
    var title: String            // input with recognized tokens stripped
    var tags: [String]           // #ish  → ["ish"]
    var project: String?         // @blink
    var priority: TaskPriority   // p1…p4 (word-boundary only)
    var dueDate: Date?           // date phrase + optional time
    var estimatedPomodoros: Int? // ~3
    var recurrence: Recurrence   // recurrence phrase
}
```

**Recognized tokens (English + Uzbek):**

| Token | Examples |
|---|---|
| Tag | `#ish`, `#deep-work` (multiple allowed) |
| Project | `@blink` (first occurrence wins) |
| Priority | `p1` `p2` `p3` `p4` |
| Date | `today/bugun`, `tomorrow/ertaga`, weekday names (`friday/juma`, next occurrence), `12.08` / `12/08` (day.month) |
| Time | `15:00`, `5pm` — combines with the date phrase, defaults to today (or tomorrow if already past) |
| Estimate | `~3` → 3 pomodoros |
| Recurrence | `daily/har kuni`, `weekdays/ish kunlari`, `weekly/har hafta`, `every N days/har N kunda`, `monthly/har oy` |

Rules: matching is case-insensitive on word boundaries; unrecognized text
stays in the title; a date phrase with no time gets 09:00; parser is pure
(takes `now:` for tests).

**UI:** the existing composer in `TasksView` parses on every keystroke and
renders detected tokens as small chips under the field (reuse the existing
chip components). Enter → `store.add(...)` with parsed fields. A leading
`\` escapes parsing for that line (edge case: task titles that genuinely
contain `p1` etc.).

## 2. Extended recurrence

`Recurrence` gains two cases with associated values:

```swift
case everyNDays(Int)   // har 3 kunda
case monthly(Int)      // day-of-month 1…31, clamped to month length
```

Custom Codable: encode as a single string (`"everyNDays:3"`,
`"monthly:15"`); decoding falls back to the existing raw strings
(`"daily"` …) so old rows and old sync blobs load unchanged. `nextDate`
gets the new math — `monthly` clamps (31 → Feb 28/29). Editor picker in
`TaskEditorView` gains the two new options (stepper for N / day-of-month).

## 3. Due-date notifications v2

Today a notification fires exactly at `dueDate`. Add:

- **Pre-reminder offset** — global setting (`PomodoroSettings`,
  default 10 min, options 0/5/10/30/60): a second notification
  "Due in 10 min: <title>" (id `blink.task.pre.<uuid>`).
- **Reschedule audit** — every mutation that changes `dueDate`, completes,
  or deletes a task must cancel + reschedule both ids. Centralize in one
  `syncDueNotifications(for:)` helper called from `update/toggleDone/delete`.
- **Morning overdue digest** — optional (default off): daily 09:00 local
  notification "3 tasks overdue" when count > 0, scheduled by
  `BlinkCoordinator` on launch/day-change.

## 4. Snooze / overdue rollover

Overdue tasks already surface in Today (`matches`). Add:

- **Overdue chip** — red "overdue" badge on rows whose `dueDate < now`.
- **Snooze actions** — row context menu (+ swipe in the popover list):
  *Tomorrow*, *Next week*, *Pick date…*. Moves `dueDate` forward keeping
  the original time-of-day, updates `plannedDate` if it was set, and
  reschedules notifications. `TaskStore.snooze(_ id: UUID, to: Date)`.

## 5. Task templates + duplicate

- **Duplicate** — context menu → deep copy with fresh UUIDs, title
  suffix " (copy)", state reset (`isDone=false`, `pomodorosDone=0`,
  subtask done flags cleared), `createdAt=now`, no `completedAt`.
- **Templates** — "Save as template" stores a state-stripped `TaskItem`
  JSON in a new `templates` SQLite table (id, name, json). Composer "+"
  menu gains "From template…" (instantiates with fresh IDs, relative
  due = none). Small manage sheet: rename / delete. `TemplateStore`
  observable in `BlinkCore`, persisted via `TaskDatabase`.

## 6. Subtask reorder + promote

- `TaskStore.reorderSubtasks(_ taskID:, from: IndexSet, to: Int)` +
  drag handles in `TaskEditorView`'s subtask list (`onMove`).
- `TaskStore.promoteSubtask(_ taskID:, _ subID:)` — creates a top-level
  `TaskItem` inheriting the parent's category / project / tags / priority,
  carrying the subtask's title, estimate and `pomodorosDone`; removes the
  subtask from the parent. Context-menu action "Make a task".

## 7. Archive & completed history

- `TaskItem.completedAt: Date?` — set in `toggleDone` (cleared on
  un-complete), defensive-decoded, included in CSV export and spawn-next
  recurrence handling (`spawnNextOccurrence` copies must not inherit it).
- **Done view** — grouped by completion day ("Today", "Yesterday", then
  absolute dates) instead of by category; each row has *Restore*.
- **Clear** — the Done view's existing "Clear" becomes a confirmed,
  permanent delete (alert with count).

---

## Error handling

- Parser never throws; worst case the whole line is the title.
- Recurrence decode failure falls back to `.none` (never drops the task).
- Notification scheduling stays best-effort (existing pattern).

## Testing

- `Tests/BlinkTests`: `TaskInputParser` table tests (en + uz, escapes,
  past-time rollover), recurrence `nextDate` math incl. month clamping and
  Codable round-trip/back-compat, `snooze` time-of-day preservation,
  `completedAt` lifecycle, `promoteSubtask` inheritance, template
  instantiate-with-fresh-IDs, duplicate state reset.
- `SelfTest`: add assertions mirroring the model-level cases.

## Out of scope (later phases)

Global capture hotkey, `tired task` CLI, focus queue, post-break task
picker, project/tag time reports, Eisenhower view, App Intents, widget,
Night Shift.
