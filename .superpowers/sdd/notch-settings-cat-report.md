# Notch HUD → its own Settings category

## The new case and where it sits
`SettingsCategory` (Sources/SharinganCore/Models/SettingsCategory.swift) gains
`case notch`, declared **right after `timer`**:
`general, timer, notch, tasks, breaks, focus, eyeCare, sharingan, voice, shortcuts`.
Enum declaration order drives the sidebar order (root list iterates
`SettingsCategory.allCases`), so Notch HUD now sits directly under Timer.

Metadata:
- `title` → "Notch HUD"
- `subtitle` → "Island, ears, what it shows"
- `icon` → `rectangle.topthird.inset.filled` (SF Symbols 4; macOS 14 target, so
  available) — reads as a filled strip/island across the top of the screen.
- `tint` (SettingsView extension) → `.cyan` (distinct from Timer's `.blue`,
  free of the other categories' colors).
- `hasAdvancedRows` → `true` automatically (it's not General/Voice/Shortcuts),
  so the category gets its Advanced accordion. No per-category tier table
  exists beyond `hasAdvancedRows`; nothing else to seed.

## What moved
Everything notch-related left Timer and now lives under `.notch`:
- **Simple tier** (`categorySections(_:)`, new `case .notch`): the "Notch HUD"
  section — master "Show the notch HUD" toggle (`notchControls(requiresHUD:false)`),
  the description, the **Ears** picker (`notchControls { … }`, moved up from
  Advanced per the spec), and `notchUnavailableNote` last.
- **Advanced tier** (`advancedSections(_:)`, new `case .notch`): the "Notch HUD
  details" section — live-activity toggle, the divider, "What the panel shows"
  header, the four section toggles (Timer/controls, Today's tasks, Quick
  actions, Blocking & streak strip) and the 3–5 "Task rows" stepper (gated on
  `notchShowTasks`). Ears removed here (it moved to Simple). The
  "Turn the notch HUD on to configure it" hint and the no-double-note comment
  survive.

Timer is now clean: `categorySections`'s `.timer` ends at the "Menu bar"
section; `advancedSections`'s `.timer` ends at "Floating timer details". Verified
by awk-scanning the whole `.timer` region for `notch` — nothing left.

## Simple/Advanced split
Matches the neighbouring categories exactly: essentials in `categorySections`,
extras in `advancedSections`, each wrapped in the file's `Section(...)` helper,
same binding style (`$settings.notch…`), same `notchControls` grey/disable
wrapper. Split landed as specified — enable + ears Simple; live-activity + four
toggles + row count Advanced.

## Search re-routing
Timer's keyword list dropped `notch, island, hud, ears, camera housing,
menu bar` (and a duplicate trailing `countdown`); `.notch` now owns
`notch, island, dynamic island, hud, ears, camera housing, menu bar,
live activity`. `matches("notch")` etc. now return `.notch` and no longer
`.timer`. Timer keeps its own terms (floating, opacity, repeat, today panel, …).

## refresh() still fires
Untouched by the move. Notch settings reach `NotchWindowManager.shared.refresh()`
through the settings object, not the view: `NotchWindowManager.install(...)`
subscribes to `timer.objectWillChange` and calls `refreshIfSettingsChanged`;
mutating `$settings.notch*` (the same `PomodoroSettings` binding regardless of
which category page hosts the control) triggers that chain, plus the
`didChangeScreenParametersNotification` observer. The bindings are byte-for-byte
the same (`$settings.notchHUDEnabled`, `$settings.notchEars`, etc.), so the
refresh path is preserved.

## Tests
Tests/SharinganTests/SettingsCategoryTests.swift updated (TDD — written before
the source change):
- count 9 → **10**, General first, **notch immediately after timer**.
- search-routing: `notch, island, hud, ears, camera housing, menu bar` match
  `.notch` and do **not** match `.timer`.
- new: Timer keeps its own keywords; notch has non-empty label/subtitle/icon.
- `hasAdvancedRows` loop unchanged (notch → true).

## Build / test
- `swift build` — Build complete, clean.
- `swift test` — **386 tests in 45 suites passed** (was 384; +2 net from the
  new category tests). "Settings categories" suite green.

## Settings preview
`main.swift`'s `--render-dev-preview` was repointed from `initialCategory: .timer`
→ `.notch` (output renamed `settings-timer.png` → `settings-notch.png`). Rendered
on this notchless Mac: a standalone **Notch HUD** page, cyan top-strip icon, the
Simple "NOTCH HUD" section (master toggle, description, Ears = Both sides, and the
"This Mac has no notch. The HUD needs a MacBook with a camera housing." note), and
the Advanced "NOTCH HUD DETAILS" accordion (announce toggle, "What the panel
shows", four toggles + "5 rows" stepper). The entire category renders **disabled/
greyed** — exactly the state a notchless Mac shows and the one the user can verify
locally. I did not (and could not) see the notch HUD itself on this machine.

## Doubt
- `menu bar` moved to `.notch` per the spec's explicit list, even though Timer
  still has a "Show countdown in menu bar" toggle. That Timer feature stays
  discoverable via `countdown` (kept in Timer), so nothing is orphaned, but a
  user searching "menu bar" now lands on Notch HUD first. Flagging as a
  deliberate, spec-directed choice.
- Icon `rectangle.topthird.inset.filled` reads well in the render; if a more
  literal notch glyph is wanted it's a one-line swap.
