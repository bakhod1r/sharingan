# Blink — Hisobot

> macOS menu bar pomodoro + break bloklash + eye health app.
> Liquid glass design, Vision-based gaze tracking, floating timer,
> natural-language input, global hotkeys, streak system, CloudKit sync,
> app blocking, screen dim, ambience sounds, posture/water reminders.
> All user-facing strings in English; everything configurable from Settings.

---

## ✅ Bajarildi

### Phase 1 — MVP (PLAN'#1, #2, #3, #8, #9, #11)

- **#1 Skelet** — SwiftPM tri-target: `BlinkCore` (testable logic) + `Blink` (AppKit/SwiftUI executable) + `SelfTest`. `LSUIElement`.
- **#2 Pomodoro** — `PomodoroPhase/Settings/Stats/Timer`, 25/5/15 defaults, `UserDefaults` persistence, long break har 4 cycle, countdown/count-up, 250ms precision loop.
- **#3 Break bloklash** — Multi-monitor `NSPanel`, `.screenSaver` level, `canJoinAllSpaces`, Cmd+Q/W/Tab bloklangan.
- **#8 Break UI** — 88pt timer + chip + motivatsion xabar + mashq animatsiyasi.
- **#9 Notification** — `UNUserNotificationCenter`, 5-daq qoldi alert.
- **#11 Menu bar** — `MenuBarExtra` popover: status, quick input, controls, stats, streak, chart.

### Phase 2 — Eye Health (PLAN'#4, #5, #7)

- **#4 Eye exercise animatsiyalari** — 27 PNG frame (Python/PIL), `EyeExerciseAnimation` (kamera yoq) + `ExerciseSequenceView` (live).
- **#5 Eye blink detection** — `CameraService` AVFoundation `.front` + `AsyncStream`. `EyeTracker` Vision rev2 landmarks, EAR ratio, blink debounce, 1-min window.
- **#7 TTS** — `TTSService` AVSpeechSynthesizer, rate/pitch sliders.
- **Gaze mashqlari (yangi)** — `GazeDirection` 8-dir vector + matches. `BreakExercise` library (20-20-20/gaze/blink). `ExerciseValidator` hold-while-matching + retry. `boundsFromLandmarks()` VNFaceLandmarks bbox workaround.

### Phase 3 — Polish (PLAN'#10, #12, #13)

- **#10 Settings** — Markazlashgan `SettingsView` (480×760): timer mode, theme (5), durations, repeat, break message, block/floating, **exercise sequence toggles + stepHoldScale slider**, **per-instruction text editor**, **global kalib pool** editable, kalib interval slider, camera/Vision, autostart, notifications, sound, TTS rate/pitch, shortcuts legend, streak badge header, iCloud sync UI, brightness section, app blocker section, reminders editor.
- **#12 Long break + auto-start** — 4-cycle, autostart togle.
- **#13 Statistika** — `StreakStore` (consecutive/gap/longest) + `StreakBadge` milestones (1/7/14/30/90/365) + `PomodoroStats.history` per-day + `StreakBadgeView` + `StatsChartView` (SwiftCharts 7d/30d).

### Phase 4 — Super Easy Timer-inspired

- **Natural language parser** — `5 min`/`2h 30m`/`25`/`5pm`/`Add 5 min`/`+5m`/`Remove 1 hour`/`-1h`/`reset`.
- **Global hotkeys** — Carbon `RegisterEventHotKey` + `InstallEventHandler`: ⌃⌥Space/F/R/+/L.
- **Floating timer** — `.floating` + `.nonactivatingPanel`, digital time + label + theme gradient, drag qilinadigan, break'da auto show/hide.
- **Repeat + count-up** — `RepeatConfig` + `TimerMode.countUp`.
- **Alarm sounds** — 3 generated `.caf` (glass/chime/softBell) + silent.

### Phase 4 — Eye health kompanion featurelari

- **Live settings sync** — `BlinkCoordinator` `timer.$settings` subscribe → `syncAll()` (alarm/shortcuts/camera/TTS/ambience/reminders/iCloud/exercise) — Settings o'zgarganda jonli.
- **TTSKalibrator** — settings-driven, step-sinxron instruction + kalib rotation pool.
- **Streak milestone banner** — `StreakRewardCenter` + `StreakRewardBanner` (spring animatsiya), `BlinkCoordinator` `.streakUpdated` catch → reward + notification + TTS.

### Phase 4 — Break comfort

