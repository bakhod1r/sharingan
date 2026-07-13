# Notch HUD — dressed in Blink's glass

Paint-only pass on the island. No geometry, constants, layout, or logic touched —
every change is a color, material, border, font, or button *style*.

## Tokens / components reused (nothing invented)

- `Font.dsTimer(_:)` — the app's one countdown-numeral face (light, rounded,
  monospaced). Now the island clock (26pt expanded) and the live ear clock (13pt),
  so the notch clock is the same element as the menu-bar strip and floating pill.
- `Color.dsPrimary / dsSecondary / dsTertiary` — replaced every ad-hoc
  `.white.opacity(…)` foreground across the timer row, task rows, ears, quick
  actions, status strip, empty caption, announcement.
- `Color.dsHairline` — the body's ring and the timer-row divider (was `white 0.10`).
- `.glass(_:material:)` from `GlassComponents` — the play/pause/skip/+5/reset
  circles (`Circle`, `.regular`) and the quick-action chips
  (`RoundedRectangle(DS.Radius.sm)`, `.regular`). `.buttonStyle(.pressableSubtle)`
  is the app's press interaction.
- `PomodoroPhase.gradient` / `.glow` — used as an *accent*, never a wash: the body
  glow behind the timer, the active-row fill + hairline, the running row's
  play/pause glyph, the announcement icon. (The progress line and ear dot already
  used it — kept.)
- `.regularMaterial` + phase gradient + `dsHairline` on an `UnevenRoundedRectangle`
  — the body surface, the same recipe `TodayPanelView` and the popover use.
- `DS.Radius.sm`, `DS.Motion.snappy`, `NotchMotion.phaseFade` for the phase cross-fade.

## What each surface now uses

- **Stem** — untouched pure black (`.fill(.black)`). Camera-housing illusion intact.
- **Body (expanded + activity)** — `bodyGlass(_:)` in `NotchHUDView`: dark-glass
  `.regularMaterial` over the black base, a faint diagonal phase tie (0.13), a phase
  glow that fades out by 55% height (behind the timer, clear of the task rows), and a
  `dsHairline` ring on the body's exact silhouette (`bodyTopRadius` top corners,
  `cornerRadius` bottom). Guarded to `body.height > 8`, so `idle`/`live` stay pure black.
- **Timer row** — `dsTimer(26)` clock, phase-label on `dsSecondary` (tracking 1.2),
  glass circle controls, `dsHairline` divider.
- **Task rows** — checkbox/title/play on the text ramp; active row carries the phase
  gradient fill + hairline; the running row's play/pause takes `phase.glow`.
  `Color.green` kept for the done checkmark (the app's done semantic, as in
  `TodayPanelView`/`MenuBarView`).
- **Ears** — `dsTimer(13)` time, `dsSecondary` task label, phase dot + gradient
  progress line unchanged.
- **Announcement** — sits on the glass body automatically; icon on `phase.glow`,
  message on `dsPrimary`.
- **Quick actions** — glass chips. **Status strip** — streak on `dsSecondary`;
  blocking kept `.orange` (the app's warning semantic, as with today/planned).

## Confirmation no geometry moved (how I checked)

Rendered a true HEAD baseline (via `git stash`) and diffed against the change:

- `notch-idle.png` is **byte-identical** (md5 match) — the flat-state render path is
  untouched.
- The island's **non-grey bounding box is pixel-identical** in every wide state:
  `notch-expanded (16,0,695,597)`, `notch-activity (56,0,655,161)`,
  `notch-live (0,0,711,81)`, `notch-expanded-full (…,657)`, `notch-expanded-empty (…,421)`.
  Same silhouette, same top-of-menu-bar body start, same computed heights at 5 rows
  and 0 rows → the height formula and the hit-test mask are unaffected.

The 4-row expanded (vs the stale 3-row shots in `/private/tmp/native-preview/`) is
HEAD's task-list behavior — present in the baseline too — not this change.

Fixed sizes I deliberately kept to preserve measured constants: the 9pt FOCUS label
(`caption2` would grow the 51pt timer row), the 12pt task title, the 14pt/12pt
announcement, the 26pt control frame, the 24pt chip height. These took the token
*treatment* (rounded, tracking, color ramp) but not a new pixel size. The ear clock
moved 12→13pt — inside the fixed 78pt ear frame, no silhouette/mask impact.

## What the previews show

- **expanded** — blue-violet focus dark-glass body, glow behind the `10:00` clock
  fading before the tasks; glass circle controls with hairline rings; glass action
  chips; "Ship landing page v1" active row phase-tinted with a hairline. Reads as the
  popover, seen through the notch.
- **live** — `dsTimer` ear clock, phase dot, blue gradient progress line; ears black
  in the menu-bar row.
- **activity** — glass body + hairline, phase-glow, phase-colored cup icon.
- **idle** — pure black hardware lip, unchanged.

## Doubt

- The `activity` shot shows a *blue* body while saying "Break time" only because the
  preview harness seeds `phase = .focus`; at runtime a break sets the phase and the
  glow/icon go green. Harness data, not a bug — left as-is (out of scope).
- `.regularMaterial` renders in `ImageRenderer` as a translucent grey glass here; on
  real hardware it samples the desktop for true vibrancy, exactly like the popover.
