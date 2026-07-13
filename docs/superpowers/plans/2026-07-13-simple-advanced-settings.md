# Simple / Advanced Settings Tier Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One global Simple | Advanced switch in Settings; Simple shows ~30 most-used rows, Advanced shows all ~85, nothing resets when hidden.

**Architecture:** A `SettingsTier` enum + one-shot seeding live in `SharinganCore` (testable). `SettingsCategory` moves from the view into Core and gains tier metadata. `SettingsView` reads the tier from `@AppStorage` and gates advanced rows with plain `if advanced { }` conditionals — the same pattern the file already uses for `if settings.repeatConfig.enabled { }` (SwiftUI ConditionalContent yields zero variadic children when false, so `SettingsCard` draws no stray divider).

**Tech Stack:** Swift 5.9 SwiftPM, SwiftUI (macOS 14), swift-testing (`import Testing`, `@Suite`, `@Test`, `#expect`).

**Spec:** `docs/superpowers/specs/2026-07-13-simple-advanced-settings-design.md`

## Global Constraints

- Hidden ≠ disabled: advanced values persist and stay in effect while hidden; nothing is reset by switching tiers.
- Tier is UI state in `UserDefaults` under key `"settingsTier"` — it must NOT be added to the `PomodoroSettings` Codable blob.
- Seeding: fresh install → `simple`; existing settings blob at `"com.blink.settings"` → `advanced`; a stored choice is never overwritten.
- Unknown/missing stored tier falls back to `simple`.
- No renaming of existing settings keys; no value migration.
- `docs/` is gitignored — commit doc files with `git add -f`.
- Push after every commit (multi-Mac workflow).
- Run tests with `swift test` (whole suite is fast); build the app with `swift build`.

---

### Task 1: `SettingsTier` in Core + seeding

**Files:**
- Create: `Sources/SharinganCore/Models/SettingsTier.swift`
- Modify: `Sources/SharinganCore/Models/PomodoroSettings.swift` (add `defaultsKey`)
- Modify: `Sources/SharinganCore/Services/PomodoroTimer.swift` (~line 389: use the shared key)
- Test: `Tests/SharinganTests/SettingsTierTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `SettingsTier` (`.simple`/`.advanced`, `String` raw values), `SettingsTier.defaultsKey: String`, `SettingsTier.from(_ raw: String?) -> SettingsTier`, `SettingsTier.seedIfNeeded(defaults: UserDefaults = .standard)`, `PomodoroSettings.defaultsKey: String` (== `"com.blink.settings"`). Later tasks use all of these.

- [ ] **Step 1: Write the failing tests**

Create `Tests/SharinganTests/SettingsTierTests.swift`:

```swift
import Testing
import Foundation
@testable import SharinganCore

@Suite("Settings tier")
struct SettingsTierTests {

