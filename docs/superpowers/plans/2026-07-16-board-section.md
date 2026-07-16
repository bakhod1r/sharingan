# Board Section (Weekly + Jira tabs) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the sidebar's Week section to **Board** with two tabs — **Weekly** (existing 7-day board) and **Jira** (the sprint board, moved out of its TasksView sheet).

**Architecture:** `AppSection.week` keeps its case name (persisted selection + wiring untouched); only its `title`/`icon` change. A new `BoardSectionView` hosts a `GlassSegmentedPicker` over the two boards, persists the tab in `@AppStorage("board.tab")`, and lazily creates one `JiraBoardModel` on first Jira-tab visit. TasksView's board button becomes an `AppRouter.openBoard(tab: .jira)` deep-link; the sheet is deleted.

**Tech Stack:** SwiftUI (macOS 14+), SwiftPM. Note: unit tests can only import `SharinganCore` (`@testable import SharinganCore`); `Sharingan` is an executable target and **cannot be imported by tests** — view/router changes are verified by `swift build` + manual run.

**Spec:** `docs/superpowers/specs/2026-07-16-board-section-design.md`

## Global Constraints

- Version bump to **1.8.0** (CHANGELOG, `Resources/Info.plist`, `docs/TECHNICAL.md`).
- Menu-bar popover's Week tab is **out of scope** — name and content unchanged.
- No changes to `JiraBoardView` internals or `JiraBoardModel`.
- Every commit: `swift build` passes; run `swift test` before the final commit.
- Commit messages end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`; push after each commit (multi-Mac workflow).

---

### Task 1: AppRouter — rename section, add Board deep-link

**Files:**
- Modify: `Sources/Sharingan/Views/AppRouter.swift`

**Interfaces:**
- Produces: `enum BoardTab: String { case weekly, jira }` (top-level, in AppRouter.swift), `AppRouter.pendingBoardTab: BoardTab?`, `AppRouter.openBoard(tab: BoardTab?)`.

- [ ] **Step 1: Change the section's title and icon**

In `AppSection.title`, change:

```swift
        case .week:     return "Board"
```

In `AppSection.icon`, change:

```swift
        case .week:     return "rectangle.split.3x1"
```

- [ ] **Step 2: Add the BoardTab enum and deep-link**

Below the `AppSection` enum (before `AppRouter`), add:

```swift
/// The two boards inside the Board section. RawValue is persisted
/// (`board.tab` default), so cases must stay stable.
enum BoardTab: String, CaseIterable, Identifiable, Hashable {
    case weekly, jira
    var id: String { rawValue }
    var title: String {
        switch self {
        case .weekly: return "Weekly"
        case .jira:   return "Jira"
        }
    }
}
```

Inside `AppRouter`, after `openTaskImport` (line ~50), add:

```swift
    /// One-shot "land the Board section on this tab" — set by the Tasks
    /// view-bar's Jira button, consumed by BoardSectionView like the filters.
    @Published var pendingBoardTab: BoardTab?
```

After `revealTask`, add:

```swift
    /// Jump to the Board section, optionally landing on a specific tab.
    func openBoard(tab: BoardTab? = nil) {
        pendingBoardTab = tab
        section = .week
    }
```

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | tail -5` — expect `Build complete!`

- [ ] **Step 4: Commit & push**

```bash
git add Sources/Sharingan/Views/AppRouter.swift
git commit -m "feat(board): rename Week section to Board, add openBoard deep-link

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push
```

---

### Task 2: BoardSectionView — tabbed host for the two boards

**Files:**
- Create: `Sources/Sharingan/Views/BoardSectionView.swift`
- Modify: `Sources/Sharingan/Views/MainWindowView.swift:883-889` (the `.week` case)

**Interfaces:**
- Consumes: `BoardTab`, `AppRouter.pendingBoardTab` (Task 1); `GlassSegmentedPicker` (GlassControls.swift); `WeeklyBoardView(timer:)`; `JiraBoardView(model:projectKey:accent:)`; `AppServices.jiraService` (`makeBoardModel()`, `boardProjectKey`, `isConnected`); `AppRouter.shared.openSettings()`.
- Produces: `BoardSectionView(timer: PomodoroTimer)`.

- [ ] **Step 1: Create the view**

```swift
import SwiftUI
import SharinganCore

/// The Board section: a segmented picker over the two boards — the local
/// weekly planner and the Jira sprint board (formerly a sheet in Tasks).
/// The Jira model is created once on first visit and kept for the window's
/// lifetime so tab switches don't refetch (`JiraBoardView`'s `.task` guard
/// only loads while `phase == .idle`).
struct BoardSectionView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var router = AppRouter.shared

    /// Last-selected tab, restored across launches.
    @AppStorage("board.tab") private var tabRaw = BoardTab.weekly.rawValue
    private var tab: BoardTab { BoardTab(rawValue: tabRaw) ?? .weekly }

    /// Created lazily on the first switch to the Jira tab; nil while
    /// disconnected (the tab then shows the connect hint instead).
    @State private var jiraModel: JiraBoardModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GlassSegmentedPicker(
                selection: Binding(get: { tab },
                                   set: { tabRaw = $0.rawValue }),
                cases: BoardTab.allCases, label: \.title)
                .frame(width: 220)

            switch tab {
            case .weekly:
                WeeklyBoardView(timer: timer)
            case .jira:
                jiraBoard
            }
        }
        .onAppear(perform: consumeDeepLink)
        .onChange(of: router.pendingBoardTab) { consumeDeepLink() }
    }

    @ViewBuilder
    private var jiraBoard: some View {
        if let model = jiraModel,
           let project = AppServices.jiraService?.boardProjectKey {
            JiraBoardView(model: model, projectKey: project,
                          accent: timer.settings.theme.accent)
        } else {
            connectHint
        }
    }

    /// Shown while Jira is disconnected (or has no browsable project).
    private var connectHint: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.split.3x1")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.dsTertiary)
            Text("Connect Jira in Settings to see your sprint board.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.dsSecondary)
            Button("Open Settings") { AppRouter.shared.openSettings() }
                .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .onAppear(perform: resolveJiraModel)
    }

    /// Applies a pending deep-link tab, then re-resolves the Jira model so a
    /// connection made while the window was open is picked up.
    private func consumeDeepLink() {
        if let pending = router.pendingBoardTab {
            tabRaw = pending.rawValue
            router.pendingBoardTab = nil
        }
        if tab == .jira { resolveJiraModel() }
    }

    private func resolveJiraModel() {
        if jiraModel == nil {
            jiraModel = AppServices.jiraService?.makeBoardModel()
        }
    }
}
```

