# Blink

> A macOS menu bar Pomodoro + eye-health app with liquid-glass design,
> Vision-based gaze tracking, floating timer, natural-language input,
> global hotkeys, streak system, CloudKit sync, app blocking, screen
> dim, ambience sounds, and a `tired` CLI.

Pure SwiftPM — no Xcode project required.

---

## Features

### Pomodoro core
- Configurable focus / short break / long break durations (25/5/15 defaults)
- Countdown and count-up modes
- Long break every N pomodoros
- Auto-start focus / break toggles
- Repeat with delay
- Persistent state via `UserDefaults`

### Break blocking
- Full-screen multi-monitor `NSPanel` at `.screenSaver` level
- Cmd+Q / Cmd+W / Cmd+Tab blocked during break
- Liquid-glass countdown ring + phase chip + motivational message
- Skip button

### Eye health
- **Eye exercise animations** — 20-20-20 rule, 8-direction gaze, blink exercise
- **Camera blink detection** — AVFoundation + Vision face landmarks, eye-openness ratio, blink count
- **Gaze tracking** — `GazeDirection` vector, exercise validator with retry signal
- **Camera indicator badge** — pulsing privacy UI
- **TTS voice guidance** — per-step instruction text + rotating kalib pool, settings-driven

### Floating timer
- Always-on-top `.floating` panel, joins all Spaces
- Digital time + uppercased phase label + theme gradient
- Draggable, auto show/hide on break

### Natural language input
- `5 min`, `2h 30m`, `25` (=25 min), `5pm`, `Add 5 min`, `+5m`, `Remove 1 hour`, `-1h`, `reset`

### Global keyboard shortcuts
- ⌃⌥Space — start/pause
- ⌃⌥F — skip
- ⌃⌥R — reset
- ⌃⌥+ — +5 minutes
- ⌃⌥L — toggle floating timer

### Streaks & rewards
- Consecutive-day streak tracking with gap reset
- Milestone badges: 1, 7, 14, 30, 90, 365 days
- Spring-animated reward banner on new milestone
- SwiftCharts 7/30-day statistics

### Break comfort
- **Ambience sounds** — white noise, rain, forest, lo-fi pad (generated `.caf`, looping)
- **Screen brightness dim** — gamma ramp via `CGSetDisplayTransferByFormula`, smooth cubic ease
- **Posture / water / custom reminders** — interval-based, focus-only, pause during break

### Multi-device
- **iCloud sync** — CloudKit `CKContainer` → private DB → `BlinkZone`, JSON blob push/pull

### Focus enforcement
- **App blocking** — hide or force-quit distracting apps during break (Chrome, Safari, VS Code, Slack, Telegram, Messages presets)

### CLI
- `tired` command-line tool — control Blink from Terminal

### Themes
- Liquid Glass, Frosted, Midnight, Cream, Neon

### Sharingan eye style
- Premium anime-style eye animation during breaks — red iris, rotating tomoe, glossy highlight, red glow, breathing, blink

---

## Build & run

```bash
swift build                 # build all targets
swift run Blink             # launch the menu bar app
swift run SelfTest          # run 183 assertion tests
swift run tired status      # CLI: show current timer state
```

### Release build

```bash
swift build -c release
```

---

## `tired` CLI

```bash
tired start 25            # 25-minute focus
tired start 5pm           # until 5:00 PM
tired start 2h 30m        # 2.5 hours
tired pause               # pause
tired resume              # resume
tired skip                # skip to next phase
tired reset               # stop & reset
tired add 5m              # +5 minutes
tired remove 10m          # -10 minutes
tired set 45m             # set custom duration
tired status              # show current state
tired help                # usage
```

The CLI communicates with the running app via Darwin notifications +
`UserDefaults` snapshot — no XPC required.

---

## Project layout

```
Package.swift
Sources/
  BlinkCore/              # testable logic + services
    Models/               # PomodoroSettings, StreakStore, BreakExercise, …
    Services/             # PomodoroTimer, EyeTracker, CameraService, SyncService, …
  Blink/                  # SwiftUI/AppKit executable (the .app)
    Views/                # SettingsView, BreakView, FloatingTimerView, SharinganEyeView, …
    Services/             # window managers (break / floating)
    Resources/            # Animations, Sharingan PNGs → Bundle.module
  SelfTest/               # standalone assertion harness (swift run SelfTest)
  tired/                  # `tired` CLI executable
Resources/                # Info.plist + AppIcon.appiconset + Sounds/
```

---

## Settings

Everything is configurable from a single Settings screen:

- Timer mode (countdown / count-up) + theme
- Focus / break durations + long-break cycle
- Repeat with delay
- Break message text
- Block screen + floating timer toggles
- Eye exercise sequence (20-20-20 / gaze / blink) + step hold scale
- Per-instruction TTS text editor + global kalib pool + kalib interval
- Camera & Vision toggle
- Auto-start focus / break
- Notifications (5-min left)
- Alarm sound (glass / chime / soft bell / silent)
- TTS voice rate / pitch
- Global shortcuts toggle
- Streak badge header
- iCloud sync (enable + Push/Pull + status)
- Screen brightness dim (enable + level + smooth)
- App blocking (enable + force-quit + per-app toggles)
- Reminders (posture / water / custom — add / remove / interval / message)

---

## Tests

```bash
swift run SelfTest
```

183 assertions covering:
- Pomodoro models, timer state machine, add/remove/set/parsed-input
- Natural language parser (durations, clock-target, deltas)
- Count-up mode, repeat config
- StreakStore, StreakBadge milestones, StreakRewardCenter
- GazeDirection, BreakExercise library
- AlarmSound + Ambience enum, BrightnessSettings, AppBlocker settings
- Codable round-trip

---

## Tech stack

- Swift 5.9+, SwiftUI, AppKit, macOS 13+
- Vision (face/eye landmarks), AVFoundation (camera + TTS + audio)
- UserNotifications, CloudKit, Carbon (global hotkeys)
- SwiftCharts (statistics)
- Pure SwiftPM — no Xcode project

---

## License

Private.