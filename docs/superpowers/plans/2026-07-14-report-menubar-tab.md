# Report as a Menu-Bar Popover Tab — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface the day-paged per-task focus Report (`ReportView`) as a fourth tab in the menu-bar popover, next to Timer / Tasks / Week.

**Architecture:** Pure view wiring — `MenuBarView`'s `Tab` enum, segmented `Picker`, and tab `switch` each gain one entry, and `ReportView` is reused unchanged (the same way the popover's Tasks tab reuses the main window's `TasksView`). Data flows from `TaskStore.shared`, so no store or timer changes. Verification is by the repo's headless dev-preview renders, not unit tests — there is no new logic to test.

**Tech Stack:** Swift / SwiftUI, SwiftPM (`swift build`), `--render-dev-preview` headless shots.

**Spec:** `docs/superpowers/specs/2026-07-14-report-menubar-tab-design.md`

## Global Constraints

- macOS 14+, SwiftPM CLI toolchain (no Xcode project) — build with `swift build`.
- Popover width stays 360pt for every tab except `.week` (which already widens itself). Do not touch the width logic.
- `ReportView` must be reused **unchanged** — no popover-specific fork of it.
- **Commit with explicit paths only** (`git add <file>…`, never `-A`/`.`): the working tree may carry unrelated in-progress work, and this repo has already had a WIP swept into a stranger's commit once.
- `/docs/` is in `.gitignore`; already-tracked files there (`docs/TECHNICAL.md`) stage normally, but any *new* file under `docs/` needs `git add -f`.
- Headless renders redirect `TaskStore.shared` to a throwaway SQLite automatically (argv seam in `HeadlessRender`) — no env var needed, and the render never touches the user's database.
- Commit messages end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: The Report tab

**Files:**
- Modify: `Sources/Sharingan/Views/MenuBarView.swift` (three edits: `Tab` enum ~line 30, `Picker` ~line 52, tab `switch` ~line 68)

**Interfaces:**
- Consumes: `ReportView(timer:)` (`Sources/Sharingan/Views/ReportView.swift`) — internal memberwise init, `timer: PomodoroTimer`; reads `TaskStore.shared` itself.
- Produces: `MenuBarView.Tab.report` — Task 2 photographs it; nothing else references it by name.

- [ ] **Step 1: Add the enum case**

In `Sources/Sharingan/Views/MenuBarView.swift`, change:

```swift
    private enum Tab: Hashable { case timer, tasks, week }
```

to:

```swift
    private enum Tab: Hashable { case timer, tasks, week, report }
```

- [ ] **Step 2: Add the segment**

In the same file's `body`, change:

```swift
            Picker("", selection: $tab) {
                Label("Timer", systemImage: "timer").tag(Tab.timer)
                Label("Tasks", systemImage: "checklist").tag(Tab.tasks)
                Label("Week", systemImage: "calendar").tag(Tab.week)
            }
```

to:

```swift
            Picker("", selection: $tab) {
                Label("Timer", systemImage: "timer").tag(Tab.timer)
                Label("Tasks", systemImage: "checklist").tag(Tab.tasks)
                Label("Week", systemImage: "calendar").tag(Tab.week)
                Label("Report", systemImage: "list.bullet.rectangle").tag(Tab.report)
            }
```