    /// Isolated defaults so tests never touch the real app domain.
    private func freshDefaults() -> UserDefaults {
        let name = "tier-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test("fresh install seeds Simple")
    func freshInstallSeedsSimple() {
        let d = freshDefaults()
        SettingsTier.seedIfNeeded(defaults: d)
        #expect(d.string(forKey: SettingsTier.defaultsKey) == "simple")
    }

    @Test("existing settings blob seeds Advanced")
    func existingUserSeedsAdvanced() throws {
        let d = freshDefaults()
        let blob = try JSONEncoder().encode(PomodoroSettings())
        d.set(blob, forKey: PomodoroSettings.defaultsKey)
        SettingsTier.seedIfNeeded(defaults: d)
        #expect(d.string(forKey: SettingsTier.defaultsKey) == "advanced")
    }

    @Test("a stored choice is never overwritten")
    func storedChoiceWins() {
        let d = freshDefaults()
        d.set("simple", forKey: SettingsTier.defaultsKey)
        d.set(Data([0x7b]), forKey: PomodoroSettings.defaultsKey)
        SettingsTier.seedIfNeeded(defaults: d)
        #expect(d.string(forKey: SettingsTier.defaultsKey) == "simple")
    }

    @Test("raw-string resolution falls back to Simple")
    func rawResolution() {
        #expect(SettingsTier.from(nil) == .simple)
        #expect(SettingsTier.from("banana") == .simple)
        #expect(SettingsTier.from("simple") == .simple)
        #expect(SettingsTier.from("advanced") == .advanced)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SettingsTierTests`
Expected: compile FAILURE — `cannot find 'SettingsTier' in scope`, `type 'PomodoroSettings' has no member 'defaultsKey'`.

- [ ] **Step 3: Implement**

Create `Sources/SharinganCore/Models/SettingsTier.swift`:

```swift
import Foundation

/// Settings surface tier: Simple shows the most-used essentials, Advanced
/// shows everything. Pure UI state — stored in UserDefaults, never in the
/// PomodoroSettings JSON blob. Advanced values hidden by Simple keep
/// persisting and keep taking effect.
public enum SettingsTier: String, CaseIterable, Sendable {
    case simple, advanced

    /// UserDefaults key holding the chosen tier's rawValue.
    public static let defaultsKey = "settingsTier"

    /// Tier from a stored raw string; unknown or missing → Simple.
    public static func from(_ raw: String?) -> SettingsTier {
        raw.flatMap(SettingsTier.init(rawValue:)) ?? .simple
    }

    /// One-shot default: fresh installs start Simple; an existing settings
    /// blob (a user updating from an older build) starts Advanced so no
    /// control they already saw disappears. No-op once a tier is stored.
    public static func seedIfNeeded(defaults: UserDefaults = .standard) {
        guard defaults.string(forKey: defaultsKey) == nil else { return }
        let hasBlob = defaults.data(forKey: PomodoroSettings.defaultsKey) != nil
        defaults.set((hasBlob ? SettingsTier.advanced : .simple).rawValue,
                     forKey: defaultsKey)
    }
}
```

In `Sources/SharinganCore/Models/PomodoroSettings.swift`, inside `public struct PomodoroSettings` (right above `public init() {}`), add:

```swift
    /// UserDefaults key of the persisted settings JSON blob (owned by
    /// PomodoroTimer; exposed so tier seeding can detect an existing user).
    public static let defaultsKey = "com.blink.settings"
```

In `Sources/SharinganCore/Services/PomodoroTimer.swift` replace the private key constant (~line 389):

```swift
    private static let settingsKey = "com.blink.settings"
```

with:

```swift
    private static let settingsKey = PomodoroSettings.defaultsKey
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SettingsTierTests`
Expected: 4 tests PASS.

- [ ] **Step 5: Commit and push**

```bash
git add Sources/SharinganCore/Models/SettingsTier.swift Sources/SharinganCore/Models/PomodoroSettings.swift Sources/SharinganCore/Services/PomodoroTimer.swift Tests/SharinganTests/SettingsTierTests.swift
git commit -m "feat(settings): SettingsTier enum with one-shot simple/advanced seeding"
git push
```

---

### Task 2: Move `SettingsCategory` into Core with tier metadata

**Files:**
- Create: `Sources/SharinganCore/Models/SettingsCategory.swift`
- Modify: `Sources/Sharingan/Views/SettingsView.swift` (delete the nested enum at ~lines 898–997; add a `tint` extension)
- Test: `Tests/SharinganTests/SettingsCategoryTests.swift`

**Interfaces:**
- Consumes: `SettingsTier` from Task 1.
- Produces: top-level `public enum SettingsCategory: String, CaseIterable, Identifiable, Hashable, Sendable` with the same 9 cases (`timer, tasks, breaks, focus, eyeCare, sharingan, general, voice, shortcuts`) and members `title`, `subtitle`, `icon`, `keywords`, `matches(_:) -> Bool` (all moved verbatim), plus new `tier: SettingsTier`, `hasAdvancedRows: Bool`, `static func visible(in: SettingsTier) -> [SettingsCategory]`. The view keeps `tint: Color` via a private extension.

- [ ] **Step 1: Write the failing tests**

Create `Tests/SharinganTests/SettingsCategoryTests.swift`:

```swift
import Testing
@testable import SharinganCore

@Suite("Settings categories")
struct SettingsCategoryTests {

    @Test("Simple root shows exactly 7 categories, without Voice/Shortcuts")
    func simpleVisibility() {
        let visible = SettingsCategory.visible(in: .simple)
        #expect(visible.count == 7)
        #expect(!visible.contains(.voice))
        #expect(!visible.contains(.shortcuts))
    }

    @Test("Advanced root shows all 9 in declaration order")
    func advancedVisibility() {
        #expect(SettingsCategory.visible(in: .advanced) == SettingsCategory.allCases)
    }

    @Test("only Voice and Shortcuts are advanced-only categories")
    func tierMetadata() {
        for cat in SettingsCategory.allCases {
            let expected: SettingsTier =
                (cat == .voice || cat == .shortcuts) ? .advanced : .simple
            #expect(cat.tier == expected)
        }
    }

    @Test("search keywords still find advanced-only categories")
    func searchFindsAdvanced() {
        #expect(SettingsCategory.voice.matches("pitch"))
        #expect(SettingsCategory.shortcuts.matches("hotkey"))
    }

    @Test("every category except General has advanced-only rows")
    func advancedRows() {
        #expect(!SettingsCategory.general.hasAdvancedRows)
        for cat in SettingsCategory.allCases where cat != .general {
            #expect(cat.hasAdvancedRows)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SettingsCategoryTests`
Expected: compile FAILURE — `cannot find 'SettingsCategory' in scope` (it is currently nested inside the app-target view, invisible to Core tests).

- [ ] **Step 3: Create the Core enum**

Create `Sources/SharinganCore/Models/SettingsCategory.swift`. The `title`/`subtitle`/`icon`/`keywords`/`matches` bodies are moved **verbatim** from `SettingsView.SettingsCategory` (SettingsView.swift ~lines 898–997), with `public` added:

```swift
import Foundation

/// Groups of settings, shown as drill-down rows on the root Settings screen.
/// Lives in Core (not the view) so tier visibility and search stay testable.
public enum SettingsCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case timer, tasks, breaks, focus, eyeCare, sharingan, general, voice, shortcuts

    public var id: String { rawValue }

    /// Simple-tier categories appear in both tiers; advanced-only ones
    /// (Voice, Shortcuts) appear on the root list only in Advanced. Their
    /// one essential control — spoken instructions on/off — is surfaced in
    /// Eye Care for Simple users.
    public var tier: SettingsTier {
        switch self {
        case .voice, .shortcuts: return .advanced
        default:                 return .simple
        }
    }

    /// Whether the category's detail page hides extra rows in Simple
    /// (drives the "More settings in Advanced" footer).
    public var hasAdvancedRows: Bool { self != .general }

    /// Categories for the root list in the given tier.
    public static func visible(in tier: SettingsTier) -> [SettingsCategory] {
        tier == .advanced ? allCases : allCases.filter { $0.tier == .simple }
    }

    public var title: String {
        switch self {
        case .timer:     return "Timer"
        case .tasks:     return "Tasks & Planning"
        case .breaks:    return "Breaks"
        case .focus:     return "Focus & Blocking"
        case .eyeCare:   return "Eye Care"
        case .sharingan: return "Sharingan Eyes"
        case .general:   return "General"
        case .voice:     return "Voice Guidance"
        case .shortcuts: return "Shortcuts"
        }
    }

    public var subtitle: String {
        switch self {
        case .timer:     return "Durations, mode, repeat, floating timer"
        case .tasks:     return "Goal, estimates, weekly planning, badges"
        case .breaks:    return "Break screen, ambience, brightness"
        case .focus:     return "App blocking, reminders"
        case .eyeCare:   return "Exercises, camera tracking"
        case .sharingan: return "Iris style, desktop wallpaper, spin"
        case .general:   return "Auto-start, sound, notifications"
        case .voice:     return "Spoken instructions"
        case .shortcuts: return "Global keyboard shortcuts"
        }
    }

    public var icon: String {
        switch self {
        case .timer:     return "timer"
        case .tasks:     return "checklist"
        case .breaks:    return "cup.and.saucer.fill"
        case .focus:     return "hand.raised.fill"
        case .eyeCare:   return "eye.fill"
        case .sharingan: return "eye.circle.fill"
        case .general:   return "gearshape.fill"
        case .voice:     return "waveform"
        case .shortcuts: return "keyboard.fill"
        }
    }

    /// Extra search terms so a query finds a category by the settings it holds
    /// (e.g. "float" or "opacity" → Timer).
    public var keywords: [String] {
        switch self {
        case .timer:
            return ["duration", "minutes", "pomodoro", "focus length", "mode",
                    "countdown", "count up", "repeat", "endless", "floating",
                    "float", "opacity", "always on top", "compact",
                    "size", "small", "medium", "large", "preset",
                    "dots", "cycle dots", "active task", "task pill",
                    "today panel", "panel", "desktop", "widget"]
        case .tasks:
            return ["task", "subtask", "estimate", "goal", "week", "weekly",
                    "monday", "sunday", "badge", "plan", "planner", "🍅"]
        case .breaks:
            return ["break", "message", "ambience", "rain", "forest", "white noise",
                    "brightness", "dim", "screen", "exit",
                    "night shift", "warm", "warmth"]
        case .focus:
            return ["app", "block", "blocker", "distraction", "reminder",
                    "posture", "water", "stand"]
        case .eyeCare:
            return ["eye", "exercise", "camera", "vision", "gaze",
                    "blink", "20-20-20"]
        case .sharingan:
            return ["sharingan", "iris", "style", "tomoe", "mangekyou",
                    "wallpaper", "desktop", "spin", "eyes", "follow", "mouse"]
        case .general:
            return ["auto-start", "auto start", "sound", "alarm", "chime",
                    "notification", "launch at login", "startup"]
        case .voice:
            return ["tts", "voice", "speak", "spoken", "announcement", "rate", "pitch"]
        case .shortcuts:
            return ["keyboard", "hotkey", "shortcut", "global", "quick add"]
        }
    }

    /// Whether this category matches a lowercased search query.
    public func matches(_ query: String) -> Bool {
        let hay = ([title, subtitle] + keywords).joined(separator: " ").lowercased()
        return hay.contains(query)
    }
}
```

- [ ] **Step 4: Delete the nested enum from the view, keep `tint` there**

In `Sources/Sharingan/Views/SettingsView.swift`:

1. Delete the whole nested `enum SettingsCategory … }` block (the one starting with the doc comment `/// Groups of settings, shown as drill-down rows…`, ~lines 898–997, including its `tint` property).
2. Add at the bottom of the file (after the last type):

```swift
/// Category accent color — view-layer concern, so it stays out of Core.
private extension SettingsCategory {
    var tint: Color {
        switch self {
        case .timer:     return .blue
        case .tasks:     return .mint
        case .breaks:    return .teal
        case .focus:     return .indigo
        case .eyeCare:   return .green
        case .sharingan: return .red
        case .general:   return Color(white: 0.5)
        case .voice:     return .orange
        case .shortcuts: return .purple
        }
    }
}
```

No other references change — the view already uses the bare name `SettingsCategory`, which now resolves to the Core type via `import SharinganCore`.

- [ ] **Step 5: Run tests and build**

Run: `swift test --filter SettingsCategoryTests && swift build`
Expected: 5 tests PASS; whole package builds (the view compiles against the Core enum).

- [ ] **Step 6: Commit and push**

```bash
git add Sources/SharinganCore/Models/SettingsCategory.swift Sources/Sharingan/Views/SettingsView.swift Tests/SharinganTests/SettingsCategoryTests.swift
git commit -m "refactor(settings): move SettingsCategory to Core, add tier metadata"
git push
```

---

### Task 3: Tier switch UI — root picker, filtered list, search chip, footer, seeding

**Files:**
- Modify: `Sources/Sharingan/Views/SettingsView.swift` (state, `rootHeader`, `filteredCategories`, `categoryRow`, `categoryPage`)
- Modify: `Sources/Sharingan/AppDelegate.swift` (`applicationDidFinishLaunching`, ~line 240)

**Interfaces:**
- Consumes: `SettingsTier.defaultsKey`, `SettingsTier.from(_:)`, `SettingsTier.seedIfNeeded()`, `SettingsCategory.visible(in:)`, `.tier`, `.hasAdvancedRows` (Tasks 1–2).
- Produces: `private var advanced: Bool` inside `SettingsView` — Tasks 4–5 gate rows with `if advanced { }`.

- [ ] **Step 1: Add tier state to `SettingsView`**

Below the existing `@AppStorage(TaskStore.preReminderDefaultsKey)` property (~line 15), add:

```swift
    /// Simple | Advanced surface tier. UI state only — hidden advanced
    /// values keep persisting and keep taking effect.
    @AppStorage(SettingsTier.defaultsKey) private var tierRaw =
        SettingsTier.simple.rawValue
    private var tier: SettingsTier { SettingsTier.from(tierRaw) }
    private var advanced: Bool { tier == .advanced }
```

- [ ] **Step 2: Segmented picker in `rootHeader`**

In `rootHeader`, after the subtitle `Text("Tune your focus sessions, breaks, and eye-care.")…` line, add:

```swift
            Picker("", selection: $tierRaw) {
                Text("Simple").tag(SettingsTier.simple.rawValue)
                Text("Advanced").tag(SettingsTier.advanced.rawValue)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            .padding(.top, 4)
```

- [ ] **Step 3: Tier-aware `filteredCategories`**

Replace the body of `filteredCategories`:

```swift
    /// Root-list categories: the tier's visible set normally; when searching,
    /// ALL categories — an Advanced-only match shows an "Advanced" chip.
    private var filteredCategories: [SettingsCategory] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return SettingsCategory.visible(in: tier) }
        return SettingsCategory.allCases.filter { $0.matches(q) }
    }
```

- [ ] **Step 4: "Advanced" chip + tier auto-switch in `categoryRow`**

Replace `categoryRow(_:)` with:

```swift
    private func categoryRow(_ cat: SettingsCategory) -> some View {
        Button {
            // Opening an Advanced-only category from a Simple search result
            // switches the tier so its page isn't empty.
            if cat.tier == .advanced { tierRaw = SettingsTier.advanced.rawValue }
            openCategory = cat
        } label: {
            HStack(spacing: 12) {
                Image(systemName: cat.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(cat.tint.gradient))
                VStack(alignment: .leading, spacing: 1) {
                    Text(cat.title)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .foregroundStyle(.white)
                    Text(cat.subtitle)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 8)
                if cat.tier == .advanced && !advanced {
                    Text("Advanced")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(.white.opacity(0.12)))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableSubtle)
    }
```

- [ ] **Step 5: "More settings in Advanced" footer on category pages**

In `categoryPage(_:)`, after `categorySections(cat)` add:

```swift
                if !advanced && cat.hasAdvancedRows {
                    Button {
                        tierRaw = SettingsTier.advanced.rawValue
                    } label: {
                        HStack(spacing: 4) {
                            Text("More settings in Advanced")
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(.callout, design: .rounded).weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressableSubtle)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                }
```

- [ ] **Step 6: Seed the tier at launch**

In `Sources/Sharingan/AppDelegate.swift`, in `applicationDidFinishLaunching`, right after `NSApp.setActivationPolicy(.accessory)`:

```swift
        // Fresh install → Simple settings; updating user (existing settings
        // blob) → Advanced, so nothing they already saw disappears.
        SettingsTier.seedIfNeeded()
```

(`AppDelegate.swift` already imports `SharinganCore`.)

- [ ] **Step 7: Build and test**

Run: `swift build && swift test`
Expected: build succeeds, all tests PASS.

- [ ] **Step 8: Commit and push**

```bash
git add Sources/Sharingan/Views/SettingsView.swift Sources/Sharingan/AppDelegate.swift
git commit -m "feat(settings): global Simple/Advanced switch with search bridging"
git push
```

---

### Task 4: Row split — Timer, Tasks, Breaks

**Files:**
- Modify: `Sources/Sharingan/Views/SettingsView.swift` (`categorySections`, cases `.timer`, `.tasks`, `.breaks`)

**Interfaces:**
- Consumes: `advanced: Bool` (Task 3); `settings.focusMinutes` / `settings.shortBreakMinutes` (existing active-kind computed accessors on `PomodoroSettings`), `settings.activeKind.label`.
- Produces: nothing new for later tasks.

All gating uses `if advanced { … }` / `if !advanced { … }` around **existing** rows — row code itself is unchanged unless shown below. `Section` here is the view's private helper (title + `SettingsCard`), so whole sections can be wrapped in conditionals safely.

- [ ] **Step 0: General first + Theme lives in General** *(user decision 2026-07-13)*

In `Sources/SharinganCore/Models/SettingsCategory.swift`:

1. Reorder the case declaration so General leads the root list (order is
   `allCases` order):

```swift
    case general, timer, tasks, breaks, focus, eyeCare, sharingan, voice, shortcuts
```

2. Update General's `subtitle` to `"Theme, auto-start, sound, notifications"`
   and prepend `"theme", "appearance", "liquid", "glass"` to General's
   `keywords` array. Remove nothing from Timer's keywords (search may still
   route "mode"/"countdown" there).

In `Tests/SharinganTests/SettingsCategoryTests.swift` add to the
`simpleVisibility` test:

```swift
        #expect(visible.first == .general)
```

In `SettingsView.categorySections`, move the existing Theme `Picker` row
out of `.timer`'s "Timer mode" section and into `.general` as the FIRST
section of that case, visible in both tiers:

```swift
        case .general:
                Section("Appearance") {
                    Picker("Theme", selection: $settings.theme) {
                        ForEach(SharinganTheme.allCases, id: \.self) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                    .pickerStyle(.menu)
                }
                // existing sections below, unchanged: Auto-start,
                // Notifications, Sound
```

- [ ] **Step 1: `.timer` case**

Restructure the `case .timer:` body to (existing row code moved, not rewritten — note the Theme picker has moved to General in Step 0):

```swift
        case .timer:
                if advanced {
                    Section("Timer mode") {
                        // existing rows, unchanged: Mode picker,
                        // Time format picker, "Flash at 5 seconds left" toggle
                    }
                }

                if !advanced {
                    Section("Durations") {
                        StepperRow(title: "Focus", value: $settings.focusMinutes,
                                   unit: "min")
                        StepperRow(title: "Break", value: $settings.shortBreakMinutes,
                                   unit: "min")
                        Text("Lengths for the current pomodoro size (\(settings.activeKind.label)). All three sizes are editable in Advanced.")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                } else {
                    Section("Pomodoro sizes") {
                        // existing rows, unchanged: explainer Text +
                        // ForEach(PomodoroKind.allCases) focus/break steppers
                    }
                }

                Section("Long break") {
                    // existing rows, unchanged (both tiers)
                }

                if advanced {
                    Section("Repeat") {
                        // existing rows, unchanged
                    }
                }

                Section("Floating timer") {
                    ToggleRow(title: "Floating timer (while running)",
                              isOn: $settings.floatingTimerEnabled)
                    if settings.floatingTimerEnabled && advanced {
                        // existing rows, unchanged: Size picker, Always on top,
                        // Cycle dots, Active task, Opacity slider, drag hint Text
                    }
                }

                Section("Today panel") {
                    // existing rows, unchanged (both tiers)
                }

                Section("Menu bar") {
                    // existing rows, unchanged (both tiers)
                }
```

The comments above name every existing row that moves inside each brace — copy those rows verbatim from the current file; only the two `StepperRow`s and the explainer `Text` in `Section("Durations")` are new code.

- [ ] **Step 2: `.tasks` case**

Wrap the last two sections:

```swift
        case .tasks:
                Section("Tasks") { /* existing rows, unchanged */ }
                Section("Due reminders") { /* existing rows, unchanged */ }
                if advanced {
                    Section("Planning") { /* existing rows, unchanged */ }
                    Section("Estimates & badges") { /* existing rows, unchanged */ }
                }
```

- [ ] **Step 3: `.breaks` case**

Wrap only the brightness section:

```swift
        case .breaks:
                Section("Break message") { /* existing rows, unchanged */ }
                Section("Break") { /* existing rows, unchanged */ }
                Section("Break ambience") { /* existing rows, unchanged */ }
                if advanced {
                    Section("Screen brightness") { /* existing rows, unchanged */ }
                }
```

- [ ] **Step 4: Build and eyeball**

Run: `swift build && swift test`
Expected: build succeeds, tests PASS.
Then launch briefly (`swift run Sharingan` or the packaged app), open Settings → Timer in Simple: exactly Focus/Break steppers, Long break, floating toggle, Today panel, Menu bar + the Advanced footer; flip to Advanced: full surface as before. Both `Durations` steppers must move the same values the Advanced grid shows for the active kind.

- [ ] **Step 5: Commit and push**

```bash
git add Sources/Sharingan/Views/SettingsView.swift
git commit -m "feat(settings): simple/advanced row split for Timer, Tasks, Breaks"
git push
```

---

### Task 5: Row split — Focus, Eye Care, Sharingan (+ Voice toggle bridge)

**Files:**
- Modify: `Sources/Sharingan/Views/SettingsView.swift` (`categorySections`, cases `.focus`, `.eyeCare`, `.sharingan`; `.general`, `.voice`, `.shortcuts` stay untouched)

**Interfaces:**
- Consumes: `advanced: Bool` (Task 3); `$settings.ttsSettings.enabled` (existing binding, also used by the Voice category).
- Produces: nothing new.

- [ ] **Step 1: `.focus` case**

```swift
        case .focus:
                Section("App blocking") {
                    ToggleRow(title: "Block distracting apps on break",
                              isOn: $settings.appBlockerSettings.enabled)
                    if advanced {
                        ToggleRow(title: "Also block during focus session",
                                  isOn: $settings.blockAppsDuringFocus)
                        ToggleRow(title: "Force quit (not just hide)",
                                  isOn: $settings.appBlockerSettings.killOnFrontmost)
                    }
                    // existing rows, unchanged (both tiers): ForEach blocked-app
                    // rows + "Restore default apps" button
                }

                if advanced {
                    Section("Do Not Disturb") { /* existing rows, unchanged */ }
                }

                Section("Reminders (posture / water / custom)") {
                    ToggleRow(title: "Reminders enabled",
                              isOn: $settings.reminderSettings.enabled)
                    if advanced {
                        ToggleRow(title: "Only during focus phase",
                                  isOn: $settings.reminderSettings.duringFocusOnly)
                        // existing rows, unchanged: ForEach ReminderRow +
                        // "Add reminder" button
                    }
                }
```

- [ ] **Step 2: `.eyeCare` case**

```swift
        case .eyeCare:
                Section("Eye exercise sequence") {
                    // existing rows, unchanged (both tiers): 20-20-20 / Gaze /
                    // Blink toggles, "Exercise rounds" stepper
                    if !advanced {
                        // Bridge: the one essential Voice control, surfaced here
                        // because the Voice category is Advanced-only. Same
                        // underlying setting as Voice Guidance → Spoken
                        // instructions (in Advanced it lives only there).
                        ToggleRow(title: "Spoken instructions",
                                  isOn: $settings.ttsSettings.enabled)
                    }
                    // existing row, unchanged (both tiers): "Preview break
                    // screen" button
                    if advanced {
                        // existing rows, unchanged: step-hold-scale slider +
                        // step-length caption, instructionEditor(for:) block,
                        // StepsInstructionEditor, kalib-interval slider
                    }
                }

                Section("Camera & Vision") {
                    ToggleRow(title: "Eye tracking via camera",
                              isOn: $settings.cameraEyeTrackingEnabled)
                    if settings.cameraEyeTrackingEnabled {
                        Text("Works during breaks only. Alerts when blink rate is low.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.white.opacity(0.65))
                        if advanced {
                            ToggleRow(title: "Strict exercise validation",
                                      isOn: $settings.strictExerciseValidation)
                            Text("A step won't advance until the camera confirms the movement (gaze directions and blinks). Off = auto-advance after a grace period.")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }
                }
```

Note the `if let selected = editingInstructionDirection { instructionEditor(for: selected) }` block belongs inside the `if advanced` group (the per-direction editor is Advanced).

- [ ] **Step 3: `.sharingan` case**

```swift
        case .sharingan:
                Section("Iris style") {
                    // existing rows, unchanged (both tiers): eye-pair preview
                    // HStack, main style picker row, "Used everywhere…" caption
                    if advanced {
                        // existing rows, unchanged: "Different style per eye"
                        // toggle + right-eye picker row
                    }
                }

                Section("Break screen") {
                    // existing rows, unchanged (both tiers): Background picker
                    // row + its caption, "Preview break screen" button
                    if advanced {
                        // existing rows, unchanged: Pattern animation picker +
                        // caption, Mixed patterns toggle + caption, Pattern spin
                        // picker + caption
                    }
                }

                Section("Desktop wallpaper") {
                    // existing rows, unchanged (both tiers): "Show eyes on the
                    // desktop" toggle + live-wallpaper caption
                    if advanced {
                        // existing rows, unchanged: Sharingan spin trigger row,
                        // Spin speed row, Idle delay slider, Close-eyes-after
                        // slider + doze caption
                    }
                }
                .onChange(of: settings.eyesWallpaperEnabled) { _, on in
                    WallpaperWindowManager.shared.setEnabled(on, config: WallpaperConfig(from: settings))
                }
                .onChange(of: settings.wallpaperSpinTrigger) { refreshWallpaper() }
                .onChange(of: settings.wallpaperSpinDuration) { refreshWallpaper() }
                .onChange(of: settings.wallpaperIdleDelay) { refreshWallpaper() }
                .onChange(of: settings.wallpaperDozeSeconds) { refreshWallpaper() }
                .onChange(of: settings.sharinganStyle) { refreshWallpaper() }
                .onChange(of: settings.sharinganStyleRight) { refreshWallpaper() }
```

Keep the whole `.onChange` chain on the last section exactly as today. Inside "Break screen", the caption `"One flat tone across the whole break screen…"` stays with the Background picker (both tiers); the Mixed-patterns conditional `if settings.breakPatternTransition != .off` nests inside the `if advanced` block unchanged.

`.general`, `.voice`, `.shortcuts` cases: no changes (General is all-Simple; Voice/Shortcuts pages are reachable only in Advanced).

- [ ] **Step 4: Build, test, verify in app**

Run: `swift build && swift test`
Expected: build succeeds, tests PASS.
In-app check (Simple): Focus page shows block-on-break + app list + reminders master toggle only; Eye Care shows the Spoken-instructions bridge toggle; Sharingan shows style/background/wallpaper-toggle only. Flip a hidden setting in Advanced (e.g. wallpaper spin), switch to Simple → behavior persists.

- [ ] **Step 5: Commit and push**

```bash
git add Sources/Sharingan/Views/SettingsView.swift
git commit -m "feat(settings): simple/advanced row split for Focus, Eye Care, Sharingan"
git push
```

---

### Task 6: Docs + spec amendment + final verification

**Files:**
- Modify: `docs/TECHNICAL.md` (settings section)
- Modify: `docs/superpowers/specs/2026-07-13-simple-advanced-settings-design.md` (footer wording)

**Interfaces:** none.

- [ ] **Step 1: Amend the spec footer bridge**

In the spec's "Discoverability bridges" item 2, replace:

> **Footer link on each Simple category page:** "*N more settings in Advanced →*". Tapping switches tier in place. N is computed automatically via a PreferenceKey counting hidden rows — never hand-maintained.

with:

> **Footer link on each Simple category page:** "*More settings in Advanced →*". Tapping switches tier in place. (No hidden-row count: the variadic `SettingsCard` row layout would render a preference-carrying placeholder as an empty row with a stray divider, so the link is countless by design.)

Also in "Code structure", replace the `.advancedOnly()` modifier bullet with:

> - Rows/sections gated in place with `if advanced { }` conditionals in
>   `SettingsView.categorySections` — a modifier whose body conditionally
>   omits content still counts as a variadic child in `SettingsCard` and
>   would leave an empty padded row with a divider; a false `if` yields
>   zero children (the pattern the file already uses for conditional rows).

- [ ] **Step 2: Update `docs/TECHNICAL.md`**

Add a subsection to the settings/UI area of the doc (match its existing heading style):

```markdown
### Settings tiers (Simple / Advanced)

Settings has two surfaces controlled by one segmented switch on the root
list: **Simple** (~30 most-used rows across 7 categories) and **Advanced**
(all ~85 rows, 9 categories — adds Voice Guidance and Shortcuts).

- `SettingsTier` (SharinganCore/Models) — `simple`/`advanced`; stored in
  `UserDefaults` under `settingsTier` (never in the PomodoroSettings blob).
  `seedIfNeeded()` runs at launch: fresh install → simple, existing
  settings blob (`PomodoroSettings.defaultsKey`) → advanced.
- `SettingsCategory` (SharinganCore/Models) — moved out of the view; owns
  `tier`, `hasAdvancedRows`, `visible(in:)`, and search `matches(_:)`.
  The `tint` color stays in a SettingsView extension.
- Rows are gated in `SettingsView.categorySections` with `if advanced { }`.
  Hidden ≠ disabled: advanced values persist and stay in effect.
- Search always spans both tiers; an Advanced-only hit shows an "Advanced"
  chip and opening it switches the tier. Simple category pages end with a
  "More settings in Advanced →" link.
- Simple Timer shows two steppers bound to the active pomodoro kind
  (`settings.focusMinutes` / `shortBreakMinutes`); the Small/Normal/Big
  grid is Advanced. The Spoken-instructions toggle appears in Eye Care in
  Simple (same `ttsSettings.enabled` the Voice category edits).
```

- [ ] **Step 3: Full verification**

Run: `swift build && swift test`
Expected: clean build, entire suite PASS.

- [ ] **Step 4: Commit and push (docs are gitignored — force-add)**

```bash
git add -f docs/TECHNICAL.md docs/superpowers/specs/2026-07-13-simple-advanced-settings-design.md
git commit -m "docs: settings tier concept in TECHNICAL.md; spec footer amendment"
git push
```

---

### Task 7: Blink → Sharingan internal rebrand + one-shot data migration

*(Added 2026-07-13 by user decision: "hammasi + migratsiya". The app is
already branded Sharingan in the UI; this renames the internal storage
identifiers and demo strings, migrating existing users' data.)*

**Files:**
- Create: `Sources/SharinganCore/Services/RebrandMigration.swift`
- Modify: `Sources/SharinganCore/Models/PomodoroSettings.swift` (defaultsKey, DND defaults),
  `Sources/SharinganCore/Services/PomodoroTimer.swift` (statsKey),
  `Sources/SharinganCore/Services/CLIBridge.swift` (snapshotKey, darwin names, shared dir),
  `Sources/SharinganCore/Services/TaskStore.swift` + `TemplateStore.swift` (dir name),
  `Sources/Sharingan/Views/FloatingTimerView.swift` / wherever `blink.floating.*` and
  `blink.todayPanel.origin` keys live (grep for `"blink.` to find them),
  `Sources/Sharingan/AppDelegate.swift` (call migration BEFORE `SettingsTier.seedIfNeeded()`),
  `Sources/tired/main.swift` (call migration at startup; fix `@blink` help example),
  `Sources/Sharingan/main.swift` + `Sources/SelfTest/main.swift` (demo `project: "Blink"` strings)
- Test: `Tests/SharinganTests/RebrandMigrationTests.swift`

**Interfaces:**
- Consumes: `PomodoroSettings.defaultsKey` (changes value), `SettingsTier.seedIfNeeded` ordering.
- Produces: `RebrandMigration.migrate(defaults:fileManager:)` — called at app AND CLI startup.

**Key renames (old → new):**

| Old | New |
|---|---|
| `com.blink.settings` | `com.sharingan.settings` |
| `com.blink.stats` | `com.sharingan.stats` |
| `com.blink.cliSnapshot` | `com.sharingan.cliSnapshot` |
| `com.blink.cli.*` (darwin notification names) | `com.sharingan.cli.*` |
| `blink.floating.x/y/w/h` | `sharingan.floating.x/y/w/h` |
| `blink.todayPanel.origin` | `sharingan.todayPanel.origin` |
| App Support dir `Blink/` (incl. `Blink/cli`) | `Sharingan/` |
| Demo/task strings `project: "Blink"`, help `@blink` | `"Sharingan"`, `@sharingan` |
| DND shortcut DEFAULTS `"Blink Focus On/Off"` | `"Sharingan Focus On/Off"` |

**NOT migrated (deliberate):** stored `dndShortcutOn/Off` values inside a
user's settings blob — they name the user's real Shortcuts in Shortcuts.app;
rewriting them would silently break the user's automation. Only the code
defaults change (fresh installs). Old defaults-keys are copied, not deleted
(cheap rollback safety); the App Support dir is MOVED (renamed), not copied,
so task/template data isn't forked.

- [ ] **Step 1: Write failing tests**

`Tests/SharinganTests/RebrandMigrationTests.swift`:

```swift
import Testing
import Foundation
@testable import SharinganCore

@Suite("Rebrand migration")
struct RebrandMigrationTests {

    private func freshDefaults() -> UserDefaults {
        let name = "rebrand-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func tempBase() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rebrand-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("old defaults values are copied to new keys, old kept")
    func defaultsCopied() {
        let d = freshDefaults()
        d.set(Data([0x7b]), forKey: "com.blink.settings")
        d.set(Data([0x5b]), forKey: "com.blink.stats")
        d.set(120.0, forKey: "blink.floating.x")
        RebrandMigration.migrateDefaults(d)
        #expect(d.data(forKey: PomodoroSettings.defaultsKey) == Data([0x7b]))
        #expect(d.data(forKey: "com.sharingan.stats") == Data([0x5b]))
        #expect(d.double(forKey: "sharingan.floating.x") == 120.0)
        #expect(d.data(forKey: "com.blink.settings") != nil)  // kept
    }

    @Test("existing new-key values are never overwritten")
    func newKeyWins() {
        let d = freshDefaults()
        d.set(Data([0x01]), forKey: "com.sharingan.settings")
        d.set(Data([0x02]), forKey: "com.blink.settings")
        RebrandMigration.migrateDefaults(d)
        #expect(d.data(forKey: "com.sharingan.settings") == Data([0x01]))
    }

    @Test("no-op on a fresh install")
    func freshNoop() {
        let d = freshDefaults()
        RebrandMigration.migrateDefaults(d)
        #expect(d.data(forKey: PomodoroSettings.defaultsKey) == nil)
    }

    @Test("Blink app-support dir is renamed to Sharingan")
    func dirMoved() throws {
        let base = try tempBase()
        let old = base.appendingPathComponent("Blink", isDirectory: true)
        try FileManager.default.createDirectory(
            at: old.appendingPathComponent("cli"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: old.appendingPathComponent("tasks.json"))
        RebrandMigration.migrateAppSupport(base: base)
        let new = base.appendingPathComponent("Sharingan", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: new.appendingPathComponent("tasks.json").path))
        #expect(!FileManager.default.fileExists(atPath: old.path))
    }

    @Test("dir move never clobbers an existing Sharingan dir")
    func dirMoveNoClobber() throws {
        let base = try tempBase()
        let old = base.appendingPathComponent("Blink", isDirectory: true)
        let new = base.appendingPathComponent("Sharingan", isDirectory: true)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: new.appendingPathComponent("tasks.json"))
        RebrandMigration.migrateAppSupport(base: base)
        let kept = try Data(contentsOf: new.appendingPathComponent("tasks.json"))
        #expect(String(decoding: kept, as: UTF8.self) == "new")
    }

    @Test("fresh DND defaults say Sharingan")
    func dndDefaults() {
        let s = PomodoroSettings()
        #expect(s.dndShortcutOn == "Sharingan Focus On")
        #expect(s.dndShortcutOff == "Sharingan Focus Off")
    }
}
```

Run: `swift test --filter RebrandMigrationTests` — expect compile failure.

- [ ] **Step 2: Implement `RebrandMigration`**

`Sources/SharinganCore/Services/RebrandMigration.swift`:

```swift
import Foundation

/// One-shot Blink → Sharingan storage rename. The app was renamed in the UI
/// long ago; this migrates the on-disk identifiers so existing users keep
/// their settings, stats, tasks and templates. Old defaults keys are copied
/// (kept for rollback); the App Support directory is moved. Safe to call on
/// every launch — copies and moves only happen when the new location is
/// still empty. Called by the app (AppDelegate) and the `tired` CLI before
/// anything reads storage.
public enum RebrandMigration {

    /// Old→new UserDefaults keys (values copied verbatim, old kept).
    static let keyMap: [(old: String, new: String)] = [
        ("com.blink.settings", "com.sharingan.settings"),
        ("com.blink.stats", "com.sharingan.stats"),
        ("com.blink.cliSnapshot", "com.sharingan.cliSnapshot"),
        ("blink.floating.x", "sharingan.floating.x"),
        ("blink.floating.y", "sharingan.floating.y"),
        ("blink.floating.w", "sharingan.floating.w"),
        ("blink.floating.h", "sharingan.floating.h"),
        ("blink.todayPanel.origin", "sharingan.todayPanel.origin"),
    ]

    public static func migrate(defaults: UserDefaults = .standard,
                               fileManager: FileManager = .default) {
        migrateDefaults(defaults)
        if let base = fileManager.urls(for: .applicationSupportDirectory,
                                       in: .userDomainMask).first {
            migrateAppSupport(base: base, fileManager: fileManager)
        }
    }

    public static func migrateDefaults(_ defaults: UserDefaults) {
        for (old, new) in keyMap
        where defaults.object(forKey: new) == nil {
            if let value = defaults.object(forKey: old) {
                defaults.set(value, forKey: new)
            }
        }
    }

    public static func migrateAppSupport(base: URL,
                                         fileManager: FileManager = .default) {
        let old = base.appendingPathComponent("Blink", isDirectory: true)
        let new = base.appendingPathComponent("Sharingan", isDirectory: true)
        guard fileManager.fileExists(atPath: old.path),
              !fileManager.fileExists(atPath: new.path) else { return }
        try? fileManager.moveItem(at: old, to: new)
    }
}
```

- [ ] **Step 3: Rename the constants**

Apply the key-rename table above. Every rename is a constant-value change —
grep `"com.blink\|\"blink\.\|\"Blink\b\|Blink Focus\|@blink"` across
`Sources/` to find them all. Specifics:

1. `PomodoroSettings.defaultsKey` → `"com.sharingan.settings"`; DND defaults
   → `"Sharingan Focus On"` / `"Sharingan Focus Off"` (both the stored-property
   defaults AND the `d.dndShortcutOn/Off` decode fallbacks pick this up
   automatically since they read the defaults instance).
2. `PomodoroTimer.statsKey` → `"com.sharingan.stats"`.
3. `CLIBridge`: `snapshotKey`, all `darwinCommand*` names (`com.blink.cli.*`
   → `com.sharingan.cli.*`), and `sharedDir` path component `"Blink/cli"` →
   `"Sharingan/cli"`.
4. `TaskStore` and `TemplateStore` dir `"Blink"` → `"Sharingan"`.
5. Floating/today-panel keys per the table (app target).
6. Demo strings: `project: "Blink"` → `project: "Sharingan"` in
   `Sources/Sharingan/main.swift` (2 sites) and `Sources/SelfTest/main.swift`
   (incl. its `t.project == "Blink"` assertion); `@blink` → `@sharingan` in
   the `tired` help text.

- [ ] **Step 4: Wire the calls**

In `AppDelegate.applicationDidFinishLaunching`, immediately BEFORE
`SettingsTier.seedIfNeeded()` (order matters — seeding checks the NEW
settings key, so the blob must be copied first):

```swift
        RebrandMigration.migrate()
```

In `Sources/tired/main.swift`, at the top of the entry point before any
CLIBridge/TaskStore access, add the same `RebrandMigration.migrate()` call.

- [ ] **Step 5: Run tests**

Run: `swift test --filter RebrandMigrationTests` → 6 tests PASS, then the
full `swift test` and `swift build`. Watch for existing tests that assert the
old literals (e.g. SelfTest-style fixtures) and update them per Step 3.6.

- [ ] **Step 6: Update docs**

Add to `docs/TECHNICAL.md` (near the storage/persistence notes): a short
"Storage identifiers" note listing the new `com.sharingan.*` keys, the
`~/Library/Application Support/Sharingan/` directory, and that
`RebrandMigration` performs the one-shot Blink→Sharingan copy/move at
launch (defaults copied, dir moved, DND stored values deliberately kept).

- [ ] **Step 7: Commit and push**

```bash
git add -A Sources Tests
git add -f docs/TECHNICAL.md
git commit -m "feat(rebrand): Blink -> Sharingan storage identifiers with one-shot migration"
git push
```

---

### Task 8: Per-page "Advanced settings" accordion replaces the global tier switch

*(Added 2026-07-13, user decision after seeing the built UI: "ichiga kirib
asosiylar ochiq ko'rinsin, pastda advanced settings accordionda chiqsin".
The global Simple|Advanced switch goes away; every category page shows its
essential rows always, with the advanced rows inside one collapsible
"Advanced settings" disclosure at the bottom of the page.)*

**Files:**
- Modify: `Sources/Sharingan/Views/SettingsView.swift` (remove tier state/picker/chip/footer; restructure `categorySections`; add accordion)
- Modify: `Sources/SharinganCore/Models/SettingsCategory.swift` (drop `tier` + `visible(in:)`; recompute `hasAdvancedRows`)
- Delete: `Sources/SharinganCore/Models/SettingsTier.swift`
- Modify: `Sources/Sharingan/AppDelegate.swift` (drop `SettingsTier.seedIfNeeded()`; keep `RebrandMigration.migrate()`)
- Delete: `Tests/SharinganTests/SettingsTierTests.swift`
- Modify: `Tests/SharinganTests/SettingsCategoryTests.swift`

**Interfaces:**
- Consumes: existing `categorySections` structure with `if advanced { }` gates (Tasks 4–5) — those gates become the accordion's content.
- Produces: nothing new for later tasks (terminal UI task).

**Design:**

1. **Root list**: all 9 categories always visible (General first, as now).
   No segmented picker in `rootHeader`, no "Advanced" chip, no tier
   auto-switch in `categoryRow`, no "More settings in Advanced" footer.
2. **Category page layout**: the previously-Simple rows render always, in
   their existing sections. The previously-Advanced rows move into a
   trailing accordion:

```swift
    @State private var advancedExpanded = false
```

   (reset to `false` whenever `openCategory` changes). At the bottom of
   `categoryPage(_:)` (after `categorySections(cat)`), for categories where
   `cat.hasAdvancedRows`:

```swift
                if cat.hasAdvancedRows {
                    Button {
                        withAnimation(DS.Motion.gentle) { advancedExpanded.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .rotationEffect(.degrees(advancedExpanded ? 90 : 0))
                            Text("Advanced settings")
                                .font(.system(.callout, design: .rounded).weight(.semibold))
                            Spacer()
                        }
                        .foregroundStyle(.white.opacity(0.75))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressableSubtle)
                    .padding(.top, 4)

                    if advancedExpanded {
                        advancedSections(cat)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
```

3. **Split `categorySections`** into two builders:
   - `categorySections(_ cat:)` — the always-visible rows: exactly the
     rows that were un-gated (Simple) after Tasks 4–5, with two deltas:
     (a) the Eye Care "Spoken instructions" bridge toggle is REMOVED
     (Voice Guidance is now always reachable from the root — the bridge
     would duplicate it on two simultaneously-visible pages);
     (b) *(user decision 2026-07-13: "settingsda pomidor tursin")* Timer's
     always-visible part shows the FULL Section("Pomodoro sizes") —
     explainer + 3×2 Small/Normal/Big grid — and the two-stepper
     "Durations" simplification from Task 4 is DELETED (it was a
     Simple-tier substitute; with tiers gone the real grid is the one
     source of truth).
   - `advancedSections(_ cat:)` — new `@ViewBuilder` containing what was
     inside the `if advanced { }` gates, kept in their own sections, in
     this order per category:
     - **Timer**: Section("Timer mode") — mode/format/flash;
       Section("Repeat"); Section("Floating timer details") —
       size/always-on-top/dots/task/opacity/drag hint, still gated
       `if settings.floatingTimerEnabled` (keep that inner conditional;
       when the master toggle is off the section shows a short caption
       "Enable the floating timer to configure it." instead).
     - **Tasks**: Section("Planning"); Section("Estimates & badges").
     - **Breaks**: Section("Screen brightness").
     - **Focus**: Section("App blocking extras") — also-block-during-focus +
       force-quit; Section("Do Not Disturb") — unchanged block;
       Section("Reminder details") — during-focus-only + per-reminder rows +
       add button.
     - **Eye Care**: Section("Exercise tuning") — step-hold slider + caption,
       instruction editor block (`if let selected…` + StepsInstructionEditor),
       kalib slider; Section("Camera") — strict-validation toggle + caption,
       gated `if settings.cameraEyeTrackingEnabled` (else a caption "Enable
       camera eye tracking to configure validation.").
     - **Sharingan**: Section("Iris details") — per-eye toggle + right-eye
       picker; Section("Break screen effects") — pattern animation + mixed +
       spin (Mixed still nested in `!= .off`); Section("Wallpaper motion") —
       spin trigger/speed/idle/doze. NOTE: the `.onChange` chain currently
       hangs off the "Desktop wallpaper" section in the always-visible part —
       it must STAY on an always-visible view (it re-applies wallpaper
       config); do not move it into the accordion, where it would stop
       observing while collapsed.
     - **General, Voice, Shortcuts**: no `advancedSections` (all content
       always visible; `hasAdvancedRows == false`).
4. **Core cleanup**: delete `SettingsTier.swift` and its tests; in
   `SettingsCategory` delete `tier` and `visible(in:)`, recompute
   `hasAdvancedRows` as `!(self == .general || self == .voice || self == .shortcuts)`;
   in `SettingsView` delete `tierRaw`/`tier`/`advanced` and every use;
   in `AppDelegate` delete the `SettingsTier.seedIfNeeded()` call and its
   comment (keep `RebrandMigration.migrate()`). The stored `"settingsTier"`
   defaults key becomes a harmless leftover — do not write cleanup code
   for it.
5. **Tests** (`SettingsCategoryTests`): replace tier-dependent tests with:
   all 9 cases present, `allCases.first == .general`,
   `hasAdvancedRows` false exactly for general/voice/shortcuts, search
   keywords still find voice ("pitch") and shortcuts ("hotkey").
6. Update `docs/TECHNICAL.md` "Settings tiers" subsection → rename to
   "Settings layout (essentials + Advanced accordion)" and rewrite to match
   (per-page accordion, no global switch, no seeding); add a dated line to
   the spec's "Later decisions" section.

- [ ] **Step 1: implement the view + Core + AppDelegate changes above**
- [ ] **Step 2: update the tests; run `swift test --filter SettingsCategoryTests`**
- [ ] **Step 3: full `swift build && swift test` — green (RebrandMigration
      and all other suites untouched)**
- [ ] **Step 4: docs updates (TECHNICAL.md + spec Later decisions)**
- [ ] **Step 5: commit and push**

```bash
git add -A Sources Tests
git add -f docs/TECHNICAL.md docs/superpowers/specs/2026-07-13-simple-advanced-settings-design.md
git commit -m "feat(settings): per-page Advanced accordion replaces global tier switch"
git push
```

---

### Task 9: Pomodoro-kind chip in the task picker

*(Added 2026-07-13, user decision: "task tanlashda pomidorini turini
tanlasin" — when picking the task for a focus session, the user should be
able to pick that task's pomodoro size right there.)*

The model and editor already support per-task kinds: `TaskItem.pomodoroKind:
PomodoroKind?` (nil = default), `TaskStore.resolvedActiveKind`, and
`TaskEditorView` has a chip + `Menu` precedent (lines ~222–236: "Default" +
`ForEach(PomodoroKind.allCases)` entries with checkmark). The timer already
adopts the picked task's kind (verified by SelfTest "session adopts the
task's kind"). The ONLY gap: `TaskPickerSheet` (the "Choose a task" /
"What's next?" sheet) shows no kind control.

**Files:**
- Modify: `Sources/Sharingan/Views/TaskPickerSheet.swift`

**Design:**

1. In `row(_ task:)`, right-aligned before the chevron/affordances, add a
   compact kind chip styled like the editor's: a `Menu` whose label is the
   task's current kind (`task.pomodoroKind?.label ?? "Auto"` with
   `task.pomodoroKind?.systemImage ?? "timer"` icon, caption font, subtle
   capsule). Menu entries: "Default" (sets nil) + one per
   `PomodoroKind.allCases` (Small/Normal/Big, checkmark on the current one).
2. Selecting an entry PERSISTS to the task via the existing store update
   path (mirror how `TaskEditorView` saves the draft's kind — reuse
   `TaskStore`'s update API, do not add new store methods) — so the choice
   sticks for future sessions, same semantics as the editor.
3. Tapping the chip must NOT trigger the row's own Button action (picking
   the task). Put the Menu outside the row Button's label or use
   `.buttonStyle` isolation — verify a chip tap doesn't start a session.
4. Row height/layout must not jump: chip is one-line, caption-sized,
   `fixedSize()`.
5. No behavior change in pick-mode vs start-mode beyond the chip being
   available in both.

**Verification:** `swift build && swift test` green; then
`swift run Sharingan` manually (or ask the controller/user) to confirm:
chip shows per-row, changing it updates the task (visible in the editor
afterwards), tapping the chip does not start the session, picking the row
starts with the chosen kind.

**Commit:**

```bash
git add Sources/Sharingan/Views/TaskPickerSheet.swift
git commit -m "feat(tasks): pomodoro-size chip in the task picker"
git push
```

---

### Task 10: Pomodoro sizes as a table, long break per size

*(Added 2026-07-13, user decision: "buni tablik qil. pomidorolarga ham long
break tasir qiladi" — render the Pomodoro sizes section as a compact grid,
and give each size its own long-break length.)*

**Files:**
- Modify: `Sources/SharinganCore/Models/PomodoroSettings.swift` (`PomodoroKindConfig` + effective long break)
- Modify: `Sources/Sharingan/Views/SettingsView.swift` (table UI in Timer's always-visible part; drop the global "Long break" stepper row)
- Test: `Tests/SharinganTests/PomodoroModelsTests.swift` (append a new suite or tests)

**Model design (backward compatible):**

1. `PomodoroKindConfig` gains `public var longBreakMinutes: Int? = nil`
   (nil = "no per-size override"). Update its `init` to
   `init(focusMinutes: Int, breakMinutes: Int, longBreakMinutes: Int? = nil)`.
   Synthesized Codable handles old JSON (missing key → nil) — do NOT write
   a custom decoder for it.
2. `PomodoroSettings.longBreakMinutes` (stored, default 15) STAYS — it is
   the fallback when a kind has no override, so every existing blob keeps
   its exact current behavior.
3. Effective length: change `longBreakSeconds` to

```swift
    /// Long-break length of the ACTIVE kind: per-size override, else the
    /// stored global value (pre-per-size blobs keep behaving identically).
    public var longBreakSeconds: TimeInterval {
        TimeInterval(config(for: activeKind).longBreakMinutes ?? longBreakMinutes) * 60
    }
```

   `duration(for: .longBreak)` and every caller pick this up automatically.

**Table UI (Timer page, always-visible "Pomodoro sizes" section):**

Replace the explainer + 6 `StepperRow`s + the "Long break" section's global
stepper with: the explainer Text (unchanged), then a `Grid`:

```swift
                    Grid(horizontalSpacing: 10, verticalSpacing: 8) {
                        GridRow {
                            Color.clear.frame(width: 1, height: 1)
                            ForEach(["Focus", "Break", "Long break"], id: \.self) { h in
                                Text(h)
                                    .font(.system(.caption, design: .rounded).weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        ForEach(PomodoroKind.allCases) { kind in
                            GridRow {
                                Label(kind.label, systemImage: kind.systemImage)
                                    .font(.system(.callout, design: .rounded).weight(.medium))
                                    .foregroundStyle(.white)
                                    .labelStyle(.titleAndIcon)
                                    .gridColumnAlignment(.leading)
                                kindCell(kind, \.focusMinutes)
                                kindCell(kind, \.breakMinutes)
                                longBreakCell(kind)
                            }
                        }
                    }
```

with two small helpers next to the other private helpers in `SettingsView`:

```swift
    /// One table cell: minutes value + compact stepper for a kind's field.
    private func kindCell(_ kind: PomodoroKind,
                          _ field: WritableKeyPath<PomodoroKindConfig, Int>) -> some View {
        let binding = Binding<Int>(
            get: { settings.config(for: kind)[keyPath: field] },
            set: { v in
                var c = settings.config(for: kind)
                c[keyPath: field] = v
                settings.setConfig(c, for: kind)
            })
        return VStack(spacing: 3) {
            Text("\(binding.wrappedValue) min")
                .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.dsSecondary)
            DSStepper(value: binding)
        }
        .frame(maxWidth: .infinity)
    }

    /// Long-break cell: per-size override, falling back to the global value.
    private func longBreakCell(_ kind: PomodoroKind) -> some View {
        let binding = Binding<Int>(
            get: { settings.config(for: kind).longBreakMinutes ?? settings.longBreakMinutes },
            set: { v in
                var c = settings.config(for: kind)
                c.longBreakMinutes = v
                settings.setConfig(c, for: kind)
            })
        return VStack(spacing: 3) {
            Text("\(binding.wrappedValue) min")
                .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.dsSecondary)
            DSStepper(value: binding)
        }
        .frame(maxWidth: .infinity)
    }
```

The old `Section("Long break")` keeps ONLY the "Long break every N
pomodoros" stepper (rename its title to "Long break rhythm" is NOT needed —
keep "Long break"). The global "Long break minutes" stepper row is deleted
(the table's third column supersedes it; the stored global value silently
remains as the fallback for kinds never edited).

**Tests (append to `Tests/SharinganTests/PomodoroModelsTests.swift`):**

```swift
@Suite("Per-kind long break")
struct PerKindLongBreakTests {
    @Test("override wins over the global value")
    func overrideWins() {
        var s = PomodoroSettings()
        s.activeKind = .big
        s.setConfig(.init(focusMinutes: 90, breakMinutes: 15, longBreakMinutes: 30),
                    for: .big)
        #expect(s.longBreakSeconds == 30 * 60)
    }

    @Test("no override falls back to the global value")
    func fallback() {
        var s = PomodoroSettings()
        s.activeKind = .small
        s.longBreakMinutes = 21
        #expect(s.longBreakSeconds == 21 * 60)
    }

    @Test("pre-per-size config JSON decodes with a nil override")
    func legacyConfigDecodes() throws {
        let json = Data(#"{"focusMinutes":25,"breakMinutes":5}"#.utf8)
        let c = try JSONDecoder().decode(PomodoroKindConfig.self, from: json)
        #expect(c.longBreakMinutes == nil)
    }
}
```

**Steps:** tests first (compile-fail on the new init/field), model change,
table UI, `swift build && swift test` green, update `docs/TECHNICAL.md`
(Timer bullet: per-size long break + table) and the spec's "Later
decisions" (dated entry), commit
`feat(timer): per-size long break; pomodoro sizes as a grid` and push.

---

### Task 11: Pomodoro-type icons in the Tasks composer

*(Added 2026-07-13, user decision: "pomidoro typeni ham tanlash kerak
sozla. 3 xil iconda" — the main-window Tasks composer should let you pick
the new task's pomodoro type via three icons.)*

**Files:**
- Modify: `Sources/Sharingan/Views/TasksView.swift`

**Design:**

1. New state near the other composer `@State`s: `@State private var newKind: PomodoroKind? = nil`.
2. In `detailsPanel`'s estimate+repeat `HStack` (currently `Est … 🍅` +
   `DSStepper` + repeat `Menu`, ~line 722), append after the repeat menu a
   three-icon selector — one tappable icon per `PomodoroKind`
   (`hare.fill` / `timer` / `tortoise.fill` via `kind.systemImage`):

```swift
                HStack(spacing: 2) {
                    ForEach(PomodoroKind.allCases) { kind in
                        Button {
                            newKind = (newKind == kind) ? nil : kind
                        } label: {
                            Image(systemName: kind.systemImage)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(newKind == kind ? Color.white : .white.opacity(0.45))
                                .frame(width: 26, height: 22)
                                .background(
                                    Capsule().fill(newKind == kind
                                        ? Color.dsAccent.opacity(0.45)
                                        : Color.white.opacity(0.06)))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.pressableSubtle)
                        .help("\(kind.label) pomodoro — tap again for Auto")
                    }
                }
```

   (If `Color.dsAccent` doesn't exist, use the same accent the composer's
   active chips use — read `chip(icon:text:active:)` and reuse its active
   fill.) Tapping the selected icon again clears back to nil = Auto.
3. Thread it into task creation: in the `TaskItem(...)` construction in
   the add path (~line 1683), pass `pomodoroKind: newKind` (the initializer
   already has the parameter). Reset `newKind = nil` wherever the other
   composer fields reset after a successful add.
4. No model/store changes; parser (`parsed`) untouched.

**Verification:** `swift build && swift test` green; visual sanity via the
existing dev-preview flag if it renders the task editor/composer, else
reasoning + tests.

**Commit:** `feat(tasks): pomodoro-type icons in the composer` and push.

---

### Task 12: Pomodoro-type badge on task rows

*(Added 2026-07-13, user decision: "pomidoro type ko'rinsin" — a task's
chosen pomodoro type must be visible on its row in the Tasks list.)*

**Files:**
- Modify: `Sources/Sharingan/Views/TasksView.swift` (task row metadata line; subtask rows if they render metadata)
- Possibly: `Sources/Sharingan/Views/TaskComponents.swift` if the row metadata HStack lives there — find the row view that renders the due-date + priority-flag + subtask-progress chips (the screenshot shows `Jul 14, 09:00  ⚑ P2  0/1`) and add the badge THERE, wherever that is.

**Design:**

1. In the task row's metadata HStack (due date, priority, subtask count),
   append — only when `task.pomodoroKind != nil`:

```swift
                if let kind = task.pomodoroKind {
                    HStack(spacing: 3) {
                        Image(systemName: kind.systemImage)
                        Text(kind.label)
                    }
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                }
```

   Match the exact font/opacity idiom of the neighboring metadata chips —
   read them first and mirror (the snippet above is the intent, not the
   letter; if neighbors use a shared chip helper, use it).
2. Auto (nil) shows nothing — no badge noise on default tasks.
3. If subtask rows show per-subtask metadata and `sub.pomodoroKind` exists
   there, add the same icon-only (no label) badge; if subtask rows are
   bare title rows, skip them.
4. No model changes.

**Verification:** `swift build && swift test` green.

**Commit:** `feat(tasks): pomodoro-type badge on task rows` and push.

---

### Task 13: Effective estimate — subtask sum when subtasks exist

*(Added 2026-07-13, user decision: "taskda subtask bo'lmasa pomidoro
estimate qilsin. subtask bo'lsa total sum pomidoro estimate qil" — a task
without subtasks uses its own estimate; a task with subtasks derives its
estimate as the SUM of its subtasks' estimates.)*

**Files:**
- Modify: `Sources/SharinganCore/Models/TaskItem.swift` (computed `effectiveEstimate`)
- Modify: display sites that show a task-level estimate (grep
  `estimatedPomodoros` in `Sources/Sharingan/Views/` — task row 🍅 badges,
  editor summary, menu-bar rows if they show estimates) — switch DISPLAY to
  `effectiveEstimate`; editing paths keep writing `estimatedPomodoros`.
- Modify: `Sources/Sharingan/Views/TasksView.swift` — also clean up Task 11's
  add-path workaround: add a `pomodoroKind: PomodoroKind? = nil` parameter to
  `TaskStore.add(...)` (Sources/SharinganCore/Services/TaskStore.swift:244,
  threaded into the `TaskItem(...)` construction inside), replace the
  tasks.count/tasks.last/update dance in `TasksView.add()` with a direct
  argument. (The workaround is correct today but silently breaks if add()
  ever stops appending.)
- Test: `Tests/SharinganTests/PomodoroModelsTests.swift` or the tasks test
  file that already covers `TaskItem` (find `SubtaskOpsTests.swift` —
  append there if it fits better).

**Model:**

```swift
    /// Estimate shown for the task: its own when it has no subtasks;
    /// otherwise the sum of subtask estimates (falling back to its own
    /// when no subtask carries one).
    public var effectiveEstimate: Int? {
        guard !subtasks.isEmpty else { return estimatedPomodoros }
        let sum = subtasks.compactMap(\.estimatedPomodoros).reduce(0, +)
        return sum > 0 ? sum : estimatedPomodoros
    }
```

**Rules:**
- Display-only change: `estimatedPomodoros` stays the stored, user-edited
  value everywhere (editor stepper, parser, CSV); `effectiveEstimate` is
  what rows/badges/progress show.
- Done-count badges (`🍅 done/est`) use `effectiveEstimate` for the "est"
  half; the "done" half is unchanged.
- Subtask-level badges unchanged.

**Tests:**

```swift
@Suite("Effective estimate")
struct EffectiveEstimateTests {
    @Test("no subtasks → own estimate")
    func ownEstimate() {
        var t = TaskItem(title: "t"); t.estimatedPomodoros = 3
        #expect(t.effectiveEstimate == 3)
    }
    @Test("subtasks with estimates → their sum, own ignored")
    func subtaskSum() {
        var t = TaskItem(title: "t"); t.estimatedPomodoros = 3
        t.subtasks = [Subtask(title: "a", estimatedPomodoros: 2),
                      Subtask(title: "b", estimatedPomodoros: 4)]
        #expect(t.effectiveEstimate == 6)
    }
    @Test("subtasks without estimates → falls back to own")
    func fallbackToOwn() {
        var t = TaskItem(title: "t"); t.estimatedPomodoros = 3
        t.subtasks = [Subtask(title: "a")]
        #expect(t.effectiveEstimate == 3)
    }
    @Test("nothing anywhere → nil")
    func allNil() {
        var t = TaskItem(title: "t")
        t.subtasks = [Subtask(title: "a")]
        #expect(t.effectiveEstimate == nil)
    }
}
```

(Adapt the `TaskItem`/`Subtask` initializers to their real signatures —
read the model first; the test INTENT is binding, the constructor calls are
not.)

**Verification:** `swift build && swift test` green; SelfTest untouched.

**Commit:** `feat(tasks): estimate derives from subtask sum; direct pomodoroKind in add()` and push.
