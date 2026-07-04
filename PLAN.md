# TiredEyes — macOS Swift Extension Plan

Pomodoro + break bloklash + eye health app.

---

## High Priority

### 1. Xcode Project Skeleton
- SwiftUI menu bar app (`LSUIElement = true`)
- Helper agent (background timer/uquvsiz)
- Folder structure: `App/`, `Models/`, `Views/`, `Services/`, `Features/`

### 2. Pomodoro Timer Logic
- State: `work` / `break` / `paused` / `longBreak`
- Configurable durations (default: 25/5/15)
- Auto-start toggle
- Persistent timer state
- Long break after 4 pomodoros

### 3. Break Full-Screen Blocking Window
- Multi-monitor support (har screen uchun alohida window)
- `level = .screenSaver`
- `collectionBehavior` — Spaces, Mission Control'da ham ko'rinishi
- Anti: Cmd+Q, Cmd+Tab, Force Quit
- `NSApp.preventUserTermination` or `terminate` rejection
- Boshqa app'larni activate qilishni bloklash

### 4. Eye Exercise Animations (break'da)
- 20-20-20 qoidasi animatsiyasi
- Ko'z harakatlari (yuqori/past/chap/o'ng qarash)
- Blink reminder animation
- Sozlanadigan exercise sequence

### 5. Eye Blink Detection (Camera + Vision)
- Front camera orqali AVFoundation capture
- Vision framework bilan face/eye landmarks
- Blink count — kam bo'lsa ogohlantirish
- Faqat break vaqtida kamera ishlaydi (privacy)
- Camera indicator ko'rsatish

### 6. Eye Movement Tracking (Camera + Vision)
- Pupil/gaze direction tracking
- Break mashqlarini bajarishni tekshirish
- Exercise correct bajarilmasa retry

### 7. Mac TTS Voice Guidance (break'da)
- `AVSpeechSynthesizer` bilan ovozli instruksiyalar
- Multiple languages (uzbek, english, russian)
- Voice timing (har 30 sec) — "O'rningdan tur", "Ko'zingni yum", "Uzoqroqqa qarang"
- Sozlanadigan voice, rate, pitch
- Voice kalibRouter (mashqlar bilan sinxron)

---

## Medium Priority

### 8. Break Window: Matn + Qolgan Vaqt
- Sozlanadigan motidovatsion xabar
- Countdown timer (yirik font)
- TTS bilan sinxron matn

### 9. 5 Daqiqa Qoldi Notification
- `UNUserNotificationCenter`
- Sound + banner
- "Pomidoro 5 daqiqada tugaydi"

### 10. Sozlamalar Ekrani
- Work/break duration
- Break xabar matni
- Voice settings (TTS)
- Notification toggle
- Camera permission status

### 11. Menu Bar Icon + Status
- Pomodoro holatini ko'rsatish (work/break/paused)
- Qolgan vaqt
- Start/pause/stop actions

### 12. Long Break + Auto-Start
- 4 pomodoro cycle
- Auto-start toggle (break/work)

### 13. Bugungi Pomodoro Statistikasi
- Bugungi count
- Weekly chart

---

## Low Priority

### 14. Break Music / White Noise / Nature Sounds
- Built-in sound packs
- User custom audio

### 15. SwiftCharts Statistika Grafiklari
- Kunlik/haftalik/oylik
- Streak kunlar

### 16. Streak Tizimi
- Ketma-ket pomodoro kunlar
- Badge reward

### 17. Break'da Screen Brightness Auto-Tushirish
- `DisplayServices` yoki Gamma ramp

### 18. Night Shift Scheduler Integratsiyasi
- CoreBrightness private API (谨慎) yoki manual schedule

### 19. Suv Ichish + Posture Eslatmasi
- Schedule reminders
- Posture (tana holati) TTS eslatma

### 20. Slack/Discord Break Status
- Slack status API
- Discord RPC

### 21. Apple Watch Heart Rate + Break Tavsiyasi
- HealthKit
- Yurak urishi bo'yicha break tavsiyasi

### 22. Raycast/Alfred Extension + Stream Deck
- CLI command integration
- Stream Deck plugin

### 23. iCloud Sync + Multi-Device
- CloudKit
- iPhone/iPad companion

### 24. App Bloklash break Vaqtida
- Telegram, YouTube, etc.
- NSWorkspace monitor + force quit

### 25. Theme/Ranglar + Dark/Light Mode
- Color schemes
- Auto theme by system

### 26. Break Musiqa / White Noise / Nature Sounds
- Built-in sound packs
- User custom audio

### 27. CLI Tool — `tired start 25`
- Terminal'dan pomodoro'ni boshqarish

---

## Implementation Order

```
Phase 1 (MVP): #1, #2, #3, #8, #9, #11
Phase 2 (Eye Health): #4, #5, #6, #7
Phase 3 (Polish): #10, #12, #13
Phase 4 (Features): #14-33
```

## Permissions Kerak

- Camera (AVFoundation) — eye detection
- Notification (UNUserNotificationCenter)
- Accessibility (AXIsProcessTrusted) — break blocklash uchun
- Launch at login (SMAppService)
- (Optional) Screen Recording — brightness control private API
- (Optional) HealthKit — heart rate

## Tech Stack

- Swift 5.9+, SwiftUI, macOS 14+
- Vision framework (eye tracking)
- AVFoundation (camera + TTS)
- UserNotifications
- CloudKit (sync)
- SwiftData/UserDefaults (persistence)
- (Optional) HealthKit, EventKit