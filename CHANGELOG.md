# Changelog

All notable changes to Sharingan are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/); versions follow [SemVer](https://semver.org/).

## [Unreleased]

## [1.5.1] — 2026-07-14

### Fixed
- The black strip under the notch while a session runs is gone: the live island's black now stops at the hardware cutout, exactly like idle — the 4pt lip below it belongs to the progress line alone (the accent line and its faint track, no black backing). The silhouette, hover stroke, and click mask are unchanged

## [1.5.0] — 2026-07-14

### Added
- Sort & filter everywhere tasks are listed: the focus-task picker ("Choose a task" / "What's next?") gets a chip bar under its header, and the weekly board gets two circle buttons by the week navigation — the board's sort orders every column and the filter narrows cards across the whole board (the header's planned-count follows). The sort choice is one shared preference, so the Tasks list, picker, and board always agree; filters stay per-view
- The picker distinguishes "no open tasks" from "no tasks match the filter", keeping the controls visible so the filter can be cleared

## [1.4.1] — 2026-07-14

### Added
- Branded DMG install window: opening Sharingan.dmg now shows a designed window — dark background with a ghost Sharingan iris rendered by the app itself (`--render-dmg-background`), the app icon and Applications folder laid out side-by-side with an arrow, toolbar hidden. The layout is scripted into the image's .DS_Store at build time, so it survives release downloads

## [1.4.0] — 2026-07-14

### Added
- Sort menu in the Tasks view bar (↑↓): order each category's rows by Priority (most urgent first, custom levels above P1), Due date (dateless last), A–Z, Newest, or the default Manual drag order. The choice sticks across launches; open tasks always stay above done ones, and ties keep the manual order so nothing shuffles
- Filter menu in the Tasks view bar (funnel): narrow the list to one category, tag, or priority right from the list — the same narrowing the sidebar offers, shown in the "Filtered by …" chip with its ✕ to clear. Picking the active entry again toggles it off

## [1.3.1] — 2026-07-14

### Fixed
- The DMG now shows the Sharingan icon everywhere: the mounted volume carries `.VolumeIcon.icns` *inside* the image (so it survives GitHub release downloads too) and the local `.dmg` file gets the icon via its resource fork. The generic-icon app/dmg you may have on disk came from the pre-icon v1.0.0 release — rebuild (`Scripts/make-dmg.sh`) or grab the next release and replace those copies

## [1.3.0] — 2026-07-14

### Added
- Subtask priorities: every step can carry its own P1–P4 flag. Import templates set it with an exact `p1`…`p4` token on the step line (Markdown) or a `"priority"` field on JSON subtasks; the subtask rows and the task editor show the flag as a colored rank chip, the editor's per-step flag menu edits it, and promoting a subtask keeps the step's own flag (falling back to the parent's). Step pomodoro size now carries over on promote too

## [1.2.0] — 2026-07-14

### Added
- Duplicate-safe import: pasting the same template twice no longer doubles the list — imported tasks whose title already exists on an open task (or earlier in the same document) are held back and a prompt asks "Skip Duplicates / Add Anyway"; the import sheet's counter shows "· N already exist" live. Completed tasks don't block a title from coming back
- The `sharingan://add-task` URL and `tired task add` CLI now bulk-import whole documents too (duplicates skipped silently — there's no one to ask headless)
- The Sharingan spins: the menu-bar tomoe (and the Dock icon while the main window is open) rotate slowly, in phase — turn it off in Settings → General → Appearance → "Spin the Sharingan". Pauses automatically under macOS Reduce Motion and while your screens sleep
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
