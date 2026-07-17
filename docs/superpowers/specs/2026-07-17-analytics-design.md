# Sharingan Analytics — Design Spec (2026-07-17)

Ten analytics features, built in three phases on `feature/analytics`.
User decisions: build all phased; app tracking configurable (default focus-only);
new dedicated Analytics page; real .xlsx export.

## Foundation: per-session log

Existing stats are aggregates (`PomodoroStats.history` daily counts, `hourCounts`;
`FocusLogEntry` per-task daily rows). Replay, time machine, burnout, and honest
scores need per-session records.

New in SharinganCore:

```swift
struct SessionRecord: Codable, Identifiable, Sendable {
    var id: UUID
    var start: Date
    var end: Date
    var phase: PomodoroPhase          // focus / shortBreak / longBreak
    var completed: Bool               // false = skipped/abandoned
    var taskID: UUID?
    var subtaskID: UUID?
    var taskTitle: String?            // snapshot, survives deletion
    var plannedSeconds: TimeInterval
    var appUsage: [String: TimeInterval]   // bundleID → seconds (empty if tracking off)
}
```

`FocusSessionLog` (service): JSON file store in the app container, same defensive
decoding style as PomodoroStats; append on every phase end (complete, skip, stop
after meaningful progress); retention 400 days; day-indexed reads
(`sessions(on: Date)`, `sessions(in: DateInterval)`). Written by
`SharinganCoordinator` at phase transitions. Existing aggregates unchanged —
heatmap also feeds from `history`, so long-time users see data immediately.

## Active app tracking

`ActiveAppTracker` (SharinganCore service): `NSWorkspace.didActivateApplicationNotification`
for the frontmost app — app-level only, no window titles, no Accessibility
permission. Idle gap detection via `CGEventSource.secondsSinceLastEventType`
(> 2 min idle = untracked). Modes: `off / focusOnly (default) / always`
(Settings → new Analytics section). Focus-only accumulates into the running
session's `appUsage`; Always additionally writes per-day app totals
(`DailyAppUsage` rows in the same store). Local only, exportable, deletable.

## Scores (pure, unit-tested)

`AnalyticsEngine` (SharinganCore, pure functions over `[SessionRecord]` + tasks):

- **Focus Score (0–100/day)** = weighted: focus minutes vs daily goal (existing
  daily goal setting; 40%), completion ratio completed/(completed+abandoned)
  (25%), break compliance — breaks taken vs skipped (20%), deep-block bonus —
  runs of consecutive completed pomodoros (15%). No sessions ⇒ no score (nil),
  not zero.
- **Consistency Score (0–100)** = plan adherence: today's planned tasks
  completed, estimate-vs-actual accuracy per task, start-time regularity vs the
  user's median start hour (from log), streak factor.
- **Focus load**: per-hour focus-seconds histogram for a day/range → area chart
  data ("diqqat cho'qqilari").

## UI: Analytics page

New sidebar destination in `AppRouter` → `AnalyticsView` with sub-tabs:

1. **Overview** — two score gauges (ring style matching CountdownRing), score
   trend sparkline, smart-suggestion card, burnout banner when triggered.
2. **Heatmap** — GitHub-style 52-week grid from `PomodoroStats.history`
   (falls back seamlessly for pre-log history), 5-step accent color scale,
   hover/click shows the day's totals, month labels.
3. **Focus load** — hour-of-day area chart; day pager + 7/30-day average
   overlay.
4. **Timeline** (phase 2) — horizontal day ribbon: session blocks (focus =
   accent red, breaks = green, abandoned hatched), task labels, app-usage
   segments beneath. **Time Machine** = the date navigation on this tab
   (◀ ▶, calendar picker via SharinganCalendar) — any past day replays.
5. **Apps** (phase 2) — table: app icon, name, focus time, share; range picker.
6. **Export** (phase 3) — range picker + PDF (themed report render via
   ImageRenderer/print API), CSV, and XLSX from a minimal in-repo writer
   (zip + SpreadsheetML, no dependencies).

## Burnout & suggestions (rule-based)

- **Burnout detection**: over the session log — ≥5 consecutive heavy days
  (≥8 pomodoros), any 12+ pomodoro day, break-skip ratio > 50%, late-night
  (23:00+) focus on ≥3 recent days. Any two triggers ⇒ warning level; banner on
  Overview + one notification (per-condition cooldown, dismissible).
- **Smart suggestions**: templated insights from existing stats + log — best
  hour ("Odatda 9 AM da yaxshi ishlaysiz"), best weekday, estimate drift,
  break-skipping nudge. Localized like the rest of the app; max 2 shown.

## Phases

1. Session log + scores + heatmap + focus load + Analytics page skeleton.
2. App tracking + timeline/replay + time machine + Apps tab.
3. Export (PDF/CSV/XLSX) + burnout + suggestions.

Each phase: CHANGELOG SemVer entry, Info.plist + TECHNICAL.md bump, tests in
`Tests/`, commit + push (multi-Mac workflow).

## Testing

- Unit: AnalyticsEngine scores (edge: empty day, all-abandoned, midnight-spanning
  sessions), FocusSessionLog decode-forward-compat, burnout rules, xlsx writer
  output unzips to valid XML.
- Runtime: `verify` skill — drive timer via sharingan:// URLs, confirm records
  land and page renders.

## Error handling

Log write failures never block the timer (fire-and-forget with logging, same
principle as the 1.7.3 widget-snapshot fix). Corrupt log file ⇒ rename aside and
start fresh, never crash. Tracking observers torn down when mode is off.
