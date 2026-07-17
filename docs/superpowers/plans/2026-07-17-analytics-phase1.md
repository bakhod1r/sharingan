# Analytics Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Per-session focus log + Focus/Consistency scores + GitHub-style heatmap + focus-load chart, surfaced on a new Analytics page.

**Architecture:** `PomodoroTimer` posts a `.sessionDidEnd` notification for every finished/abandoned session; `SharinganCoordinator` enriches it with task attribution and appends to a JSON-file `FocusSessionLog`. Pure `AnalyticsEngine` computes scores/loads from `[SessionRecord]`. New `AppSection.analytics` renders `AnalyticsView` (Overview / Heatmap / Focus load tabs).

**Tech Stack:** Swift 5.10, SwiftUI, Swift Charts (already used in StatsChartView), XCTest. No new dependencies.

## Global Constraints

- macOS 14+, menu-bar app; follow DS (DesignSystem.swift) styling and existing view idioms.
- Defensive Codable decoding (never reset user data on new fields) — mirror `PomodoroStats.init(from:)`.
- Log writes must never block or crash the timer (1.7.3 principle).
- Version this phase as **1.8.0**: CHANGELOG entry, Info.plist (Resources/Info.plist CFBundleShortVersionString), TECHNICAL.md version + feature docs. No git tag.
- Concurrent agent sessions may share the checkout: `git add` with explicit pathspecs only.
- Commit + push after each completed task (multi-Mac workflow).

---

### Task 1: SessionRecord model + FocusSessionLog store

**Files:**
- Create: `Sources/SharinganCore/Models/SessionRecord.swift`
- Create: `Sources/SharinganCore/Services/FocusSessionLog.swift`
- Test: `Tests/SharinganTests/SessionLogTests.swift` (Tests dir is flat under the single test target — match neighbors)

**Interfaces (Produces):**
```swift
public struct SessionRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var start: Date
    public var end: Date
    public var phase: PomodoroPhase        // .focus / .shortBreak / .longBreak
    public var completed: Bool             // false = skipped/stopped
    public var taskID: UUID?
    public var subtaskID: UUID?
    public var taskTitle: String?
    public var plannedSeconds: TimeInterval
    public var appUsage: [String: TimeInterval]   // empty in phase 1
    public init(id: UUID = UUID(), start: Date, end: Date, phase: PomodoroPhase,
                completed: Bool, taskID: UUID? = nil, subtaskID: UUID? = nil,
                taskTitle: String? = nil, plannedSeconds: TimeInterval,
                appUsage: [String: TimeInterval] = [:])
    public var seconds: TimeInterval { end.timeIntervalSince(start) }
}

@MainActor public final class FocusSessionLog: ObservableObject {
    public static let shared = FocusSessionLog()
    @Published public private(set) var records: [SessionRecord]
    public init(fileURL: URL? = nil)      // nil → Application Support default
    public func append(_ r: SessionRecord)          // saves async, trims >400 days
    public func sessions(on day: Date) -> [SessionRecord]
    public func sessions(in interval: DateInterval) -> [SessionRecord]
    public func daysWithData() -> Set<Date>          // start-of-day keys
}
```

Storage: JSON array file `focus-sessions.json` next to the app's other container data (resolve via the same Application Support directory TaskDatabase/WidgetSnapshotStore use — check `TaskDatabase.swift` for the exact base-dir helper and reuse it). Load on init; corrupt file → rename to `focus-sessions.corrupt.json`, start empty. `append` mutates `records`, then writes on a background queue (fire-and-forget, log failures with `os_log`). Decoding uses `decodeIfPresent` per field with sensible defaults (`appUsage` ?? [:], `completed` ?? true).

**Steps:**
- [ ] Write failing tests: round-trip append/load with a temp-file URL; corrupt-file recovery; `sessions(on:)` day filtering incl. a midnight-spanning record (bucketed by its **start** day); decode of a JSON blob missing `appUsage`/`completed` keys; 400-day trim.
- [ ] Run `swift test --filter SessionLogTests` — expect FAIL (types missing).
- [ ] Implement model + store.
- [ ] `swift test --filter SessionLogTests` — PASS; run full `swift test` for regressions.
- [ ] Commit: `feat(analytics): per-session focus log (SessionRecord + FocusSessionLog)` — explicit pathspecs.

