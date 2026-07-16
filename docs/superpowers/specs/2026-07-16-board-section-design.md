# Board section — Weekly + Jira tabs (design)

Date: 2026-07-16 · Branch: `jira` · Target version: 1.8.0

## Goal

Rename the sidebar's **Week** section to **Board** and give it two tabs:
**Weekly** (the existing 7-day board) and **Jira** (the sprint board that
currently opens as a sheet from Tasks). One place for both boards; the sheet
goes away.

## Current state

- `AppSection.week` in `AppRouter.swift` → `WeeklyBoardView(timer:)` rendered
  full-width in `MainWindowView.detail`.
- `JiraBoardView` opens as a `.sheet(isPresented: $showJiraBoard)` from
  `TasksView` (button at TasksView.swift:572), model created per-open via
  `AppServices.jiraService?.makeBoardModel()`.
- `JiraBoardView` was deliberately shaped after `WeeklyBoardView` (same column
  width, drag idiom), so they sit naturally in one section.

## Design

### Sidebar
- Section label: `Week` → `Board`; icon `calendar` → `rectangle.split.3x1`.
- `AppSection` case stays `.week` (avoids touching persisted selection and
  deep-link wiring); only `title`/`icon` change.

### Board section body
- A segmented control (design-system styled, matching existing view-bar
  controls) at the top: **Weekly** | **Jira**.
- Weekly tab: `WeeklyBoardView(timer:)` unchanged.
- Jira tab: `JiraBoardView` embedded full-width (same padding as Weekly).
- Last-selected tab persists in `UserDefaults` (`board.tab`).
- Jira not connected (`AppServices.jiraService == nil` or no
  `boardProjectKey`): the Jira tab still shows, with a "Connect Jira in
  Settings" empty state (button deep-links to Settings).

### Model lifecycle
- The board section holds one `JiraBoardModel` created lazily on first switch
  to the Jira tab (`makeBoardModel()`), kept for the window's lifetime so tab
  switches don't refetch (`.task(id:)` + `phase == .idle` guard already
  handles this).
- If Jira connects/disconnects while the window is open, the tab re-resolves
  the service on next appearance.

### Tasks view cleanup
- The board button in TasksView no longer opens a sheet — it routes to the
  Board section's Jira tab via `AppRouter` (add a `pendingBoardTab` deep-link
  following the existing pending-* pattern).
- Remove `showJiraBoard` state and the sheet.

### Out of scope
- Menu-bar popover's Week tab keeps its name and content (weekly only).
- No changes to `JiraBoardView` internals or `JiraBoardModel`.

## Versioning / docs
- CHANGELOG 1.8.0 entry, Info.plist + TECHNICAL.md version bump,
  TECHNICAL.md sections for the Board section and the moved Jira board.

## Testing
- Unit: deep-link routing to the Jira tab; tab persistence default.
- Manual (`/verify`-style): switch tabs, drag on both boards, disconnected
  Jira state, Tasks button routes correctly.
