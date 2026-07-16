# Custom board columns (Sharingan board) — design

Date: 2026-07-16 · Branch: `jira` · Target version: 1.12.0

## Goal

Turn the Sharingan **Board** tab (shipped in 1.10.0 as fixed To Do / In
Progress / Done) into a **custom-column kanban**: the user can add, rename,
delete, and enable/disable columns, and drag tasks between them. Columns and
each task's column ride the user's existing cross-Mac sync.

## Background / current state

- `SharinganBoardView` renders three hardcoded columns derived from task
  state (`isDone`, `activeTaskID`). That derivation goes away — columns are
  now first-class, user-defined data and a task's column is stored on the task.
- Tasks persist to SQLite (`TaskStore`, `tasks.json`) and sync to CloudKit
  field-by-field via `RecordMapper` (Jira added four fields behind a
  **promote gate**: the new Task fields must be promoted dev→production in the
  CloudKit dashboard before shipping — this feature adds one more).
- Settings already sync as a blob through `SettingsSync`; the column
  definitions ride that path, so no new CKRecord type is needed.

## Design

### Data model

**`BoardColumn`** (new, SharinganCore, `Codable`, `Sendable`):
```
struct BoardColumn: Identifiable, Codable, Equatable, Sendable {
    var id: String            // stable slug ("today", or a UUID string for user-added)
    var name: String
    var order: Int
    var isEnabled: Bool
    var role: Role            // .plain (default) or .done
    enum Role: String, Codable { case plain, done }
}
```
- `role == .done` is the only built-in coupling: dropping a task into a
  `.done` column sets `isDone = true`; dragging it out sets `isDone = false`.
  Every other column is a pure bucket. At most one `.done` column.
- Seeded defaults (first run / migration), in order: **Today**, **This Week**,
  **In Progress**, **Paused**, **Done** (`role: .done`), **Cancelled**.

**Task field** (added to `TaskItem`): `var boardColumnID: String?`
- `nil` ⇒ the task shows in the first enabled column ("inbox" fallback).
- A task whose `boardColumnID` names a disabled or deleted column also falls
  back to the first enabled column visually, without rewriting the stored id.

### Storage & sync

- **Column list**: stored in the synced settings blob (`SettingsSync`). One
  array of `BoardColumn`. Reuses the existing sync path — no CloudKit schema
  change for columns.
- **`boardColumnID`**: a new Task field.
  - SQLite: rides the existing `tasks.json` (Codable, decode as optional so old
    rows load — same pattern as the Jira fields).
  - CloudKit: `record["boardColumnID"]` in `RecordMapper` (write + read).
  - **Release gate:** promote the new `boardColumnID` Task field dev→production
    in the CloudKit dashboard before shipping (extends the existing Jira
    4-field gate — now five).

### Behavior

- **Board rendering**: columns = enabled `BoardColumn`s in `order`; each shows
  its tasks (`boardColumnID == column.id`, or the fallback set for the first
  column), in the shared sort order (`tasks.sortMode`).
- **Drag** a card onto a column → set `boardColumnID = column.id`; if the
  target is the `.done` column set `isDone = true`, if leaving a `.done`
  column set `isDone = false`. Fully reversible.
- **Column management** (board header):
  - **+ Add column** — prompts for a name, appends an enabled `.plain` column.
  - Per-column **"…" menu**: Rename, Enable/Disable, Delete.
  - **Delete** removes the column; its tasks keep their (now-dangling) id and
    fall back to the first column. A `.done` column can be disabled but the
    seeded Done keeps its id so completion still has a home; deleting the only
    `.done` column is allowed (completion then only happens via the task row).
- **Cross-surface**: columns are the board's own grouping. Only the `.done`
  coupling affects other surfaces (via `isDone`, already reflected everywhere).
  A task in "Cancelled" stays "open" elsewhere in v1 — hiding cancelled tasks
  app-wide is out of scope (future).

### Migration

- First run after upgrade: seed the six default columns into settings.
- Backfill `boardColumnID` for existing tasks: `isDone` ⇒ the Done column id;
  otherwise leave `nil` (falls back to the first column, "Today").

## Out of scope

- Per-column WIP limits, colours, column-level sort overrides.
- Hiding Cancelled (or any column's) tasks from the Tasks list / stats.
- Menu-bar popover board (still weekly-only).
- Touching `JiraBoardView` / the Jira tab.

## Testing

- Unit (SharinganCore): `BoardColumn` Codable round-trip; default seed order;
  migration backfill (done→Done, open→nil); drag mutation helper
  (set column, done-coupling both directions); delete/disable fallback
  resolution ("which column does this task render in").
- `RecordMapper`: `boardColumnID` survives record → task → record.
- Manual: add/rename/delete/disable columns, drag across, relaunch (persist),
  second-Mac sync (after the promote gate).

## Versioning

CHANGELOG 1.12.0, `Info.plist` + `docs/TECHNICAL.md` bump, TECHNICAL.md
sections for the custom board and the new CloudKit gate.
