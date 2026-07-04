# Blink — Hisobot

> macOS menu bar pomodoro + break bloklash + eye health app.
> Liquid glass design, Vision-based gaze tracking, suzuvchi taymer,
> natural-language input, global hotkeys, streak tizimi.

---

## ✅ Bajarildi

### Phase 1 — MVP (PLAN'dagi #1, #2, #3, #8, #9, #11)

**#1 Skelet**
- SwiftPM `Package.swift`: `BlinkCore` (testable logic) + `Blink` (executable, AppKit/SwiftUI) + `SelfTest` (test runner) ajratilgan.
- `LSUIElement = true` Info.plist (menu bar app).
- Folder structure: `Models/`, `Services/`, `Views/`, `Resources/`.

**#2 Pomodoro taymeri**
- `PomodoroPhase` (.focus/.shortBreak/.longBreak/.paused), `PomodoroSettings`, `PomodoroStats`, `PomodoroTimer`.
- 25/5/15 default, konfiguratsiyalanadigan, `UserDefaults` orqali persistence, long break har 4 pomodoro'dan keyin.
- Auto-start togle (focus/break alohida).
- `Task.sleep(250ms)` precision loop, count-down/count-up rejimlar.

**#3 Break bloklash oynasi**
- Multi-monitor `NSPanel`'lar, `.screenSaver` level, `canJoinAllSpaces` + `.fullScreenAuxiliary`.
- Cmd+Q/Cmd+W/Cmd+Tab bloklangan (`performKeyEquivalent` override).
- Liquid glass dizayn: countdown ring, faza label chip, motivatsion xabar.

**#8 Break matn + countdown**
- `BreakView`: 88pt monospace timer, faza label chip, sozlanadigan motivatsion xabar, mashq animatsiyasi.

**#9 5 daq notification**
- `NotificationService`: `UNUserNotificationCenter`, focus bosqichida 5 daq qolganda banner + sound.

**#11 Menu bar icon + status**
- `MenuBarExtra` popover: faza status, quick input, controls, statistika (bugun/bosqich/streak).

### Phase 2 — Eye Health (PLAN'dagi #4, #5, #7)

**#4 Eye exercise animatsiyalari**
- Python generatsiya qilingan **27 PNG frame**: 9 gaze yo'nalishi (center/up/down/left/right/diagonal) + 9 blink (open→closed→open).
- `EyeExerciseAnimation` SwiftUI view: gaze → blink tsikl @ 0.18s/frame.
- `ExerciseSequenceView` (kamera yoqilganda): live gaze-gauged mashqlar.

**#5 Eye blink detection**
- `CameraService`: AVFoundation capture session, `.front` kamera, `AsyncStream<CVImageBuffer>` frame pipe.
- `EyeTracker`: `VNDetectFaceLandmarksRequest` (rev2), eye openness ratio (EAR-approximation), blink count (`>0.15s` debounce), 1-daqikali window.
- Settings orqali yoqiladi, faqat break'da ishlashi coordinator'da boshqariladi (privacy).
- `CameraIndicatorBadge` (privacy UI): kamera yoniq ekanligini pulse qilib ko'rsatadi.

**#7 TTS voice guidance**
- `TTSService`: `AVSpeechSynthesizer`, uz-UZ voice, rate/pitch sliders sozlanadigan.
- Break/start paytida gapiradi.

### Phase 2.5 — Gaze mashqlari (yangi)
- `GazeDirection` model + `EyeTracker.lastGazeDirection`: vision landmark centroid'laridan face-center bilan farqi orqali gaze vector.
- `BreakExercise` model + `BreakExerciseStep`: 20-20-20, gaze 8-yo'nalish, blink mashqlari (library).
- `ExerciseValidator`: hold-while-matching, retry signal, step/exercise progress, gauge timer.
- `ExerciseSequenceView`: live mashq UI — instruction + hold-remaining gauge + step pips + retry ogohlantirish + face-not-detected alert.
- `BreakView` kamera yoqilganda live mashq bilan `EyeExerciseAnimation`'ni almashtiradi.