(`list.bullet.rectangle` is the symbol the main window's sidebar already uses for the Report section — see `AppRouter`.)

- [ ] **Step 3: Add the switch case**

In the same `body`, change:

```swift
                        switch tab {
                        case .timer: timerTab
                        case .tasks: TasksView(timer: timer)
                        case .week:  MenuBarWeekView(timer: timer)
                        }
```

to:

```swift
                        switch tab {
                        case .timer:  timerTab
                        case .tasks:  TasksView(timer: timer)
                        case .week:   MenuBarWeekView(timer: timer)
                        case .report: ReportView(timer: timer)
                        }
```

Nothing else changes: the `if tab == .timer` pinned-controls block, the
`.frame(width: tab == .week ? … : 360)` width rule, and the fixed 512pt
`tabContentHeight` all already do the right thing for a fourth scrolling tab.

- [ ] **Step 4: Build**

Run: `swift build`
Expected: `Build complete!` — a missing `case` would fail here, since the `switch` is exhaustive.

- [ ] **Step 5: Commit**

```bash
git add Sources/Sharingan/Views/MenuBarView.swift
git commit -m "feat(menubar): Report tab in the popover

ReportView reused unchanged as the fourth segment, the way the Tasks
tab reuses TasksView. Width and tab-area height rules untouched.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Photograph it (dev-preview shots + the truncation decision)

**Files:**
- Modify: `Sources/Sharingan/main.swift` (the `--render-dev-preview` block: the `MenuBarView` shot ~line 558, and one new shot after the `stats-extras.png` write ~line 556)

**Interfaces:**
- Consumes: `MenuBarView.Tab.report` from Task 1 (photographed, not referenced); `writeHosted(_:to:size:)` and `write(_:to:scale:)`, both already defined at the top of the dev-preview block.
- Produces: `report-popover.png` and a hosted `menubar.png` in the dev-preview output dir.

- [ ] **Step 1: Host the menubar shot so the picker photographs**

`ImageRenderer` does not rasterize the segmented `Picker` (today's `menubar.png` has a blank strip where it belongs), and the whole point of this shot is now the four segments. In `Sources/Sharingan/main.swift`, change:

```swift
        write(MenuBarView(timer: timer)
                .frame(width: 360, height: 700)
                .background(Color.black.opacity(0.85))
                .environment(\.colorScheme, .dark),
              to: "\(outDir)/menubar.png")
```

to:

```swift
        // Hosted, not `ImageRenderer`-ed: the renderer skips the segmented
        // Picker (and the tab area's ScrollView content), and the segment row
        // is what this shot now exists to check — four labels at 360pt.
        writeHosted(MenuBarView(timer: timer)
                        .background(Color.black.opacity(0.85))
                        .environment(\.colorScheme, .dark),
                    to: "\(outDir)/menubar.png",
                    size: NSSize(width: 360, height: 760))
```

- [ ] **Step 2: Add the popover-width report shot**

Immediately after the `stats-extras.png` `write(...)` call, add:

```swift
        // The report at the popover's content width (360 minus 2×18 outer
        // padding): checks the day pager and the metric column survive 324pt.
        write(ReportView(timer: timer)
                .frame(width: 324)
                .padding(18)
                .background(Color(white: 0.12))
                .environment(\.colorScheme, .dark),
              to: "\(outDir)/report-popover.png")
```

- [ ] **Step 3: Build and render**

```bash
swift build
.build/debug/Sharingan --render-dev-preview /tmp/devprev-report-tab
```

Expected: exits after `dev previews rendered to /tmp/devprev-report-tab`; the directory contains `menubar.png` and `report-popover.png` among the rest.

- [ ] **Step 4: Eyeball the two shots**

Open `menubar.png` and `report-popover.png` (agents: Read them).
PASS criteria:
- `menubar.png`: four segments visible, "Report" label not elided (no `…`).
- `report-popover.png`: pager chevrons, day label, and the 🍅/minutes column all inside the frame; row titles truncate with `…` at worst — nothing clipped mid-glyph, no wrapped metric column.

- [ ] **Step 5 (only if "Report" elides in menubar.png): drop segment labels to icons**

This is the spec's pre-agreed fallback — apply it only on visual evidence from Step 4, then re-run Steps 3-4. In `MenuBarView.swift`, change the four `Label(...)` picker items to:

```swift
            Picker("", selection: $tab) {
                Image(systemName: "timer").tag(Tab.timer)
                Image(systemName: "checklist").tag(Tab.tasks)
                Image(systemName: "calendar").tag(Tab.week)
                Image(systemName: "list.bullet.rectangle").tag(Tab.report)
            }
```

and add `.help(...)` strings ("Timer", "Tasks", "Week", "Report") on each `Image` so the names survive as tooltips.

- [ ] **Step 6: Commit**

```bash
git add Sources/Sharingan/main.swift
# plus Sources/Sharingan/Views/MenuBarView.swift if Step 5 ran
git commit -m "chore(dev-preview): host the menubar shot; report at popover width

The segmented picker never photographed under ImageRenderer, and it is
now the thing being checked (four segments at 360pt). report-popover.png
proves the day pager fits 324pt.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Docs

**Files:**
- Modify: `docs/TECHNICAL.md` (~line 115, the "Menu-bar popover with timer, tasks, and week tabs…" bullet)
- Modify: `CHANGELOG.md` (the `## [Unreleased]` → `### Added` list, which already carries the Report-section entry)

**Interfaces:**
- Consumes: the shipped behavior from Tasks 1-2. Produces: nothing downstream.

- [ ] **Step 1: TECHNICAL.md**

Change the bullet that begins:

```markdown
- Menu-bar popover with timer, tasks, and week tabs plus today's goal. The
```

to begin:

```markdown
- Menu-bar popover with timer, tasks, week, and report tabs plus today's
  goal — the report tab is the main window's day-paged `ReportView` reused
  unchanged, scrolling inside the popover's fixed tab area. The
```

(keep the rest of the bullet — the `NSAppearance` explanation — exactly as it is).

- [ ] **Step 2: CHANGELOG.md**

In `## [Unreleased]` / `### Added`, extend the existing Report entry's line end:

```markdown
…plus a "By task — today" card in Progress and a 14-day history block in the task editor
```

to:

```markdown
…plus a "By task — today" card in Progress, a 14-day history block in the task editor, and a Report tab in the menu-bar popover
```

- [ ] **Step 3: Commit and push**

```bash
git add docs/TECHNICAL.md CHANGELOG.md
git commit -m "docs: menu-bar popover's Report tab

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push
```

---

## Self-Review Notes

- Spec coverage: enum/picker/switch (Task 1), unchanged-`ReportView` + width/height rules (Task 1 Step 3 note), `report-popover.png` + four-segment check (Task 2), icon-only fallback gated on visual evidence (Task 2 Step 5), TECHNICAL.md + CHANGELOG (Task 3). No gaps.
- No unit tests by design: the spec's "no new logic" call; the test cycle is build + headless render + eyeball, which is this repo's established protocol for view-only changes.
- Names cross-checked: `Tab.report`, `ReportView(timer:)`, `writeHosted(_:to:size:)`, `tabContentHeight` all match the code as of `76b1a0b`.
