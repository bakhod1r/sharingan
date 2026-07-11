# Tasks Roadmap

Feature roadmap for the task/todo system, agreed 2026-07-11.
**Status: all phases shipped 2026-07-12.**

## Phase 1 — Model & parser foundation ✅
Spec: `docs/superpowers/specs/2026-07-11-tasks-phase1-design.md`

- [x] Natural-language quick add (`ertaga 15:00 p1 #ish hisobot yozish`)
- [x] Extended recurrence (every N days, monthly)
- [x] Snooze / overdue rollover (one-tap postpone, overdue badge)
- [x] Due-date notifications v2 (pre-reminder offset setting)
- [x] Task templates + duplicate
- [x] Subtask reorder + promote-to-task
- [x] Archive & completed history (completedAt, grouped Done view, restore)

## Phase 2 — Capture channels ✅

- [x] Global quick-capture hotkey (NL-parsing quick-add panel)
- [x] `tired task` CLI commands (add / list / done / start / queue)

## Phase 3 — Focus integration ✅

- [x] Focus queue — ordered task queue; each finished pomodoro advances;
      break window shows "Next: …"
- [x] Post-break task picker — floating panel asks which task the next
      focus session is for (skipped when a queue is active)
- [x] Time reports by project / tag (StatsExtras sections)
- [x] Eisenhower matrix smart view (priority × due date quadrants)

## Phase 4 — System integration ✅

- [x] `sharingan://` URL scheme (start/pause/skip/reset/add-task/show) —
      App Intents substitute for Shortcuts / Raycast (pure SwiftPM can't
      build an intents extension)
- [x] Floating Today panel — desktop glass card with today's tasks + timer
      (WidgetKit substitute, same constraint)
- [x] Night Shift warmth during breaks (private CoreBrightness API, fail-soft)

## Bonus (user requests along the way)

- [x] Mono theme — black & white

## Explicitly out of scope (declined 2026-07-11)

- Apple Reminders / Calendar sync
- iPhone companion app
- Task links / URL attachments