- **#14 Ambience** — `BreakAmbienceService` (silent/whiteNoise/rain/forest/lofi) + 4 generated looping `.caf` + Settings Preview/Stop.
- **#17 Screen brightness** — `BrightnessService` `CGSetDisplayTransferByFormula` gamma ramp (private APIsiz), 1.2s smooth cubic ease, restore on break end.
- **#19 Reminders** — `ReminderItem` (posture/water/custom) + `ReminderSettings` + `ReminderService` interval-based `Task` scheduler, focus-only, break'da pause, `UNNotification`.

### Phase 4 — Multi-device & focus

- **#23 iCloud sync** — `SyncService` CloudKit `CKContainer.default()` → `privateCloudDatabase` → `BlinkZone`. `push/pull` JSON blob, async shim wrappers, Settings Push/Pull UI.
- **#24 App blocking** — `BlockedApp` (6 preset) + `AppBlockerSettings` + `AppBlockerService` `NSWorkspace.didActivateApplication` observer, hide/terminate on frontmost change, kill-existing sweep. Coordinator break-start/stop.

### Assetlar
- AppIcon 16→1024px (PIL) squircle + glass + ring + eye glyph.
- Break icon (green palette) + menu bar templates.
- Animation PNG'frame'lari `Bundle.module`'da.
- 3 alarm + 4 ambience generated `.caf` files.

### Arxitektura
- `BreakPresenter` + `FloatingTimerController` protokollari — core view-layer'ga bog'lanmaydi.
- `BlinkCoordinator` — notification + TTS + floating + break + alarm + kamera + shortcuts + ambience + reminders + iCloud + brightness + app blocker, hammasi jonli.
- Settings cycle: `PomodoroSettings` Codable → `UserDefaults` → iCloud.

### Test — SelfTest 183/183 passed
- Models, timer state machine, add/remove/set/parsed-input.
- Parser (8 duration, clock-target, deltas).
- Count-up mode, repeat config.
- StreakStore + StreakBadge milestones + StreakRewardCenter (no-re-fire, unlocked tracking).
- GazeDirection (magnitude/matches/clamp/labels), BreakExercise library.
- AlarmSound + Ambience enum, BrightnessSettings, AppBlocker settings/presets/matches.
- Codable round-trip.

### Git
```
10d4ded feat(blocker): app blocking during break via NSWorkspace monitor
1cdaed3 docs: update HISOBOT — brightness + iCloud done
b6bb016 feat(sync): iCloud sync via CloudKit + brightness dim on break
b579bef docs: update HISOBOT.md — reminders + ambience done
005c0c5 feat(rewards): streak milestones with badge reward banner + live settings sync
3c4c1c0 docs: update HISOBOT.md
2c4dc03 feat(settings): full English localization + TTS kalib + exercise settings
296283c feat(eye): gaze tracking, exercise validator, camera indicator, floating redesign
2a62434 feat: camera indicator + exercise sequence view
4efbf7a feat(assets): liquid-glass AppIcon, break icon, eye/blink animation
d34dcf7 feat: Blink MVP — pomodoro + floating timer + NL parser + hotkeys
```

---

## ⏳ Qoldi

### Hozirgi navbatda (CLI tool — boshlanmagan)
- **#27 CLI `tired start 25`** — Terminal'dan pomodoro'ni boshqarish. Reja:
  - Yangi `tired` executable target `Package.swift`'ga.
  - Argument parser: `start 25`, `pause`, `resume`, `skip`, `reset`, `status`, `add 5m`.
  - Inter-process comms: `Darwin Notification` + `UserDefaults`'dan state o'qish (no XPC complexity), yoki `NSXPCConnection` lite.
  - stdout: `[Blink] Focus 25:00 ● 12 cycles today`.

### Bekor qilingan
- ~~Slack/Discord break status~~ — scope'dan tashqari.
- ~~Apple Watch heart rate (HealthKit)~~ — scope'dan tashqari.
- ~~#18 Night Shift scheduler~~ — `CoreBrightness` private API xavfi (App Store reject risk).

### Sifat/texnik qoldi
- `CameraService`/`EyeTracker` Swift 6 Sendable ogohlantirishlari — `@preconcurrency` kerak.
- `KeyboardShortcutsService`'da custom key combo settings UI yo'q — hardcoded defaults.
- `AVAudioPlayer` macOS'da priority/mixing control yo'q.
- Alarm `.caf`'lar `Bundle.main`'dan olinadi — BlinkCore'ga resource qo'shilganda `Bundle.module`'ga ko'chirish kerak.
- `PomodoroSettings`'da bir nechta eski flag sintaktik jihatdan qolgan bo'lishi mumkin — audit qilish kerak.

---

## Keyingi navbat
1. **#27 CLI tool** — `tired` executable + Darwin Notification comms.
2. **Quality fixes** — Sendable ogohlantirishlari, custom hotkey UI.
3. **Documentation** — README.md + AGENTS.md (build/test/lint kommandalar).