### Phase 3 — Polish (PLAN'dagi #10, #12, #13)

**#10 Sozlamalar**
- `SettingsView`: timer rejimi (countdown/count-up), tema (5), vaqt, takrorlash, autostart, notification, alarm ovozi, kamera tracking, floating, hotkeys, TTS, break message.

**#12 Long break + auto-start**
- 4-pomodoro cycle, long/short break auto-start togle.

**#13 Statistika**
- Bugungi count, bosqich, takror, **streak** (consecutive `StreakStore`) menu bar'da ko'rinadi.

### Phase 4 — Super Easy Timer'dan ilhomlangan featurelar

**Natural language parser** (`NaturalLanguageParser`)
- `5 min`, `5min`, `20 minutes`, `2h 30m`, `2h30m`, `90 seconds`, `25` (=25min), `1h`.
- `5pm`, `2:15am` → clock-target (keyingi mos vaqtgacha).
- `Add 5 min`, `+5m`, `Remove 1 hour`, `-1h` → delta.
- `reset` / `stop`.
- Regex + DateFormatter hybrid, clock-target bilan duration greedy parse'ini oldini olish uchun priority logic.

**Global klaviatura yorliqlari** (`KeyboardShortcutsService`)
- Carbon `RegisterEventHotKey` (to'g'ri `@convention(c)` callback + `InstallEventHandler`).
- ⌃⌥Space = toggle, ⌃⌥F = skip, ⌃⌥R = reset, ⌃⌥+ = +5m, ⌃⌥L = floating toggle.

