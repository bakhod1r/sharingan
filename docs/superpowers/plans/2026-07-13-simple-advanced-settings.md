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