### Task 2: Timer emits sessionDidEnd; coordinator appends with attribution

**Files:**
- Modify: `Sources/SharinganCore/Services/PomodoroTimer.swift`
- Modify: `Sources/SharinganCore/Services/SharinganCoordinator.swift`
- Test: `Tests/SharinganTests/SessionLogTests.swift` (extend)

**Interfaces:**
- Produces: `Notification.Name.sessionDidEnd` posted by `PomodoroTimer` with userInfo `["record": SessionRecord]` — record carries phase/start/end/completed/plannedSeconds, **no task fields** (coordinator fills those).
- Consumes: Task 1's `FocusSessionLog.shared.append`.

Timer changes: add `private var sessionStartDate: Date?` set in `start()` (only when beginning fresh, not resuming from pause — keep the original date across pause/resume via `if sessionStartDate == nil`). Post the notification from three exits, then clear `sessionStartDate`:
- `phaseComplete` path (where `registerFocusCompletion` runs, line ~381): completed = true.
- `skip()` and `stop()`: completed = false; only post when elapsed ≥ 60s (ignore fat-finger starts). Mirrored sessions (`isMirroredSession`) never post — the owner Mac logs them.

Coordinator: in `wireUp` (alongside the existing `.phaseDidComplete` observer), observe `.sessionDidEnd`; for focus records attach the current focus target (same source `incrementPomodoro` uses — the focus target/queue state around line ~693) as taskID/subtaskID/title snapshot; append to `FocusSessionLog.shared`.

**Steps:**
- [ ] Extend tests: a timer driven through a synthetic short session posts `.sessionDidEnd` with completed=true on completion and false on skip after ≥60s elapsed (use the same timer-driving technique as `PomodoroModelsTests`/`ActiveTimerRecordTests` — check them first).
- [ ] Run tests — FAIL.
- [ ] Implement; run `swift test` fully — PASS.
- [ ] Commit: `feat(analytics): record every session into FocusSessionLog`.

### Task 3: AnalyticsEngine — scores + focus load (pure)

**Files:**
- Create: `Sources/SharinganCore/Models/AnalyticsEngine.swift`
- Test: `Tests/SharinganTests/AnalyticsEngineTests.swift`

**Interfaces (Produces):**
```swift
public enum AnalyticsEngine {
    /// nil when the day has no focus sessions.
    public static func focusScore(sessions: [SessionRecord], dailyGoal: Int,
                                  focusMinutes: Int) -> Int?
    public static func consistencyScore(sessions: [SessionRecord],
                                        recentDays: [[SessionRecord]],  // prior days for median start hour
                                        plannedDone: Int, plannedTotal: Int,
                                        streakDays: Int) -> Int?
    /// 24 buckets of focus seconds for one day's sessions.
    public static func hourlyLoad(sessions: [SessionRecord]) -> [TimeInterval]
}
```