**Floating timer** (`FloatingWindowManager` + `FloatingTimerView`)
- `.floating` level, `canJoinAllSpaces`, `.nonactivatingPanel` (boshqa app'ni activate qilmaydi).
- Mini liquid glass: **ushbu raqamli vaqt (30pt rounded)** + pastida **kichik faza label (tracking, uppercased)** — sirkular progress ring outline sifatida.
- **Tema rangi font orqali/очек** — `settings.theme.gradient` fon, stroke, label accent sifatida; `phase.gradient` esa ring fill uchun.
- 168×86 px panel, drag qilinadigan, break'da avtomatik ko'rinadi/yashirinadi.

**Takrorlash + count-up**
- `RepeatConfig`: count + delay, `delaysTotal` helper.
- `TimerMode.countUp`: elapsed → 0:00 dan yuqoriga.

**Alarm soundlar** (`AlarmSoundService`)
- Python + `afconvert` bilan 3 ta **.caf** generatsiya qilingan: `glass` (high chord cluster), `chime` (3 notes), `softBell` (long decay) + `silent`.
- `AVAudioPlayer`, faz tugaganda chalinadi.

### Assetlar
- **AppIcon** (PIL): 16→1024px, 10 variants, squircle-masklangan, radial gradient + glass disc + specular + countdown ring + eye glyph. `AppIcon.appiconset/Contents.json` manifest.
- **Break icon** (green palette variant).
- **Menu bar template icons** (16/32/64).
- `Info.plist`: Blink nom, AppIcon refs, kamera/notification usage desc.

### Arxitektura
- `BreakPresenter` + `FloatingTimerController` protokollari — core view-layer'ga bog'lanmaydi (testable).
- `BlinkCoordinator`: notification + TTS + floating + break + alarm + kamera hooklarini birlashtiradi.

### Testlar — SelfTest 97/97 passed
- Models: phase/mode/theme/gradient counts.
- Timer: initial state, skip transitions, stop reset, add/remove, custom duration, parsed input apply.
- Parser: 8 duration format, 5pm clock-target, 4 add/remove directive.
- Count-up mode progress.
- Repeat config (count/delay floors, delaysTotal).
- **StreakStore**: consecutive days, gap reset, same-day idempotent, longest tracking.
- Stats with streak integration.
- AlarmSound enum.
- Codable round-trip (settings + stats).

### Git
```
4efbf7a feat(assets): liquid-glass AppIcon, break icon, eye/blink animation
d34dcf7 feat: Blink MVP — pomodoro + floating timer + NL parser + hotkeys
(WIP) feat: eye gaze tracking + exercise validator + camera indicator
```

---

## ⏳ Qoldi

### Hozirgi flux'da (yarim)
- **`EyeTracker.gazeDirection`** — `VNFaceLandmarks2D.boundingBox`'siz. Compile error: `boundingBox` `VNFaceObservation`'da. Fix: `request.results.first as? VNFaceObservation` qilib, `faceObservation.boundingBox` olish kerak. Keyin `landmarks` alohida observation'dan.
- **`ExerciseValidator`'ning UI wiring'i** — builddan o'tmagan (gaze error bloklar). Fix qilingandan keyin joriy SelfTest'da validator testlari qo'shish kerak (gaze match, retry, hold-complete, exercise advance).

### Phase 2 — qolgan
- **TTS voice kalibRouter** — hozir break/start'da birdaniga gapiradi; mashqlar bilan **sinxron timing** ("har 30 sec: ko'zingni yum, uzoqqa qarang") yo'q.

### Phase 3 — qolgan
- **Posture/suv ichish eslatmasi** (#19) yo'q.

### Phase 4 — qolgan featurelar
- **#14 Break music / white noise / nature sounds** — faqat alarm tone bor; tanaffus fon musiqasi yo'q.
- **#15 SwiftCharts statistik grafigi** (kunlik/haftalik/oylik + streak kunlar) — streak *raqami* bor, *grafik* yo'q.
- **#16 Badge reward** — streak raqami ko'rinadi, lekin milestone badge'lar (7/30/100 kun) yo'q.
- **#17 Screen brightness auto** (`DisplayServices`/gamma ramp) yo'q.
- **#18 Night Shift scheduler** (CoreBrightness private) yo'q.
- **#22 Raycast/Alfred/Stream Deck** yo'q.
- **#23 iCloud sync + multi-device** (CloudKit) — `UserDefaults` local'.
- **#24 App bloklash break vaqtida** (Telegram/YouTube force quit) yo'q — faqat break *window* bloklaydi.
- **#27 CLI `tired start 25`** yo'q.
- ~~Slack/Discord break status~~ — bekor qilindi.
- ~~Apple Watch heart rate (HealthKit)~~ — bekor qilindi.

### Sifat/texnik qoldi
- `CameraService`/`EyeTracker`'da Sendable ogohlantirishlar (Swift 6 mode'da error bo'ladi) — `@preconcurrency` yoki `nonisolated` konformance kerak.
- `KeyboardShortcutsService`'da hotkey'larni **foydalanuvchi sozlashtiirishi** (settings'da custom key combo) yo'q — hardcoded defaults.
- `AVAudioPlayer` macOS'da `AVAudioSession` yo'qligi uchun priority/mixing boshqaruvi yo'q.
- `Bundle.main` vs `Bundle.module` — alarm soundlar BlinkCore'da `Bundle.main`'dan olinadi; SPM bundle'da bo'lsa `Bundle.module`'ga ko'chirish kerak (sound endi BlinkCore'ga `.process` resource qilib qo'shilsa).

---

## Keyingi navbat
1. **`EyeTracker` compile fix** — `VNFaceObservation`'dan `boundingBox` + `landmarks` olish.
2. **SelfTest'ga validator testlari** — GazeDirection matches, validator hold/advance/retry flow.
3. **TTS kalibRouter** — mashqlar sinxron timing.
4. **Streak badge'lar** (mukofot tizimi #16 qismi).
5. **SwiftCharts statistik** (#15).