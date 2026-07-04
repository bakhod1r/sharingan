# Blink

A liquid-glass **Pomodoro + eye-health** menu bar app for macOS. Blink runs a
focus/break timer, blocks the screen during breaks, guides eye exercises with
optional camera-based gaze/blink tracking, speaks instructions aloud, and ships
with a floating timer, natural-language input, global hotkeys, streaks, iCloud
sync, screen dimming, app blocking, reminders, and a `tired` CLI.

> macOS 13+ · Swift 5.9+ · SwiftUI + AppKit · menu-bar agent (`LSUIElement`)

---

## Quick start

```bash
# Run from source (menu bar agent; no Dock icon)
swift run Blink

# Build a distributable app bundle → dist/Blink.app
Scripts/make-app.sh
cp -R dist/Blink.app /Applications/

# Install the CLI on your PATH
Scripts/install-cli.sh        # → /usr/local/bin/tired
tired start 25
```

Launch-at-login and login-item registration require the packaged **`Blink.app`**
(SMAppService only works from a LaunchServices-known bundle).

---

## Features

- **Pomodoro timer** — focus / short break / long break, configurable durations,
  long break every N cycles, countdown or count-up, repeat config, auto-start.
- **Break blocking** — full-screen, multi-monitor, `.screenSaver`-level panels
  that span Spaces and swallow ⌘-shortcuts.
- **Eye health** — 20-20-20 rule, gaze/blink exercise sequences with animated
  guidance and optional camera (Vision) validation + retry.
- **Voice guidance (TTS)** — spoken, step-synced instructions with rate/pitch.
- **Comfort** — break ambience sounds, screen dimming (gamma ramp), posture/water
  reminders, app blocking during breaks.
- **Input & control** — natural-language quick input (`5 min`, `2h 30m`, `5pm`,
  `+5m`, `-1h`, `reset`), customizable global hotkeys, floating timer, `tired` CLI.
- **Progress** — daily stats, weekly chart, streaks with milestone badges.
- **Sync** — iCloud (CloudKit) settings & stats.

Everything is configurable from **Settings** (⌘,).

---

## CLI (`tired`)

```
tired start [duration]   Start focus (default 25); '5 min', '2h 30m', '5pm', '15'
tired pause | resume | skip | reset
tired add [dur]          Add time (default 5m)
tired remove [dur]       Remove time (alias: rm)
tired set [dur]          Set custom duration
tired status             Print current timer state
tired help | version
```

The CLI talks to the running app via Darwin notifications; the app writes a state
snapshot to `UserDefaults` that `tired status` reads back.

---

## Global hotkeys (defaults)

| Action | Combo |
|--------|-------|
| Start / pause | ⌃⌥Space |
| Skip | ⌃⌥F |
| Reset | ⌃⌥R |
| +5 minutes | ⌃⌥= |
| Toggle floating timer | ⌃⌥L |

Rebind any of them in **Settings → Global shortcuts** (click a combo, press new
keys; needs at least one modifier).

---

## Build, test, run

```bash
swift build                 # debug build of all targets
swift test                  # swift-testing suites (BlinkCore)
swift run SelfTest          # extended manual self-test harness
swift run Blink             # launch the app
swift run tired status      # run the CLI
Scripts/make-app.sh         # package dist/Blink.app (release)
Scripts/make-dmg.sh         # package dist/Blink.dmg (drag-install image)
Scripts/install-cli.sh      # symlink `tired` onto PATH
```

See [AGENTS.md](AGENTS.md) for repository layout and contributor conventions.

---

## Permissions

- **Camera** (AVFoundation + Vision) — eye/gaze tracking, break-time only, opt-in.
- **Notifications** (UserNotifications) — "5 minutes left", break start/end.
- **iCloud** (CloudKit) — optional settings/stats sync.

Usage descriptions live in `Resources/Info.plist`.
