# Task import — Markdown + JSON templates

**Date:** 2026-07-14 · **Status:** approved (user: "json va mdlik qil bos")

## Goal

The user copies a template from Settings, fills it in (by hand or with an LLM),
and pastes or drops it into the app; the app parses it into fully-featured
tasks. Both Markdown and JSON are supported; the format is auto-detected.
The template covers every task feature: title, category, project, tags,
priority, due date+time, planned day, estimate, recurrence, pomodoro size,
notes, subtasks (with per-step estimate, done flag, pomodoro size), done flag.

## Prerequisite fix — ⌘V paste

The app is `.accessory` and never installs `NSApp.mainMenu`, so ⌘V/⌘C/⌘X/⌘A/⌘Z
key equivalents have no Edit menu to route through and are dead in every text
field. Fix: build a minimal main menu (Edit: Undo/Redo/Cut/Copy/Paste/Select
All) in `applicationDidFinishLaunching`. Invisible for accessory apps but key
equivalents route through it.

## Format — Markdown (hybrid)

- `#` or `##` heading starts a task. The heading line goes through the existing
  `TaskInputParser`, so quick-add tokens work in 25 languages:
  `# Hisobot yozish p1 #teg @proyekt ~4 ertaga 15:00`
- Optional `key: value` lines directly refine the task. Keys are
  case-insensitive, English + Uzbek aliases:
  `category/kategoriya`, `project/proyekt/loyiha`, `tags/teglar` (comma-sep),
  `priority/muhimlik` (P1…P4|high|medium|low|none), `due/muddat`,
  `planned/reja`, `estimate/baho` (int), `repeat/takror`
  (none|daily|weekdays|weekly|every N days|monthly:N — or any localized phrase
  the quick-add parser knows), `pomodoro` (small|normal|big),
  `notes/eslatma`, `done` (true/yes/x).
  Date values accept `YYYY-MM-DD [HH:mm]` or any natural-language phrase
  (`ertaga 15:00`) via `TaskInputParser`.
- `- [ ] Step ~2 (big)` / `- [x] Step` lines are subtasks; a trailing `~N` is
  the step estimate, a trailing `(small|normal|big)` its pomodoro size.
- Any other non-empty line inside the block becomes notes (multi-line joined).
- Headingless mode: a document with no headings is treated as a flat checklist —
  each top-level `- …` line is one task (through `TaskInputParser`), indented
  `  - …` lines under it are its subtasks.

## Format — JSON

Accepts a single object, an array, or `{"tasks": [...]}`. Parsed leniently via
`JSONSerialization` (not strict Codable). Keys mirror the md keys; `tags` may
be an array or comma string; `priority` accepts "P1"…"P4"/names/int (int =
P-number, 1 = urgent); dates are `YYYY-MM-DD`, `YYYY-MM-DD HH:mm`, or ISO8601;
`subtasks` entries are strings or `{title, estimate?, done?, pomodoro?}`.

## Components

- `SharinganCore/Services/TaskImportParser.swift` — pure
  `parse(_ raw: String, now: Date) -> [TaskItem]`; detects JSON (`{`/`[`) vs
  markdown. Also `TaskImportParser.markdownTemplate` / `.jsonTemplate` strings.
- TasksView: import button in the view bar → sheet with a text editor, live
  "N tasks recognized" count, Import/Cancel. `.md`/`.json`/text file drop onto
  the tasks list opens the sheet prefilled. Import calls `TaskStore.insert`
  per task (assigns sort order, schedules reminders, persists).
- Settings → Tasks & Planning: "Import template" block — segmented MD/JSON
  preview with a Copy button for each.

## Testing

Unit tests (`TaskImportTests.swift`) over the pure parser: md heading blocks,
key:value overrides (both languages), subtask estimates/kinds, notes capture,
headingless checklist, JSON array/object/tasks-wrapper, lenient priority/date
forms, garbage → [].
