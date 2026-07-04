# Blink — Hisobot

> macOS menu bar pomodoro + break bloklash + eye health app.
> Liquid glass design, Vision-based gaze tracking, floating timer,
> natural-language input, global hotkeys, streak system.
> All user-facing strings localized to English; everything configurable
> from a single Settings screen.

---

## ✅ Bajarildi

### Phase 1 — MVP (PLAN'#1, #2, #3, #8, #9, #11)

**#1 Skelet**
- SwiftPM `BlinkCore` (testable) + `Blink` (AppKit/SwiftUI executable) + `SelfTest`.
- `LSUIElement = true` (menu bar app).

**#2 Pomodoro taymeri**
- `PomodoroPhase`, `PomodoroSettings`, `PomodoroStats`, `PomodoroTimer`.
- 25/5/15 default, `UserDefaults` persistence, long break har 4 pomodoro.
- Countdown/count-up mode, 250ms precision loop.

**#3 Break bloklash oynasi**
- Multi-monitor `NSPanel`, `.screenSaver` level, `canJoinAllSpaces`.
- Cmd+Q/Cmd+W/Cmd+Tab bloklangan.

**#8 Break matn + countdown**
- `BreakView`: 88pt timer, faza chip, settings日消息.

**#9 5 daq notification**
- `NotificationService` `UNUserNotificationCenter`.

**#11 Menu bar status**
- `MenuBarExtra` popover — status header, quick input, controls, stats,
  streak badge, SwiftCharts grafik.

### Phase 2 — Eye Health (PLAN'#4, #5, #7)

**#4 Eye exercise animatsiyalari**
- 27 PNG frame (9 gaze + 9 blink) generated via Python/PIL.
- `EyeExerciseAnimation` (kamera o'chgan) → raster frame tsikl.
- `ExerciseSequenceView` (kamera yoqilgan) → live mashq UI face-not-detected/ retry alertlari bilan.

**#5 Eye blink detection**
- `CameraService`: AVFoundation `.front` camera, `AsyncStream<CVImageBuffer>`.
- `EyeTracker`: `VNDetectFaceLandmarksRequest` rev2, eye openness ratio (EAR-approximation),
  blink count with 0.15s debounce, 1-min window.
- `GazeDirection`: 8-direction vector + `matches(tolerance:)` + label + clamp.
- `CameraIndicatorBadge` — pulsing green privacy indicator.

**#7 TTS voice guidance**
- `TTSService` `AVSpeechSynthesizer`, rate/pitch sliders.
- `TTSKalibrator` — settings-driven, step-sinxron, per-instruction text + rotation pool.

### Phase 2.5 — Gaze mashqlari (yangi)
- `GazeDirection` model + `EyeTracker.lastGazeDirection` — landmark centroid'laridan face-center bilan farqi.
- `BreakExercise` + `BreakExerciseStep` — 20-20-20 / gaze 8-dir / blink library.
- `ExerciseValidator` — hold-while-matching, retry signal, advance automation.
- `bnitsFromLandmarks()` — `VNFaceLandmarks2D`'siz face bounds (landmark points union).

### Phase 3 — Polish (PLAN'#10, #12, #13)

**#10 Sozlamalar — markazlashgan**
- `SettingsView` 480×760 — bitta ekran:
  - Timer mode (countdown/count-up) + theme (5)
  - Durations (focus/short/long/longBreakEvery)
  - Repeat (enable/count/delay)
  - Block screen + floating timer
  - **Exercise sequence** — 20-20-20/gaze/blink toggles + stepHoldScale slider
  - **Per-instruction text editor** — direction chips → text field
  - **Global kalib pool** — editable list with add/remove
  - **Kalib interval** slider (0-60s)
  - Camera & Vision toggle + privacy note
  - Auto-start (focus/break)
  - Notifications
  - Sound (alarm toggle + picker)
  - TTS (enabled flag + voice rate/pitch)
  - Global shortcuts toggle + legend
  - Streak badge header (live)

**#12 Long break + auto-start**
- 4-pomodoro cycle, long/short break auto-start togle.

**#13 Statistika**
- `StreakStore` (consecutive days, gap reset, idempotent, longest).
- `StreakBadge` milestones (1/7/14/30/90/365 days) + earned/next helpers.
- `PomodoroStats.history` — per-day counts + `recentDays(n)` + `weeklyAverage`.
- `StreakBadgeView` — current/longest header + next-milestone progress + earned chips.
- `StatsChartView` — SwiftCharts 7d/30d bars, weekly average.

### Phase 4 — Super Easy Timer-inspired features

**Natural language parser** (`NaturalLanguageParser`)
- `5 min`/`5min`/`20 minutes`/`2h 30m`/`2h30m`/`90 seconds`/`25`/`1h`.
- `5pm`/`2:15am` → clock-target.
- `Add 5 min`/`+5m`/`Remove 1 hour`/`-1h` → delta.
- `reset`/`stop`.

**Global hotkeys** (`KeyboardShortcutsService`)
- Carbon `RegisterEventHotKey` + `InstallEventHandler` + `@convention(c)` callback.
- ⌃⌥Space/F/R/+/L.

**Floating timer** (`FloatingWindowManager` + `FloatingTimerView`)
- `.floating` level, `canJoinAllSpaces`, `.nonactivatingPanel`.
- Digital time (30pt) + uppercased phase label + theme gradient background/ring/accent.
- 168×86 px, drag qilinadigan, break'da avtomatik show/hide.

**Repeat + count-up**
- `RepeatConfig` (count + delay + `delaysTotal`).
- `TimerMode.countUp` elapsed → progress reverse.

**Alarm sounds** (`AlarmSoundService`)
- 3 generated `.caf` (glass/chime/softBell) + silent.

### Assetlar
- AppIcon 16→1024px (PIL) — squircle radial gradient + glass disc + countdown ring + eye glyph.
- Break icon (green palette) + menu bar templates (16/32/64).
- Animatsiya PNG'frame'lari `Bundle.module`'da.

### Arxitektura
- `BreakPresenter` + `FloatingTimerController` protokollari — core view-layer'ga bog'lanmaydi.
- `BlinkCoordinator` — notification + TTS + floating + break + alarm + kamera + shortcuts.
- Settings cycle: `PomodoroSettings` Codable → `UserDefaults`; `BlinkCoordinator.syncAlarm/syncCamera/installShortcuts`.

### Test — SelfTest 123/123 passed
- Models (phase/mode/theme/gradient).
- Timer (initial/skip/stop/add/remove/custom/parsed-input).
- Parser (8 duration formats, 5pm clock-target, 4 add/remove directives).
- Count-up mode progress.
- Repeat config (floors + delaysTotal).
- **StreakStore** (consecutive/gap/same-day/longest).
- Stats + streak integration.
- AlarmSound enum.
- **GazeDirection** (magnitude/matches/clamp/8-direction labels).
- **BreakExercise** (step targets/auto-instruction/library).
- Codable round-trip.

### Git
```
2c4dc03 feat(settings): full English localization + TTS kalib + exercise settings
296283c feat(eye): gaze tracking, exercise validator, camera indicator, floating redesign
2a62434 feat: camera indicator + exercise sequence view
4efbf7a feat(assets): liquid-glass AppIcon, break icon, eye/blink animation
d34dcf7 feat: Blink MVP — pomodoro + floating timer + NL parser + hotkeys
```

---

## ⏳ Qoldi

### Hozirgi flux'da yarim
- **`ExerciseValidator`'da foydalanuvchi tomonidan sozlanadigan instruction'lar** — TTSKalibrator settings'dan o'qiymaydi; tester settings change'da hozir runtime re-attach talab qiladi (BreakView onDisappear/appear trigger'lari). Settings'da apply button yoki `BlinkCoordinator.observe($settings)` qo'shilsa fully live.
- **`ttşSettings.enabled` vs `ttsEnabled`** — PomodoroSettings'da ikkalala ham bor (eski `ttsEnabled` ham, yangi `ttsSettings.enabled` ham). Coordinator eski `ttsEnabled`'ni ishlatadi. Obsolete bo'lib qoldi, hal qilishim kerak.

