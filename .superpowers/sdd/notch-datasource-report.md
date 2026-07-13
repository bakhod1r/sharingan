# Notch island data source — real open work, not just dated tasks

## The bug
The island's list came from `TaskStore.grouped(filter: .today)` flattened. `.today`
means *planned today, due today, or overdue* — a task with **no date** is invisible
to it. A user whose tasks are undated saw "Nothing planned for today" while staring
at open work in the app.

## New `NotchTaskRows` signature
```swift
public static func rows(today: [TaskItem],
                        queue: [UUID],
                        active: UUID? = nil,
                        fallback: [TaskItem] = [],
                        limit: Int = defaultLimit) -> [TaskItem]
```
`today:` and `queue:` stay first, with `active:`/`fallback:` defaulted, so the two
existing external call sites (`HeadlessRenderTests`, the older unit tests) keep
compiling and "no active task, no fallback" degrades to exactly the old behavior.

Pure and deterministic: builds one id→item lookup from `fallback` then `today`
(today wins ties), then walks four tiers through a single `seen`-set deduper and
`prefix(limit)`. `active`/`queue` ids that resolve to no item are skipped (stale/
deleted/done), never faulted on.

## How each tier is sourced (`NotchWindowManager.taskRows(limit:)`)
1. **active** — `TaskStore.shared.activeTaskID`, always first when it resolves.
2. **queue** — `AppServices.focusQueue.taskIDs`, in queue order.
3. **today** — `store.grouped(filter: .today).flatMap(\.items)` (unchanged filter).
4. **fallback** — `store.tasks.filter { !$0.isDone }` sorted by `createdAt` **descending**.
   There is no "touched-at" stamp on `TaskItem` (only `createdAt`/`sortOrder`/
   `completedAt`); newest-created-first is the honest proxy for "most recently
   relevant". The impure ordering lives in the caller; the pure function just
   preserves the order it is handed. `fallback` is the *whole* open list — the
   deduper drops whatever earlier tiers already claimed, so tier 4 is "the rest".

## Panel + geometry stay on one count
Both sides go through the same `NotchWindowManager.taskRows(...)` →
`NotchTaskRows.rows(...)`, which builds the full merged list *independent of limit*
and only `prefix(limit)`s at the end. So `rows(limit: b)` is always a prefix of
`rows(limit: a)` for b ≤ a. `syncTaskRows`/`refresh` count with
`limit: clampedTaskRows` and stamp `config.taskCount`; the panel renders with
`limit: renderedTaskRows = min(clampedTaskRows, taskCount)`. Same inputs, prefix-of-
prefix property ⇒ the geometry's count and the panel's rows are identical. No change
to the agreement machinery was needed — the fix is entirely inside the shared call.

Empty state reworded "Nothing planned for today" → **"No open tasks"** (panel +
`NotchGeometry` caption comments + `docs/TECHNICAL.md`). `TodayPanelView` keeps its
own "Nothing planned for today" — that view genuinely is the Today list.

## Tests (`Tests/SharinganTests/NotchTaskRowsTests.swift`)
8 existing tests unchanged (queue/today/dedup/cap regressions). 9 added:
- undated open task, empty today, no queue → still appears (the bug);
- today ahead of fallback, no repeats; fallback preserves handed order;
- active leads; active leads once even when also queued+today; stale active skipped;
- full four-tier priority order deduped+capped; cap bounds the merged list;
- genuinely empty (no open tasks) → empty result (the empty state).

## Build / test
- `swift build` — clean (Build complete!).
- `swift test` — 384 tests, 45 suites, all pass. "Notch task rows" suite: 17/17.

## Doubt
Tier-4 ordering is `createdAt` desc by necessity (no updated-at field). If a real
"recently touched" signal is added later, that sort is the one line to revisit. The
pure function itself is agnostic — it preserves whatever order the caller ranks.
