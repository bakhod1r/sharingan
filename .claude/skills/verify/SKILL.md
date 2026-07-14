---
name: verify
description: Build, launch, and drive Sharingan.app to verify changes at runtime — timer via sharingan:// URLs, widget via its container snapshot + chronod's database, state via the tired CLI
---

# Verifying Sharingan changes at runtime

## Build & launch

```bash
Scripts/make-app.sh              # release build → dist/Sharingan.app (also builds+signs the widget appex)
open dist/Sharingan.app          # LSUIElement app: menu-bar icon + main window on launch
```

**Gotcha — stale instance:** an older build may already be running. Check
`ps -p $(pgrep -f "dist/Sharingan.app") -o lstart=` against the binary's
mtime; if older, quit it first or you'll verify code that isn't there:
`osascript -e 'tell application "Sharingan" to quit'` (blocks on a confirm
dialog if a focus session is running — check state first, see below).

**Gotcha — concurrent sessions:** other agent sessions may be rebuilding
`dist/` or editing the tree while you verify (see the user's
blink-concurrent-sessions memory). Capture evidence promptly; re-check
`git log` before attributing behavior to a build.

## Drive

- Timer engine (same path as widget taps / Shortcuts): `open "sharingan://start"`,
  `pause`, `resume`, `skip`, `reset`, `show`, `start?minutes=N`.
- Read live state: `.build/arm64-apple-macosx/debug/tired status` (build with
  `swift build` if missing).
- Tasks: `tired` CLI (`task add`, `list`, `start`, …).

## Observe

- **Widget snapshot** (written by WidgetSnapshotPublisher ~0.4 s after any
  state change): canonical copy since 1.19.0 is
  `~/Library/Containers/com.sharingan.app.widget/Data/Library/Application Support/widget-snapshot.json`;
  the app-group copy (`~/Library/Group\ Containers/group.com.sharingan.app/…`)
  is still written but the ad-hoc appex CANNOT read it (macOS 26 rejects
  team-ID-less claims on TCC-protected group containers). While a session
  simply ticks, the file is deliberately NOT rewritten (fingerprint filter) —
  an unchanged mtime during a running session is correct.
- **Widget in the gallery:** pluginkit registration
  (`pluginkit -m -v -p com.apple.widgetkit-extension | grep -i sharingan`)
  is necessary but NOT sufficient — chronod must also ingest descriptors.
  Ground truth: a `com.sharingan.app.widget` row in
  `sqlite3 "file:$HOME/Library/Group Containers/group.com.apple.chronod/chronod/chrono.sql?mode=ro" "SELECT * FROM ExtensionMetadata"`
  = listed in the gallery; the widget named in
  `defaults read com.apple.chronod extensionsPendingDescriptorRefetch`
  = descriptor query failing (`killall chronod` retries; watch it with
  `/usr/bin/log show --last 5m --predicate 'process == "SharinganWidget" OR (process == "chronod" AND eventMessage CONTAINS "sharingan")'`
  — full `/usr/bin/log` path, bare `log` is shadowed by a zsh builtin).
  There is no CLI to place a widget; rendered-pixels checks are the user's step.
- Appex smoke test: running the appex binary directly should abort with
  `An XPC Service cannot be run directly.` — dyld loaded and the
  `_NSExtensionMain` entry is in place (make-app.sh links `-e _NSExtensionMain`
  explicitly; a plain Swift `@main` entry boots then exit(0)s under chronod
  and the widget never reaches the gallery). `Unrecognized extension type`
  or a dyld missing-symbol error is a real defect.
- Stats blob (day counts, streak):
  `defaults export com.blink.app - | python3 -c "import plistlib,sys; print(plistlib.loads(sys.stdin.buffer.read())['com.sharingan.stats'].decode())"`

## Clean up

Leave the timer idle (`open "sharingan://reset"`) so no test session pollutes
stats; a completed test pomodoro would credit the user's real daily count.