### Phase 2 — qolgan
- Hech narsa (gaze + blink + TTS yakunlangan).

### Phase 3 — qolgan
- ~~Posture/water reminder (#19)~~ — **yakunlandi**: `ReminderService` (posture/water/custom) + interval-based UNNotification firing + break'da pause + Settings ReminderRows boshqaruvi.

### Phase 4 — qolgan features
- ~~#14 Break music / white noise / nature sounds~~ — **yakunlandi**: `BreakAmbienceService` (5 ambience) + 4 generated looping `.caf` files + Settings Preview/Stop buttons.
- ~~#17 Screen brightness auto~~ — **yakunlandi**: `BrightnessService` (CGSetDisplayTransferByFormula gamma ramp, 1.2s smooth cubic ease) + Settings toggle/slider/smooth.
- **#18 Night Shift scheduler** (CoreBrightness private) yo'q.
- **#22 Raycast/Alfred/Stream Deck** yo'q.
- ~~#23 iCloud sync + multi-device~~ — **yakunlandi**: `SyncService` CloudKit CKContainer + BlinkZone + CKRecord JSON blob sync (push/pull) + Settings status/trigger UI.
- **#24 App bloklash break'da** (Telegram/YouTube force quit) — faqat window bloklaydi.
- **#27 CLI `tired start 25`** yo'q.
- ~~Slack/Discord~~ — bekor qilindi.
- ~~Apple Watch heart rate (HealthKit)~~ — bekor qilindi.

### Sifat/texnik qoldi
- `CameraService`/`EyeTracker` Sendable ogohlantirishlar (Swift 6 mode'da error) — `@preconcurrency` kerak.
- `KeyboardShortcutsService`'da custom key combo settings UI yo'q — hardcoded defaults.
- `AVAudioPlayer` macOS'da `AVAudioSession` yo'qligi uchun priority/mixing control yo'q.
- Alarm `.caf`'lar BlinkCore'da `Bundle.main`'dan olinadi; BlinkCore'ga resource qo'shilganda `Bundle.module`'ga ko'chirish kerak.

---

## Keyingi navbat
1. **`ttsEnabled` obsolescence fix** — `ttsSettings.enabled`'ga birlashtir + coordinator settings-publish observe.
2. **Settings apply button / live re-attach** — o'zgarganda break'dagi mashq ketma-ketligi hamjonkT.
3. **TTS kalib Router** — mashqlar bilan.
4. **Streak badge'lar** (mukofot tizimi #16 qismi).
5. **SwiftCharts statistik** (#15).