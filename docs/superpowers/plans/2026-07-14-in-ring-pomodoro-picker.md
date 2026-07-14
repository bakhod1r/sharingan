# In-Ring Pomodoro Size Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** While the timer is idle, the main window's ring shows a Small/Normal/Big
pomodoro-size picker in place of the "Focus" phase label.

**Architecture:** One computed property on `PomodoroTimer` names the visibility
rule (`isIdleAtFocus`); `TimerDetailView` swaps its phase label for a chip row
off that flag. Chips call the existing `applyKind`, which already refreshes the
idle countdown. No new state or persistence.

**Tech Stack:** SwiftUI, swift-testing (`@Test`/`#expect`), SwiftPM.

**Spec:** `docs/superpowers/specs/2026-07-14-in-ring-pomodoro-picker-design.md`

## Global Constraints

- macOS 14+, pure SwiftPM — no Xcode project.
- Version for this feature: **1.20.0** (CHANGELOG + `Resources/Info.plist` + `docs/TECHNICAL.md`) — re-check `CHANGELOG.md` at commit time; a parallel session may have taken 1.20.0, then use the next free minor.
- Parallel agents share this checkout: `git add` with **explicit pathspecs only** (never `-A`/`-a`), and `docs/` needs `git add -f` (gitignored wholesale).
- Do not touch `site/*` or the parallel agent's uncommitted `docs/TECHNICAL.md` hunks — TECHNICAL.md edits are ours only if staged as a synthetic blob (see Task 3, Step 4).

---

### Task 1: `PomodoroTimer.isIdleAtFocus`

**Files:**
- Modify: `Sources/SharinganCore/Services/PomodoroTimer.swift` (next to `applyKind`, ~line 180)
- Test: `Tests/SharinganTests/IdleAtFocusTests.swift` (new)

**Interfaces:**
- Consumes: existing `PomodoroTimer` API — `start()`, `pause()`, `skip()`, `stop()`, `phase`, `isRunning`.
- Produces: `public var isIdleAtFocus: Bool` on `PomodoroTimer` — Task 2's view reads exactly this name.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import SharinganCore

/// Visibility rule for the main window's in-ring size picker: it shows only
/// while nothing is in flight and the pending phase is a focus.
@Suite("Idle-at-focus (in-ring picker visibility)")
struct IdleAtFocusTests {

    @MainActor private func makeTimer(autoStartBreak: Bool = true) -> PomodoroTimer {
        let t = PomodoroTimer()
        var s = PomodoroSettings()
        s.autoStartBreak = autoStartBreak
        t.settings = s
        t.stop()
        return t
    }

    @MainActor @Test func freshTimerIsIdle() {
        let t = makeTimer()
        #expect(t.isIdleAtFocus)
    }

    @MainActor @Test func runningFocusIsNotIdle() {
        let t = makeTimer()
        t.start()
        #expect(!t.isIdleAtFocus)
        t.stop()
    }

    @MainActor @Test func pausedIsNotIdle() {
        let t = makeTimer()
        t.start()
        t.pause()
        #expect(!t.isIdleAtFocus)
        t.stop()
    }

    @MainActor @Test func pendingBreakIsNotIdle() {
        let t = makeTimer(autoStartBreak: false)
        t.start()
        t.skip()
        #expect(t.phase == .shortBreak)
        #expect(!t.isRunning)
        #expect(!t.isIdleAtFocus) // waiting at a break ≠ idle at focus
        t.stop()
    }