Focus score weights (0–100): minutes vs goal 40 (goal = dailyGoal>0 ? dailyGoal×focusMinutes : 8×focusMinutes, capped at 1.0), completion ratio 25, break compliance 20 (breaks completed / breaks offered; no breaks offered ⇒ full credit), deep blocks 15 (longest run of consecutive completed focus sessions / 4, capped). Consistency: planned-task ratio 40 (plannedTotal==0 ⇒ neutral 0.7), start-hour regularity 30 (first focus start within ±1h of median of recentDays' first starts ⇒ 1.0, linear falloff to 0 at ±4h; <3 prior days ⇒ neutral 0.7), streak 30 (min(streakDays,7)/7). `hourlyLoad` splits sessions across hour boundaries proportionally.

**Steps:**
- [ ] Failing tests: empty day ⇒ nil; all-completed goal-met day ⇒ ≥90; all-abandoned ⇒ low (<40); hourlyLoad splits a 10:30–11:30 focus 50/50 between buckets 10 and 11; consistency neutral paths.
- [ ] FAIL → implement → `swift test` PASS.
- [ ] Commit: `feat(analytics): Focus & Consistency score engine + hourly load`.

### Task 4: Analytics section + AnalyticsView skeleton with Overview

**Files:**
- Modify: `Sources/Sharingan/Views/AppRouter.swift` (add `case analytics` to `AppSection`, title "Analytics", icon `"gauge.with.needle"`, ordered after `.stats`)
- Modify: `Sources/Sharingan/Views/MainWindowView.swift` (sidebar renders CaseIterable automatically — verify; add `case .analytics:` to `detail` using `detailScaffold(title: "Analytics")`)
- Create: `Sources/Sharingan/Views/AnalyticsView.swift`

Overview tab: segmented tab picker (match existing chip/segment idiom in StatsChartView), two score gauges (reuse ring-drawing style from CountdownRing at small scale or a simple `Circle().trim` gauge with DS accent), score computed live from `FocusSessionLog.shared` + `timer.settings.dailyPomodoroGoal` + `timer.stats.streak.currentStreak`; planned counts from `TaskStore.shared` today's tasks. "No data yet" empty state when scores are nil. Heatmap/Focus-load tabs stubbed with the empty state (filled in Tasks 5–6).

**Steps:**
- [ ] Add section + view; `swift build` clean.
- [ ] Runtime check via `verify` skill flow (build & launch, open Analytics page, screenshot).
- [ ] Commit: `feat(analytics): Analytics page with Focus/Consistency overview`.

### Task 5: Heatmap tab

**Files:**
- Create: `Sources/Sharingan/Views/AnalyticsHeatmapView.swift`
- Modify: `Sources/Sharingan/Views/AnalyticsView.swift` (mount it)
- Test: `Tests/SharinganTests/AnalyticsEngineTests.swift` (extend: grid mapper)

GitHub-style grid: 52×7 `LazyHGrid`-style layout (weeks as columns, Mon-first rows, month labels on top), fed from `timer.stats.history` (`PomodoroStats.recentDays(364)`), 5-step opacity scale of the theme accent (0 = faint fill). Pure helper `heatmapWeeks(days:) -> [[DailyCount?]]` in AnalyticsEngine (unit-tested: pads leading days, Monday-first) so the view stays dumb. Hover/click sets a selected day showing "N pomodoro · date" caption.

**Steps:**
- [ ] Failing test for `heatmapWeeks` padding/order → implement → PASS.
- [ ] Build, runtime screenshot check.
- [ ] Commit: `feat(analytics): GitHub-style yearly heatmap`.

### Task 6: Focus load tab

**Files:**
- Create: `Sources/Sharingan/Views/AnalyticsLoadView.swift`
- Modify: `Sources/Sharingan/Views/AnalyticsView.swift` (mount it)

Swift Charts `AreaMark` over `AnalyticsEngine.hourlyLoad` for a selected day (day pager ◀ ▶ like ReportView's), plus a `LineMark` overlay of the 30-day average per hour (from `sessions(in:)`). Empty state when the day has no sessions. X axis 0–24h, y minutes.

**Steps:**
- [ ] Build, runtime screenshot check (drive a fake session via sharingan:// per `verify` skill so the chart has data).
- [ ] Commit: `feat(analytics): focus load chart (diqqat cho'qqilari)`.

### Task 7: Version + docs + ship

**Files:**
- Modify: `CHANGELOG.md` (1.8.0 entry: session log, scores, heatmap, focus load, Analytics page)
- Modify: `Resources/Info.plist` (CFBundleShortVersionString → 1.8.0)
- Modify: `docs/TECHNICAL.md` (version 1.8.0 + new "Analytics" section documenting all of the above)

**Steps:**
- [ ] Full `swift test` + `swift build` PASS; runtime verify pass.
- [ ] Commit: `feat(analytics): 1.8.0 — Focus Score, Consistency, heatmap, focus load` + push.
