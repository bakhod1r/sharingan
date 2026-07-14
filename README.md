<p align="center">
  <img src="Resources/AppIcon.appiconset/icon_256.png" width="128" alt="Sharingan app icon">
</p>

<h1 align="center">Sharingan</h1>

<p align="center"><b>Pomodoro &amp; eye-health for macOS</b><br>
A menu-bar Pomodoro timer, a full task manager, and guided eye exercises — in one liquid-glass app.</p>

<p align="center">
  <a href="https://github.com/bakhod1r/sharingan/releases/latest"><img src="https://img.shields.io/github/v/release/bakhod1r/sharingan?color=E5484D" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white" alt="Swift 5.9+">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/bakhod1r/sharingan?color=3E63DD" alt="MIT license"></a>
</p>

<p align="center">
  <a href="https://bakhod1r.github.io/Blink/"><b>Website</b></a> ·
  <a href="https://github.com/bakhod1r/sharingan/releases/latest"><b>Download</b></a> ·
  <a href="CHANGELOG.md"><b>Changelog</b></a> ·
  <a href="docs/TECHNICAL.md"><b>Full feature reference</b></a>
</p>

<p align="center">
  <img src="site/assets/app/iris/classic.png" width="56" alt="Classic iris">
  <img src="site/assets/app/iris/tomoe2.png" width="56" alt="Tomoe iris">
  <img src="site/assets/app/iris/mangekyou.png" width="56" alt="Mangekyou iris">
  <img src="site/assets/app/iris/itachi.png" width="56" alt="Itachi iris">
  <img src="site/assets/app/iris/madara.png" width="56" alt="Madara iris">
  <img src="site/assets/app/iris/rinnegan.png" width="56" alt="Rinnegan iris">
  <br><sub>18 Sharingan iris styles, rendered by the app itself</sub>
</p>

---

Sharingan protects your eyes while you work: focus in Pomodoro blocks, then the
screen locks for a real break with guided eye drills — optionally verified by
the camera. A complete task system with natural-language input (English +
Uzbek) keeps the work itself organized.

> Formerly known as **Blink** — you may still see the old name in the site URL
> and history. Pure SwiftPM — no Xcode project required.

## Install

**Download** — grab `Sharingan.dmg` from the
[latest release](https://github.com/bakhod1r/sharingan/releases/latest) and drag
the app into Applications.

Builds are not notarized yet: on first launch, right-click the app →
**Open** (or run `xattr -cr /Applications/Sharingan.app`).

**Build from source** — requires macOS 14+ and Xcode command-line tools:

```bash
git clone https://github.com/bakhod1r/sharingan.git && cd sharingan
Scripts/install.sh          # build dist/Sharingan.app and install to /Applications
Scripts/install-cli.sh      # optional: put the `tired` CLI on your PATH
```

## Highlights

- **Pomodoro, three gears** — Small `10′+3′`, Normal `25′+5′`, Big `90′+15′`
  (each editable), countdown or count-up, auto-cycle, long breaks every N
  pomodoros, `±5m` on the fly.
- **Enforced breaks** — full-screen, multi-monitor break screen at screen-saver
  level; ⌘Q/⌘W/⌘Tab are swallowed until the break ends (skippable if you allow it).
- **Eye health** — 20-20-20, 8-direction gaze, and blink drills with animated
  guides and voice guidance; optional **camera verification** of blinks and gaze
  via Vision, with a privacy indicator. Break eyes render as animated Sharingan —
  18 iris styles from classic tomoe to Rinnegan.
- **Tasks & planning** — natural-language quick add in English and Uzbek
  (`ertaga 15:00 p1 #ish ~2 hisobot yozish`), priorities, projects, tags, due
  dates, subtasks, recurrence, templates; a focus queue that advances task by
  task; Eisenhower matrix, weekly board, reports and per-project stats.
- **Six surfaces** — menu-bar popover, main window, notch HUD with live "ears",
  draggable floating pill timer, desktop WidgetKit widget, and a glass Today
  panel on the desktop.
- **Streaks & stats** — daily streaks with milestone badges (1→365 days),
  SwiftCharts history, tomato counts per task.
- **Break comfort** — ambience sounds (white noise, rain, forest, lo-fi),
  smooth screen dim, optional Night Shift warmth, posture/water/custom reminders.
- **Focus enforcement** — hide or force-quit distracting apps during breaks
  (Chrome, Slack, Telegram… presets included).
- **Automation** — global hotkeys (⌃⌥Space start/pause, ⌃⌥F skip, ⌃⌥R reset),
  `sharingan://` URL scheme for Shortcuts/Raycast, and the `tired` CLI.
- **Six themes** — Liquid Glass, Frosted, Midnight, Cream, Neon, Mono.

iCloud sync is planned but **not shipped yet** — everything is local today.
The complete, always-current feature list lives in
[docs/TECHNICAL.md](docs/TECHNICAL.md).

## `tired` — control it from the terminal

```bash
tired start 25            # 25-minute focus
tired start 5pm           # focus until 5:00 PM
tired pause / resume      # pause & resume
tired skip / reset        # next phase / stop
tired add 5m              # +5 minutes
tired status              # current state
tired task add "ertaga p1 #ish hisobot"   # NL quick add
tired task list           # numbered open tasks
tired task start 3        # make task #3 active
tired task queue 3        # queue task #3 for focus
```

The CLI talks to the running app via Darwin notifications + a `UserDefaults`
snapshot — no XPC required.

## Development

```bash
make build          # debug build of all targets
make run            # launch the menu-bar app from source
make test           # swift-testing suites (plus: swift run SelfTest)
make app            # assemble dist/Sharingan.app (icon, widget appex, codesign)
make dmg            # wrap it into dist/Sharingan.dmg
make open           # build the .app and launch it
```

```
Package.swift
Sources/
  SharinganCore/       # testable logic — models + services (timer, tasks, streaks, eye tracking)
  Sharingan/           # SwiftUI/AppKit executable (the .app)
  SharinganWidget/     # WidgetKit desktop widget (built into the appex by make-app.sh)
  tired/               # `tired` CLI executable
  SelfTest/            # standalone assertion harness
Tests/                 # swift-testing suites
Resources/             # Info.plist, entitlements, AppIcon, sounds
Scripts/               # make-app.sh, make-dmg.sh, install.sh
site/                  # marketing site (GitHub Pages)
```

Releases are automated: pushing a `v*` tag builds the DMG on a macOS runner
and attaches it to the GitHub release, with notes taken from the changelog.

**Tech stack** — Swift 5.9+, SwiftUI + AppKit, WidgetKit, Vision (face/eye
landmarks), AVFoundation (camera, TTS, audio), SwiftCharts, Carbon global
hotkeys. Pure SwiftPM.

## Contact

Bakhodir Yashin Mansur — bakhodiryashinmansur@gmail.com

## License

[MIT](LICENSE) © 2026 Bakhodir Yashin Mansur