    @MainActor @Test func stopReturnsToIdle() {
        let t = makeTimer()
        t.start()
        t.pause()
        t.stop()
        #expect(t.isIdleAtFocus)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter IdleAtFocusTests`
Expected: compile error — `value of type 'PomodoroTimer' has no member 'isIdleAtFocus'`

- [ ] **Step 3: Implement the property**

In `Sources/SharinganCore/Services/PomodoroTimer.swift`, directly above
`applyKind` (keeps the kind-switching API together):

```swift
/// True while nothing is in flight and the pending phase is a focus — the
/// fresh/reset state. The main window shows the in-ring size picker exactly
/// then; any live state (running, paused, or waiting at a break) keeps the
/// phase label instead.
public var isIdleAtFocus: Bool { !isRunning && phase == .focus }
```

- [ ] **Step 4: Run to verify they pass**

Run: `swift test --filter IdleAtFocusTests`
Expected: 5 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/SharinganCore/Services/PomodoroTimer.swift Tests/SharinganTests/IdleAtFocusTests.swift
git commit -m "feat(core): isIdleAtFocus — named idle state for the in-ring size picker"
```

---

### Task 2: In-ring picker UI in `TimerDetailView`

**Files:**
- Modify: `Sources/Sharingan/Views/MainWindowView.swift:959-966` (the ring's inner `VStack`) and add a private builder below `runTapped()` (~line 1020)

**Interfaces:**
- Consumes: `timer.isIdleAtFocus` (Task 1), existing `timer.applyKind(_:)`,
  `timer.settings.config(for:)`, `timer.settings.theme.accent`, `PomodoroKind`
  (`label` / `systemImage` / `allCases`), `DS.Motion.snappy`, `.pressableSubtle`.
- Produces: UI only — nothing downstream consumes it.

- [ ] **Step 1: Swap the phase label for the conditional**

Replace the inner `VStack` of the ring `ZStack` (currently: time `Text` +
phase `Label`) with:

```swift
VStack(spacing: 8) {
    Text(timer.settings.timeFormat.string(remaining))
        .font(.dsTimer(76))
        .foregroundStyle(.white)
    if timer.isIdleAtFocus {
        ringKindPicker
    } else {
        Label(timer.phase.label, systemImage: timer.phase.systemImage)
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(.white.opacity(0.7))
    }
}
.animation(DS.Motion.snappy, value: timer.isIdleAtFocus)
```

- [ ] **Step 2: Add the `ringKindPicker` builder**

Below `runTapped()` in `TimerDetailView`:

```swift
/// Small / Normal / Big switch inside the ring — idle only. Mirrors the
/// sidebar selector (same applyKind semantics); while idle a tap also
/// refreshes the countdown to the new focus length.
private var ringKindPicker: some View {
    let accent = timer.settings.theme.accent
    let active = timer.settings.config(for: timer.settings.activeKind)
    return VStack(spacing: 6) {
        HStack(spacing: 5) {
            ForEach(PomodoroKind.allCases) { kind in
                let selected = timer.settings.activeKind == kind
                let cfg = timer.settings.config(for: kind)
                Button {
                    timer.applyKind(kind)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: kind.systemImage)
                            .font(.system(size: 10, weight: .semibold))
                        Text(kind.label)
                            .font(.system(.caption, design: .rounded).weight(.bold))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(selected ? accent.opacity(0.26)
                                                        : Color.white.opacity(0.07)))
                    .overlay(Capsule().stroke(selected ? accent.opacity(0.65) : Color.clear,
                                              lineWidth: 1))
                    .foregroundStyle(selected ? accent : Color.white.opacity(0.7))
                    .contentShape(Capsule())
                }
                .buttonStyle(.pressableSubtle)
                .help("\(kind.label): \(cfg.focusMinutes) min focus, \(cfg.breakMinutes) min break")
            }
        }
        Text("\(active.focusMinutes)′ + \(active.breakMinutes)′")
            .font(.system(size: 11, design: .rounded).weight(.medium))
            .foregroundStyle(.white.opacity(0.55))
    }
    .animation(DS.Motion.snappy, value: timer.settings.activeKind)
}
```

- [ ] **Step 3: Build + full test suite**

Run: `swift build && swift test`
Expected: build succeeds, all suites pass (488 tests: 483 existing + 5 new)

- [ ] **Step 4: Commit**

```bash
git add Sources/Sharingan/Views/MainWindowView.swift
git commit -m "feat(main-window): Small/Normal/Big picker inside the timer ring while idle"
```

---

### Task 3: Runtime verify, version 1.20.0, docs, push

**Files:**
- Modify: `CHANGELOG.md` (new 1.20.0 entry), `Resources/Info.plist` (1.19.2 → 1.20.0), `docs/TECHNICAL.md` (version line + Timer bullet — synthetic-blob staging, see Step 4)
- Commit (force-add): `docs/superpowers/specs/2026-07-14-in-ring-pomodoro-picker-design.md`, `docs/superpowers/plans/2026-07-14-in-ring-pomodoro-picker.md`

- [ ] **Step 1: Runtime verify via the project `verify` skill**

Invoke the `verify` skill and follow it (install via `Scripts/install.sh`,
launch from /Applications — never `open dist/...` while the widget matters).
Confirm: idle timer page shows the three chips + minutes caption; tapping Big
flips the countdown to 90:00; `sharingan://start` hides the chips and shows
"Focus"; `sharingan://reset` brings them back.

- [ ] **Step 2: CHANGELOG entry (re-check the next free version first)**

Run: `head -12 CHANGELOG.md` — if 1.20.0 is taken, shift to the next minor
everywhere below. Insert under `## [Unreleased]`:

```markdown
## [1.20.0] — 2026-07-14

### Added
- Timer page: while the timer is idle, the ring now hosts the Small / Normal /
  Big pomodoro switch (with the selected size's `focus′ + break′` caption) in
  place of the phase label — switch sizes without reaching for the sidebar.
  Once a session runs (or pauses, or waits at a break) the phase label returns.
```

- [ ] **Step 3: Bump Info.plist**

Run: `plutil -replace CFBundleShortVersionString -string "1.20.0" Resources/Info.plist`
(also update `Resources/Widget-Info.plist` to match — it's synced now, keep it so)

- [ ] **Step 4: TECHNICAL.md — version line + feature bullet, WITHOUT sweeping the parallel agent's dirty hunks**

Working tree holds another session's uncommitted TECHNICAL.md edits. Edit the
working file normally (version line → `1.20.0`, plus this bullet at the end of
the "## Timer / Pomodoro" list):

```markdown
- Main-window timer page: while idle, the ring hosts the Small/Normal/Big size switch (accent-tinted active chip + the selected size's lengths caption) instead of the phase label; a live/paused/pending-break session shows the label. Chips call the same `applyKind` as the sidebar selector, so both stay in sync and an idle tap refreshes the countdown instantly.
```

Then stage a synthetic blob = `HEAD:docs/TECHNICAL.md` + only these two edits:

```bash
git show HEAD:docs/TECHNICAL.md > /tmp/tech-head.md
# apply the same two edits to /tmp/tech-head.md (version line + bullet)
git hash-object -w /tmp/tech-head.md   # → <sha>
git update-index --add --cacheinfo 100644,<sha>,docs/TECHNICAL.md
```

- [ ] **Step 5: Commit + push**

```bash
git add Resources/Info.plist Resources/Widget-Info.plist CHANGELOG.md
git add -f docs/superpowers/specs/2026-07-14-in-ring-pomodoro-picker-design.md \
           docs/superpowers/plans/2026-07-14-in-ring-pomodoro-picker.md
git commit -m "feat(main-window): in-ring pomodoro size picker — 1.20.0"
git push origin main
```
