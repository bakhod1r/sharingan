---
name: verify
description: Build, launch, and drive Sharingan.app to verify changes at runtime — timer via sharingan:// URLs, widget via the group-container snapshot, state via the tired CLI
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
  state change): `cat ~/Library/Group\ Containers/group.com.sharingan.app/widget-snapshot.json`
  (`group.com.blink.app` before the 1.13.0 bundle-id rename). While a session
  simply ticks, the file is deliberately NOT rewritten (fingerprint filter) —
  an unchanged mtime during a running session is correct.
- **Widget registration:** `pluginkit -m -v -p com.apple.widgetkit-extension | grep -i sharingan`.
  The appex process only runs after a human places the widget (desktop →
  right-click → Edit Widgets); there is no CLI to place one, and screencapture /
  System Events are permission-blocked for agent hosts — rendered-pixels checks
  are the user's step.
- Appex smoke test: running the appex binary directly should die with
  `ExtensionFoundation … Unrecognized extension type` — that means dyld and the
  extension runtime loaded; anything else (dyld missing symbol) is a real defect.
- Stats blob (day counts, streak):
  `defaults export com.blink.app - | python3 -c "import plistlib,sys; print(plistlib.loads(sys.stdin.buffer.read())['com.sharingan.stats'].decode())"`

## Clean up

Leave the timer idle (`open "sharingan://reset"`) so no test session pollutes
stats; a completed test pomodoro would credit the user's real daily count.
