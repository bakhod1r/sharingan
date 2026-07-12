# AGENTS.md

Guidance for humans and AI agents working in this repository.

## What this is

Sharingan — a macOS menu bar Pomodoro + eye-health app. Pure SwiftPM (no Xcode
project). See [README.md](README.md) for the feature tour.

## Layout

```
Package.swift            # 4 build targets + 1 test target
Sources/
  SharinganCore/         # platform-agnostic logic + services (unit-tested)
    Models/              # PomodoroSettings, StreakStore, ShortcutBinding, …
    Services/            # PomodoroTimer, EyeTracker, CameraService, CLIBridge, …
    Resources/Sounds/    # alarm_*.caf, ambience_*.caf  → Bundle.module
  Sharingan/             # SwiftUI/AppKit executable (the .app)
    Views/               # SettingsView, BreakView, ShortcutRecorder, …
    Services/            # window managers (break / floating)
    Resources/           # Animations, MenubarIcons  → Bundle.module
  SelfTest/              # standalone assertion harness (`swift run SelfTest`)
  tired/                 # `tired` CLI executable
Tests/SharinganTests/    # swift-testing suites (import SharinganCore)
Resources/               # Info.plist + AppIcon.appiconset (for the .app bundle)
Scripts/                 # make-app.sh, make-dmg.sh, install-cli.sh
```

Targets: `SharinganCore` (library) → depended on by `Sharingan`, `SelfTest`, `tired`,
and `SharinganTests`.

## Commands

```bash
swift build                 # build all targets (must stay warning-clean)
swift test                  # swift-testing suites
swift run SelfTest          # extended self-test (prints "SELF-TEST PASSED")
swift run Sharingan         # launch the menu bar app
Scripts/make-app.sh         # → dist/Sharingan.app (release, ad-hoc signed)
Scripts/make-dmg.sh         # → dist/Sharingan.dmg (calls make-app.sh first)
Scripts/install-cli.sh      # symlink `tired` onto PATH
```

There is no separate lint step; **keep `swift build` free of warnings**.

## Conventions

- **Where code goes:** anything testable or shared belongs in `SharinganCore`.
  Only SwiftUI/AppKit views and window plumbing live in `Sharingan`.
- **Resources:** runtime assets ship via `Bundle.module`. Sounds are in
  `SharinganCore/Resources/Sounds`; animations/icons in `Sharingan/Resources`. Do not
  read from `Bundle.main` — it's empty when run unbundled.
- **Settings:** every user-facing option is a field on `PomodoroSettings`
  (`Codable`, persisted to `UserDefaults`, optionally iCloud-synced) and must
  have a control in `SettingsView`. Live changes flow through
  `SharinganCoordinator.syncAll()`.
- **Concurrency:** services are `@MainActor`. Off-main callbacks (capture
  delegate, Carbon hotkeys, Timers) hop back via `MainActor.assumeIsolated`
  or a `Sendable` holder; keep the build data-race-clean.
- **Tests:** add swift-testing cases under `Tests/SharinganTests` for new
  `SharinganCore` logic; mirror anything hard to unit-test in `SelfTest`.

## Gotchas

- `SMAppService` (launch-at-login) and `LSUIElement` only take effect from the
  packaged `Sharingan.app`; running via `swift run` uses a runtime `.accessory`
  activation policy instead.
- The `tired` CLI and app communicate via Darwin notifications +
  `UserDefaults` snapshot — no XPC.
- `Date.now()`/timers make some behavior time-dependent; pass an explicit
  `Calendar`/`now` where the API allows (see `StreakStore`, parser tests).