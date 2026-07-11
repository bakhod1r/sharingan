# Tasks Roadmap

Feature roadmap for the task/todo system, agreed 2026-07-11. Each phase is its
own spec → plan → implementation cycle.

## Phase 1 — Model & parser foundation
Spec: `docs/superpowers/specs/2026-07-11-tasks-phase1-design.md`

- [ ] Natural-language quick add (`ertaga 15:00 p1 #ish hisobot yozish`)
- [ ] Extended recurrence (every N days, monthly)
- [ ] Snooze / overdue rollover (one-tap postpone, overdue badge)
- [ ] Due-date notifications v2 (pre-reminder offset, morning overdue digest)
- [ ] Task templates + duplicate
- [ ] Subtask reorder + promote-to-task
- [ ] Archive & completed history (completedAt, grouped Done view, restore)

## Phase 2 — Capture channels
Both reuse the Phase-1 task input parser.

- [ ] Global quick-capture hotkey (⌃⌥T mini window from any app)
- [ ] `tired task` CLI commands (add / list / done / start)

## Phase 3 — Focus integration

- [ ] Focus queue — select several tasks into an ordered queue; each finished
      pomodoro advances to the next; break window shows "next: …"
- [ ] Post-break task picker — when a break ends, a modal asks which task the
      next focus session is for (pre-answered when a queue is active)
- [ ] Time reports by project / tag (extend StatsExtras)
- [ ] Eisenhower matrix smart view (priority × due date quadrants)

## Phase 4 — System integration

- [ ] App Intents — Siri / Shortcuts (start focus, add task), unlocks
      Raycast / Stream Deck
- [ ] WidgetKit widget — today's tasks + timer state
- [ ] Night Shift scheduler (old PLAN.md #18)

## Explicitly out of scope (declined 2026-07-11)

- Apple Reminders / Calendar sync
- iPhone companion app
- Task links / URL attachments
