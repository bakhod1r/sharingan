# Premium UI Animations — Design

**Date:** 2026-07-10
**Scope:** App-wide UI animation pass (menu bar, main window, settings, floating timer, stats, tasks). Explicitly OUT of scope: Sharingan eye rendering (MoveEyesView/BreakView pattern work — separate in-flight effort).

## Goal

Make the whole app move with one consistent, premium "hand": shared motion tokens, no janky static surfaces, animated window presentation, and a few celebratory hero moments — all honoring Reduce Motion.

## Platform

Bump `Package.swift` platforms from `.macOS(.v13)` to `.macOS(.v14)` to unlock `symbolEffect`, `phaseAnimator`, `keyframeAnimator`. The app already uses back-deployed v14-era APIs (`.snappy`, `.contentTransition(.numericText())`).

## 1. Motion foundation — `DS.Motion` (DesignSystem.swift)

New token namespace alongside the existing `DS.Radius`/`DS.Space`:

- `DS.Motion.snappy` — `.snappy(duration: 0.3)`: numeric counters, small state flips.
- `DS.Motion.standard` — `.spring(response: 0.35, dampingFraction: 0.85)`: tab switches, list insert/remove, layout moves.
- `DS.Motion.gentle` — `.easeInOut(duration: 0.25)`: fades, disclosures, section cross-fades.
- `DS.Motion.hover` — `.easeOut(duration: 0.15)`: hover highlights, press states.
- `DS.Motion.celebrate` — `.bouncy(duration: 0.45)`: streak/completion moments.

Migrate existing inline timings in MenuBarView, MenuBarWeekView, MainWindowView, TasksView, WeeklyBoardView, StatsChartView, SettingsView, FloatingTimerView, GlassComponents to these tokens. Values may shift a few hundredths toward the token value — visual parity, not pixel parity, is the bar.

## 2. Janky-spot fixes

- **CountdownRing.swift** — the trim arc currently steps once per second. Drive progress through a `TimelineView(.animation)`-based interpolation (same pattern FloatingTimerView already uses) so the arc sweeps continuously. Pauses/resets stay instant-correct.
- **StatsExtrasView.swift** — add `.contentTransition(.numericText())` + `DS.Motion.snappy` to all numeric values and the streak record row (matches StatsSummary/StatsChart).
- **StreakBadgeView.swift** — animate the progress-bar fill (`DS.Motion.standard`) and the streak count (`numericText`).
- **TaskEditorView.swift** — inspected during planning: its only stateful toggle is the custom-due-date `popover`, which macOS animates itself. No custom motion needed; excluded from the plan.

## 3. Hero moments

- **Window presentation** — MainWindowManager, FloatingWindowManager, QuickAddWindowManager currently `makeKeyAndOrderFront` with zero motion. Add a shared AppKit helper: on show, fade in (alpha 0→1) with a subtle scale-in (frame 0.97→1.0, anchored center) over ~0.22s; on close, fade out over ~0.15s then order out. Respects Reduce Motion (instant show/hide).
- **Task completion** — checkmark gets `.symbolEffect(.bounce)` on completion toggle; row briefly tints toward the accent before the removal transition.
- **Streak flame** — `.symbolEffect(.bounce)` when the streak count increases.
- **Run button** — icon bounce on press (CircularRunButton).

## 4. Reduce Motion

All new animations, and existing `repeatForever` loops (MenuBarView breathing, WeeklyBoard hover scale, etc.), gate on `accessibilityReduceMotion`. `DS.Motion` ships a helper so views don't hand-roll the check.

## Error handling / risk

Pure presentation layer — no data-model changes. Worst case is a visual regression; each surface is independently revertable. Window-presentation helper must not change key/focus behavior (`makeKeyAndOrderFront` semantics preserved; only alpha/frame animate).

## Testing

- `swift build` clean after the platform bump.
- Rebuild the app bundle and visually verify: menu bar popover, main window sections, floating timer, quick-add, settings, stats, task complete, streak badge.
- Toggle System Settings → Reduce Motion and confirm loops/entrances go static.
