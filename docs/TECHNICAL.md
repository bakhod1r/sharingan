# Sharingan (Blink) — Feature Reference

> Every feature of the app, described in plain terms. **Keep this up to date:
> whenever a feature is added, changed, or removed, update this document in the
> same change.**

- Version: 1.0.0
- Platform: macOS 14+, lives in the menu bar

---

## Timer / Pomodoro

- Configurable focus, short break, and long break durations (25 / 5 / 15 by default).
- Countdown and count-up modes.
- Long break automatically after every N pomodoros.
- Auto-start focus and auto-start break toggles.
- Repeat: run focus sessions back-to-back with a delay, or loop focus↔break endlessly.
- Natural-language time input: `5 min`, `2h 30m`, bare `25`, clock targets like `5pm`, deltas like `+5m` / `-1h`, and `reset` / `stop`.
- Screen flash warning in the last 5 seconds; a "5 minutes left" notification.
- Sleep-aware: closing the lid during focus doesn't wrongly credit hours; a break still completes when you wake the Mac.
- Custom one-off session length that survives mode changes.

---

## Tasks & planning

- Full task system: title, priority (P1–P4), tags, projects, categories, due dates, notes, and estimates.
- Subtasks with their own estimates — reorder them, or promote a subtask into a full task.
- Recurrence: none, daily, weekdays, weekly, every N days, or monthly (on a chosen day). Completing a recurring task spawns the next occurrence.
- Natural-language quick add in **English and Uzbek**, e.g. `ertaga 15:00 p1 #ish @blink ~2 hisobot yozish` — with live parse chips while you type.
- Smart views: Today, Upcoming, All, Completed — each with counts. Free-text search over title, tags, project, and notes.
- Snooze a task to tomorrow, next week, or a picked date; overdue badges.
- Due reminders with a configurable pre-reminder (default 10 minutes before, or off).
- Templates: save any task as a reusable template and instantiate it later. Duplicate tasks too.
- Completed history grouped by day, with restore.
- CSV export.
- **Focus queue**: line up several tasks — each finished pomodoro advances to the next one, the break screen shows "Next: …", and after a break a picker asks what to work on next.
- **Eisenhower matrix** view: tasks sorted into do-first / schedule / delegate / eliminate by urgency and importance.
- **Weekly board**: drag tasks between days to reschedule.
- **Today panel**: a floating desktop card showing today's tasks and the timer.
- Optional guard that requires an active task before focus can start.

---

## Breaks & eye health

- Full-screen break overlay on **every monitor**, above other windows; ⌘Q / ⌘W / ⌘Tab are blocked until the break ends. Includes a skip button.
- Eye exercises: the 20-20-20 rule, 8-direction gaze (plus circles and figure-8), and blink drills.
- Exercise picker chips at the top of the break screen — tap any exercise to run it on demand; the eyes perform it and the sequence continues from there.
- Configurable exercise sequence: turn individual exercises on/off, scale hold times, set rounds.
- **Camera blink & gaze validation** using on-device face tracking — the camera runs only during breaks, never during focus. Optional strict mode waits for real gaze/blink confirmation before advancing a step; otherwise a fail-safe auto-advances.
- Pulsing camera privacy badge whenever the camera is active.
- **Voice guidance (TTS)**: spoken step instructions plus a rotating pool of reminder phrases, with editable text, rate, and pitch.
- **Ambience sounds**: white noise, rain, forest, or lo-fi — looped during breaks.
- **Screen dim**: smoothly dims the display during breaks to a chosen level, restored afterward.
- **Night Shift warmth**: optional warmer screen tone during breaks.
- **Reminders**: posture, water, and custom interval reminders — optionally focus-only, paused during breaks.
- **Phase alarm**: choose the completion sound (glass, chime, soft bell, or silent).

---

## Sharingan eyes & visuals

- 18 iris styles — 1/2/3-tomoe, Mangekyō variants, Rinnegan, and more, all drawn as smooth vector art.
- Pattern evolution: iris designs evolve from tomoe → Mangekyō → Rinnegan.
- Animated eye pair on the break screen that follows the exercise gaze, blinks, and winks.
- **Live wallpaper**: desktop-level eyes that follow the cursor, blink and wink when idle, doze when you're away, and wake with the next pattern.
- Menu-bar icon: a Sharingan iris with rotating tomoe and a progress ring (red-orange during focus, green during breaks, dimmed when paused), with an optional countdown readout.

---

## Stats, streaks & rewards

- Daily focus history with today's count and a best-focus-hour breakdown.
- Weekly and monthly aggregations: week-over-week change, best day, best weekday, average per active day.
- 7-day and 30-day charts.
- Consecutive-day streak tracking that resets on a missed day.
- Milestone badges at 1, 7, 14, 30, 90, and 365 days, with a spring-animated reward banner when a new one is unlocked.
- Pomodoro breakdown by project and by tag.
- A configurable daily pomodoro goal with progress and a "goal reached" notification.

---

## Themes & interface

- Six themes: Liquid Glass, Frosted, Midnight, Cream, Neon, and Mono.
- Liquid-glass design throughout.
- Main window sections: Timer, Tasks, Week, Progress, and Settings.
- Menu-bar popover with timer, tasks, and week tabs plus today's goal.
- Floating timer: an always-on-top panel that joins all Spaces, is draggable, has size presets, and auto shows/hides around breaks.
- Confirmation prompt before quitting while a focus session is running.
- Searchable settings, grouped into: Timer, Tasks & Planning, Breaks, Focus & Blocking, Eye Care, Sharingan Eyes, General, Voice Guidance, and Shortcuts.

---

## Focus enforcement & integrations

- **App blocking**: hide or force-quit distracting apps (presets include Chrome, Safari, VS Code, Slack, Telegram, Messages) — during breaks, during focus, or always.
- **Do Not Disturb**: toggles a macOS Focus mode automatically at the start and end of sessions.
- **Global keyboard shortcuts** (rebindable): start/pause, skip, reset, +5 minutes, toggle floating timer, and quick-add task.
- **`tired` CLI** — control the app from Terminal: start (with natural-language input), pause, resume, skip, reset, add/remove/set time, check live status, and manage tasks (add, list, mark done, start, queue).
- **`sharingan://` URL scheme** for Shortcuts / Raycast: start, pause, resume, skip, reset, show, toggle floating timer, and add a task.
- **Launch at login** toggle.

---

## Sync

- iCloud sync is planned but **not active** in this build.

---

## Marketing site

- A single landing page: hero, break-enforcement section, feature grid, an interactive live-wallpaper demo with a pattern picker, an animated CLI/URL-scheme terminal, an FAQ, and a download button for the latest release.
- Light/dark theme toggle that remembers your choice.
- Respects reduced-motion preferences.

---

*Maintenance rule: any change that adds or alters a feature must update this
document (and the changelog) in the same change.*
