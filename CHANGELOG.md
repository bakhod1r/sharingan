# Changelog

All notable changes to Sharingan are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/); versions follow [SemVer](https://semver.org/).

## [Unreleased]

### Added
- Clicking a task's title in the notch island opens the main window on the Tasks section, scrolled to that task with a short highlight flash — the done box and the play button on either side keep working as before

## [1.1.0] — 2026-07-14

### Added
- Bulk task import from Markdown or JSON: paste a document into Tasks → import (or drop a `.md`/`.json` file on the list) and every task feature parses — priority, category, project, tags, due, planned day, estimate, repeat, pomodoro size, subtasks with estimates, notes. Copyable templates for both formats live in Settings → Tasks & Planning; markdown headings understand the quick-add syntax in all 25 languages, and a plain checklist works too
- Import works from every add-a-task field: paste a whole document into the main composer, menu-bar quick add, the quick-add hotkey window, the weekly-board backlog, or the task picker and it bulk-imports right there — single lines still quick-add as before. Pasted-document damage is tolerated: ```json fences, smart/curly quotes, trailing commas, and a UTF-8 BOM are all normalized
- Report section: day-by-day per-task focus statistics — pomodoros and real minutes per task and subtask, with day totals; plus a "By task — today" card in Progress, a 14-day history block in the task editor, and a Report tab in the menu-bar popover

### Fixed
- Per-task pomodoro size (Small/Normal/Big) now survives an app relaunch: the SQLite `tasks` table never had a `pomodoroKind` column, so the setting silently dropped on every save/reload (subtask-level sizes were unaffected). Caught by the new import end-to-end round-trip test
- ⌘V / ⌘C / ⌘X / ⌘A / ⌘Z now work in every text field: the app never installed a main menu (accessory apps don't get one by default), so the standard Edit-menu key equivalents had nothing to route through — a minimal hidden Edit menu now carries them
- Closed notch island no longer shows a black lip under the notch on light menu bars (light wallpapers): idle is now exactly the hardware cutout — nothing painted beyond the housing; the 4pt lip lives only in the running state, where it carries the progress line
- Adding a task no longer creates it twice: every text field submits through a single `.onSubmit` — the legacy `TextField(onCommit:)` fired a second time on end-editing with the field's stale text (`SubmitWiringTests` now lints the pattern out)
- Menu-bar popover is readable under system Light mode: it pins its own dark appearance instead of inheriting light from the menu bar it's anchored to, which rendered the dark-glass design's white text on a light popover

## [1.0.0] — 2026-07-12

First public release. 🍅👁️

### Pomodoro
- Configurable focus / short break / long break durations (25/5/15 defaults), long break every N pomodoros
- Countdown and count-up modes, auto-start toggles, repeat with delay
- Natural-language time input — `5 min`, `2h 30m`, `5pm`, `+5m`, `-1h`, `reset`
- Global shortcuts: ⌃⌥Space start/pause, ⌃⌥F skip, ⌃⌥R reset, ⌃⌥+ add 5 min, ⌃⌥L floating timer

### Breaks & eye health
- Full-screen, multi-monitor break overlay at screen-saver level; ⌘Q/⌘W/⌘Tab blocked until the break ends
- Eye exercises: 20-20-20, 8-direction gaze, blink drills — with camera blink/gaze validation (Vision, fully on-device)
- TTS voice guidance, pulsing camera privacy badge
- Break comfort: ambience sounds (rain, forest, white noise, lo-fi), smooth screen dim, optional Night Shift warmth
- Posture / water / custom interval reminders

### Tasks
- Full task system: P1–P4 priorities, tags, projects, due dates, notes, subtasks, recurrence, templates, snooze
- Natural-language quick add (English + Uzbek): `ertaga 15:00 p1 #ish ~2 hisobot yozish`
- Focus queue — each finished pomodoro advances to the next task; post-break picker
- Eisenhower matrix, per-project/tag stats, floating Today panel
- `sharingan://` URL scheme for Shortcuts / Raycast

### Sharingan
- 18 eye styles — 1/2/3-tomoe, Mangekyō variants, Rinnegan and more, with pattern evolution
- Live wallpaper: desktop eyes that follow the cursor, blink, wink when idle, doze when away, and wake with the next pattern
- Menu-bar iris icon with rotating tomoe

### More
- Streaks with milestone badges (1/7/14/30/90/365 days) and 7/30-day charts
- iCloud sync (private CloudKit database)
- App blocking during breaks (hide or force-quit chosen apps)
- Six themes: Liquid Glass, Frosted, Midnight, Cream, Neon, Mono
- `tired` CLI — start/pause/skip/add time/tasks from Terminal
- Confirm-quit guard while a focus session is running

### Requirements
- macOS 14+, Apple Silicon