- [ ] **Step 2: Wire it into MainWindowView**

Replace the `.week` case body (MainWindowView.swift:883-889):

```swift
        case .week:
            // Full-width — the boards manage their own horizontal layout
            // rather than the width-capped scaffold used by the other sections.
            BoardSectionView(timer: timer)
                .padding(.horizontal, 28)
                .padding(.top, 32)
                .padding(.bottom, 24)
```

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | tail -5` — expect `Build complete!`

- [ ] **Step 4: Manual smoke check**

Run the app (`make run` or the `verify` skill): sidebar shows **Board** with the split-rectangle icon; segmented picker switches Weekly ⇄ Jira; Jira tab shows the sprint board when connected, the "Connect Jira in Settings" hint (button jumps to Settings) when not; tab choice survives relaunch.

- [ ] **Step 5: Commit & push**

```bash
git add Sources/Sharingan/Views/BoardSectionView.swift Sources/Sharingan/Views/MainWindowView.swift
git commit -m "feat(board): Board section hosts Weekly and Jira boards behind tabs

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push
```

---

### Task 3: TasksView — route to the Board tab, drop the sheet

**Files:**
- Modify: `Sources/Sharingan/Views/TasksView.swift` (state ~line 48, sheet ~lines 156-166, button ~line 572)

**Interfaces:**
- Consumes: `AppRouter.shared.openBoard(tab: .jira)` (Task 1).

- [ ] **Step 1: Remove the sheet state and modifier**

Delete line 48:

```swift
    @State private var showJiraBoard = false
```

Delete the whole `.sheet(isPresented: $showJiraBoard) { … }` modifier (lines 156-166).

- [ ] **Step 2: Repoint the button**

In `jiraBoardToggle` (~line 572), change the action and help text:

```swift
            Button { AppRouter.shared.openBoard(tab: .jira) } label: {
```

and

```swift
            .help("Jira sprint board — opens the Board section")
```

(the `isConnected` guard, icon, and accessibility label stay as they are).

- [ ] **Step 3: Build & full test run**

Run: `swift build 2>&1 | tail -5` — expect `Build complete!`
Run: `swift test 2>&1 | tail -5` — expect all tests pass (no test imports the app target, so this guards against SharinganCore regressions only).

- [ ] **Step 4: Manual check**

In the app: Tasks → the split-rectangle button now lands on Board section, Jira tab selected.

- [ ] **Step 5: Commit & push**

```bash
git add Sources/Sharingan/Views/TasksView.swift
git commit -m "feat(board): Tasks Jira button deep-links to the Board section

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push
```

---

### Task 4: Version bump + docs

**Files:**
- Modify: `CHANGELOG.md`, `Resources/Info.plist:18`, `docs/TECHNICAL.md`

- [ ] **Step 1: CHANGELOG**

Under `## [Unreleased]` insert:

```markdown
## [1.8.0] — 2026-07-16

### Changed
- The sidebar's **Week** section is now **Board**, with two tabs: **Weekly**
  (the 7-day planner, unchanged) and **Jira** (the sprint board, previously a
  sheet opened from Tasks). The last-used tab is remembered; while Jira is
  disconnected the tab shows a "Connect Jira in Settings" hint.
- The Jira board button in the Tasks view bar now jumps to Board → Jira
  instead of opening a sheet.
```

- [ ] **Step 2: Info.plist**

`Resources/Info.plist` line 18: `<string>1.7.0</string>` → `<string>1.8.0</string>`.

- [ ] **Step 3: TECHNICAL.md**

- Header: `- Version: 1.6.1` → `- Version: 1.8.0` (it's stale; set it to the new version).
- The **Weekly board** bullet (~line 58): append `Lives in the **Board** section (sidebar), alongside the Jira sprint board tab; the last-used tab is remembered (`board.tab` default).`
- In the Jira "Status & board" paragraph (~line 739): replace the sheet description — the sprint board now lives in the **Board** section's Jira tab (`BoardSectionView`), the Tasks view-bar button deep-links there (`AppRouter.openBoard(tab: .jira)`), and a disconnected state shows a connect-in-Settings hint.

- [ ] **Step 4: Commit & push**

```bash
git add CHANGELOG.md Resources/Info.plist docs/TECHNICAL.md
git commit -m "docs(board): CHANGELOG 1.8.0, version bump, TECHNICAL.md Board section

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push
```
