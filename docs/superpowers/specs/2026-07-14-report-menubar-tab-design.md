# Report as a menu-bar popover tab — design

**Date:** 2026-07-14 · **Status:** approved (owner picked "4th tab" over a
Timer-tab card and a footer-button-only variant)

## What

Add the day-paged per-task focus Report (`ReportView`, shipped in the main
window's Report section in e227a8c) to the menu-bar popover as a fourth tab
next to Timer / Tasks / Week.

## Why

The popover is where a session is started and finished; the day's outcome
should be readable in the same place without opening the main window. The
day pager also gives past days from the popover.

## Design

One file changes: `Sources/Sharingan/Views/MenuBarView.swift`.

- `Tab` gains `.report`; the segmented `Picker` gains
  `Label("Report", systemImage: "list.bullet.rectangle").tag(Tab.report)` —
  the same symbol the main window's sidebar uses for the section.
- The tab `switch` gains `case .report: ReportView(timer: timer)`.
  `ReportView` is reused **unchanged**, exactly the way the popover's Tasks
  tab reuses the main window's `TasksView`. Data comes from
  `TaskStore.shared`, so popover and window stay in sync for free.
- Width stays 360pt (only `.week` widens the popover); the report scrolls
  inside the existing fixed 512pt tab area. `ReportView` is a plain `VStack`,
  so the popover's `ScrollView` wrapper hosts it as-is.
- Pager fit at 324pt content width: 26 + 10 + 180 (label `minWidth`) + 10 +
  26 ≈ 252pt, plus the Today button ≈ 300pt — fits.

## Risk

Four labeled segments at 360pt may truncate. Fallback, only if the render
shows it: drop the segment labels to icons only. Decided by looking at the
new dev-preview shot, not speculatively.

## Verification

No new logic — no unit tests. Add a `report-popover.png` shot (ReportView at
324pt width) to `--render-dev-preview`, next to the existing report shots,
and eyeball the width fit and the four-segment picker.

## Docs

`docs/TECHNICAL.md`: the menu-bar popover's tab list (Timer/Tasks/Week →
plus Report). `CHANGELOG.md`: one entry.
