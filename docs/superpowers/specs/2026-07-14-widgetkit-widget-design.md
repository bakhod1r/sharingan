# WidgetKit desktop widget — design

**Date:** 2026-07-14 · **Target version:** 1.11.0

## Overview

A real WidgetKit widget (Notification Center / desktop widget gallery) showing
the pomodoro at a glance: phase, live remaining time, active task, today's
pomodoro count vs. goal, and streak. Distinct from the Dock pill spec
(2026-07-14-dock-widget-design.md), which is an in-app `NSPanel`; this one is a
system widget that lives outside the app process.

## Constraints that shape everything

1. **Pure SwiftPM, no Xcode project.** The `.appex` is assembled and signed by
   `Scripts/make-app.sh`, like the app itself. AppIntents don't work in this
   setup (no `appintentsmetadataprocessor` build phase — already noted in
   `URLCommandRouter.swift`), so **interactive widget buttons are out**. All
   taps are deep links through the existing `sharingan://` URL scheme.
2. **Ad-hoc signing, no team ID.** App Groups still work on macOS (they're not
   provisioning-restricted there), but macOS 15+ may show a one-time consent
   prompt for an unprovisioned `group.*` container. Accepted.
3. **Widget process ≠ app process.** The widget can't observe `PomodoroTimer`.
   The app publishes a snapshot file; the widget renders it. Live countdown
   comes from `Text(timerInterval:)` / `ProgressView(timerInterval:)`, which
   tick without timeline reloads.

## Approaches considered

- **A. WidgetKit `.appex` assembled by make-app.sh (chosen).** Real gallery
  widget; fits existing infra; display + deep-link taps only.
- **B. Another floating `NSPanel`.** Not WidgetKit — already covered by the
  Dock-pill spec. Rejected: doesn't answer the request.
- **C. Migrate the repo to an Xcode project** for first-class appex +
  interactive AppIntents buttons. Rejected for v1: upends Makefile/CI/headless
  tooling; revisit only if button-in-widget interactivity becomes a must.

## UX

Families: `systemSmall`, `systemMedium`. Both use
`containerBackground(for: .widget)` (required on macOS 14+).

```
 ┌───────────────┐   ┌──────────────────────────────────┐
 │  ◉ 24:37      │   │  ◉ 24:37      Design review      │
 │  Focus        │   │  Focus        🍅 4 / 8 today     │
 │  🍅 4 today   │   │               🔥 12-day streak   │
 └───────────────┘   │               [▶︎]  [⏸]  [⟲]     │
                     └──────────────────────────────────┘
```

- **Ring (◉):** circular progress in the phase color (focus red-orange, break
  green — same convention as the menu-bar icon). Running: driven by
  `ProgressView(timerInterval:)` so it animates live. Paused/idle: static.
- **Time:** running → `Text(timerInterval:)` (self-updating); paused → static
  remaining; idle → the configured focus length.
- **Phase label:** Focus / Break / Long break / Paused / Ready.
- **Task (medium):** active task title, else "No task selected".
- **Today (both):** completed-today count; medium shows `n / goal` and streak.
- **Taps:** whole small widget → `sharingan://show`. Medium adds three
  `Link` glyphs — ▶︎ `sharingan://start`, ⏸ `sharingan://pause`,
  ⟲ `sharingan://reset` — routed by the existing `URLCommandRouter`. Opening
  the (agent) app is inherent to non-AppIntents widgets; accepted.

## Architecture

| Unit | Role |
|------|------|
| `Sources/SharinganWidgetShared/` (new lib target, Foundation-only) | `WidgetSnapshot` (Codable: schemaVersion, phase, isRunning, isPaused, endDate, remainingSeconds, totalSeconds, taskTitle, todayPomodoros, dailyGoal, streakDays, updatedAt) + `WidgetSnapshotStore` (canonical file URL, atomic write, tolerant read). Pure, unit-tested. |
| `Sources/SharinganWidget/` (new executable target) | `@main WidgetBundle` → one `Widget` with a `TimelineProvider` that reads the snapshot and one SwiftUI entry view (small/medium layouts). Links WidgetKit + SwiftUI only. |
| `Sources/Sharingan/Services/WidgetSnapshotPublisher.swift` (new) | Observes `PomodoroTimer` / `TaskStore` / stats (Combine, debounced ~0.5 s), maps to `WidgetSnapshot`, writes via the store, calls `WidgetCenter.shared.reloadAllTimelines()`. Writes an idle snapshot in `applicationWillTerminate` so a quit app never leaves a counting widget behind. Wired in `AppDelegate` like other services. |
| `Scripts/make-app.sh` | Builds the `SharinganWidget` product, assembles `Contents/PlugIns/SharinganWidget.appex` (binary + generated Info.plist), signs the appex **with entitlements first**, then signs the outer app **without `--deep`** (a `--deep` re-sign would strip the appex entitlements). |
| `Resources/Widget-Info.plist`, `Resources/Widget.entitlements` (new) | Appex identity `com.blink.app.widget`, `NSExtensionPointIdentifier = com.apple.widgetkit-extension`; sandbox + app group `group.com.blink.app`. |

### Data flow

`PomodoroTimer`/`TaskStore` (app) → `WidgetSnapshotPublisher` → JSON at
`~/Library/Group Containers/group.com.blink.app/widget-snapshot.json`
(app writes the raw path; sandboxed widget reads it via
`containerURL(forSecurityApplicationGroupIdentifier:)`) → `TimelineProvider` →
entry view. Timeline policy: running → `.after(endDate)`; else `.after(next
midnight)` so a stale "today" count rolls over. The app force-reloads on every
state change anyway, so policies are just backstops.

### Error handling / staleness

- Snapshot missing or undecodable → placeholder "Ready" state, never a crash.
- `endDate` in the past (app force-killed mid-session) → render as idle.
- Snapshot from a previous day → today count renders 0.
- Writes are atomic; reads tolerate partial/corrupt files by falling back to
  the idle placeholder.

### Sandbox fallback (spike-verified)

Primary: sandboxed appex + app group (canonical, Xcode-default shape). If
chronod refuses the ad-hoc appex or the group container prompts unacceptably,
fallback: drop the sandbox entitlement and read
`~/Library/Application Support/Sharingan/widget-snapshot.json` directly. The
store abstracts the path so only the entitlements + one URL change.

## Testing

- Unit (`SharinganTests`): snapshot Codable round-trip; store write→read;
  staleness rules (past endDate ⇒ idle, yesterday ⇒ zero today-count) as pure
  functions.
- End-to-end: `make app`, install, `pluginkit -m -p
  com.apple.widgetkit-extension` shows `com.blink.app.widget`; widget appears
  in the gallery; countdown ticks while a session runs; taps deep-link.
- `codesign --verify --strict` on app + appex stays green (Gatekeeper on the
  second Mac depends on it).

## Non-goals (v1)

- Interactive buttons that don't open the app (needs AppIntents ⇒ Xcode).
- Lock-screen / iOS families, `systemLarge`, configuration intents
  (`AppIntentConfiguration` — same AppIntents limitation).
- Per-widget task picking; charts/history in the widget.
