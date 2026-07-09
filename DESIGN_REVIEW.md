# Blink — UI/UX Dizayn Reviewi (butun app)

> **Deliverable:** faqat plan — muammolar (problems) va yaxshilanishlar (improvements) ro'yxati. Kod yozilmaydi.
> **Scope:** butun app (Tasks, Timer, Menu-bar, Break, Week, Progress, Settings, Shell) — Tasks eng chuqur ko'rib chiqildi.

---

## Context — nega bu review

Blink'ning **vizual yo'nalishi (dark "Liquid Glass", SF Rounded, theme-driven accent, bespoke moment'lar) allaqachon kuchli va o'ziga xos** — bu templated emas. Muammo estetikada emas, **shu yo'nalishning bir xilda (consistent) bajarilmaganida**: `DesignSystem.swift`'da real token tizimi bor, lekin faqat ~20% qo'llanilgan. Natijada bitta tushuncha (masalan "section header", "chip", "timer raqami") har ekранda boshqacha ko'rinadi. Ustiga — bir nechta **real accessibility va contrast bug'lari**.

Bu "noldan redesign" emas — bu **"tartibga solish + sistematizatsiya" (discipline) ishi**. Estetikani saqlab qolamiz, ijросини bir xillashtiramiz va Tasks'ni best-in-class todo darajasiga ko'taramiz.

---

## Dizayn tezisi (design POV)

**Boldness'ni bitta joyda sarfla.** Bespoke moment'lar (liquid floating timer, streak celebration, colored ring glow) — bu app'ning **imzosi (signature)**, ularni saqlaymiz. Qolgan hamma narsa **tinchroq va izchilroq** bo'lishi kerak. Ya'ni: yangi vizual shovqin qo'shmaymiz — **nomuvofiqlikni (inconsistency) olib tashlaymiz**. Uch yo'nalish:

1. **Discipline** — token tizimini to'liq qo'llash (radius, opacity, **type scale**, bitta Chip/Tag/Menu komponenti).
2. **Clarity** — hierarchy, contrast va accessibility'ni tuzatish.
3. **Focus** — Tasks (todo) ni chin ma'noda kuchli todo tajribasiga aylantirish (search, filter, status view'lar).

---

## Umumiy baho + saqlaydigan narsalar (keep these)

**Dizayn yetukligi:** kuchli konsepsiya, o'rtacha ijro izchilligi. Foydalanuvchi darajasidagi eng katta bo'shliq — Tasks'da search/filter/status yo'qligi va butun app bo'ylab contrast/a11y.

**Buzmaslik kerak bo'lgan kuchli tomonlar:**
- **Liquid floating timer** — sloshing spring physics ([FloatingTimerView.swift](Sources/Blink/Views/FloatingTimerView.swift)). Genuinely bespoke.
- **Colored glass sidebar** — app'dagi eng chiroyli surface ([MainWindowView.swift:48-82](Sources/Blink/Views/MainWindowView.swift#L48-L82)).
- **Streak celebration** — spring + confetti ([StreakRewardBanner.swift](Sources/Blink/Views/StreakRewardBanner.swift)).
- **`.pressable`/`.pressableSubtle`** press feedback — butun app bo'ylab yagona izchil interaction token ([GlassComponents.swift:79-95](Sources/Blink/Views/GlassComponents.swift#L79-L95)).
- **Week bo'sh ustunlarining restraint'i** — faqat drag paytida "Release to plan" ([WeeklyBoardView.swift:305-321](Sources/Blink/Views/WeeklyBoardView.swift#L305-L321)).
- **DS token tizimi mavjudligi** — poydevor bor, uni to'ldirish kerak xolos.

---

# MUAMMOLAR (Problems)

Severity: **[Kritik]** butun app'ga ta'sir / **[Yuqori]** / **[O'rta]** / **[Past]**.

## A. Tizim darajasidagi (system-level — eng katta ta'sir)

- **A1 · [Kritik] · Accent kontrast 5 theme'dan 3 tasida yiqiladi.** Deyarli hamma rangli element `theme.gradient.first`'dan olinadi, lekin u: `midnight` → **qora**, `frosted`/`cream` → **oq'ga yaqin** ([BlinkTheme.swift:21-31](Sources/BlinkCore/Models/BlinkTheme.swift#L21-L31)). Shu sabab "Today" chip, nav selection, streak fill, heatmap, range pill shu theme'larda ko'rinmay qoladi. **Eng yuqori ta'sirli bug.**
- **A2 · [Kritik] · Type scale yo'q.** 174 ta ad-hoc `.font(.system(...))`; har surface o'lchamni qo'lda tanlaydi. Bitta "timer raqami" degan tushuncha **4 xil weight**da: `76 light` (main), `title3 semibold` (menu bar), `20 medium` (break), `20–54 semibold` (floating). Yagona `Font` ramp yo'q.
- **A3 · [Kritik] · Design token'lar faqat ~20% qo'llanilgan.** DS aynan buni to'xtatish uchun yozilgan, lekin off-scale radiuslar hamon bor: `7, 9, 11, 13, 15, 18, 22, 24, 28` (DS faqat `8/12/16/20`). White-opacity ramp'i (2 tier: 0.62/0.42) o'rniga kamida `0.3, 0.4, 0.45, 0.5, 0.55, 0.6, 0.65, 0.68, 0.7, 0.75, 0.85, 0.9` ishlatilgan.
- **A4 · [Yuqori] · "Forced dark" bo'lsa-da light theme'lar sotiladi.** App `.darkAqua`'ga pin qilingan va matn hamma joyda hardcoded oq ([AppDelegate.swift:98](Sources/Blink/AppDelegate.swift#L98)), lekin `cream`/`frosted` (oq'ga yaqin) theme'lar `black 0.30→0.62` scrim tufayli baribir qorong'i chiqadi — ziddiyat.
- **A5 · [Yuqori] · Accessibility bo'shliqlari.** `grep` bo'yicha: **Reduce Motion** ishlovi umuman yo'q (`repeatForever`/`TimelineView` animatsiyalar shartsiz ishlaydi); **Dynamic Type** yo'q (fixed `.system(size: 8/9/10/11)`); **VoiceOver** uchun `accessibilityLabel/Hint/Traits` umuman yo'q; ikkilamchi matnlar `white 0.4–0.5` shisha ustida — WCAG AA'dan past.
- **A6 · [O'rta] · Emoji UI ikonografiyasi sifatida.** `🍅 ☑ ↑ ↓` SF Symbol'lar bilan aralash ishlatilgan (Tasks, Week card, Stats) — placeholder'day ko'rinadi, turli tizimlarda har xil render bo'ladi.
- **A7 · [O'rta] · Dublikat, farqlanib ketgan komponentlar.** "chip" pill kamida 2 marta qayta yozilgan ([TasksView.swift:338](Sources/Blink/Views/TasksView.swift#L338), [TaskEditorView.swift:334](Sources/Blink/Views/TaskEditorView.swift#L334)); due/priority/category menu'lari har faylda takrorlangan (composer "This weekend" beradi, editor yo'q); tag UI **2 xil ko'rinishда**.

## B. Tasks / todo (asosiy fokus — eng chuqur)

- **B1 · [Yuqori] · Search / filter / status view yo'q.** Qidiruv yo'q; priority/tag/due/project bo'yicha filtr yo'q; "Today / Upcoming / Completed" ko'rinishlari yo'q. Todo app uchun eng katta funksional bo'shliq. Grouping qattiq category bo'yicha kodlangan ([TaskStore.swift:142-156](Sources/BlinkCore/Services/TaskStore.swift#L142-L156)).
- **B2 · [Yuqori] · Bajarilgan tasklarni yashirish/tozalash yo'q.** Strikethrough bilan category ichida to'planib boraveradi; hide-completed / clear-completed toggle yo'q.
- **B3 · [Yuqori] · Meta row overload.** Bitta `lineLimit(1)` qatorda `size: 10`da 6 xil element (priority flag, project, 3 tagacha tag, repeat, subtask count, due) — tez truncate bo'ladi, title bilan raqobatlashadi ([TasksView.swift:711-758](Sources/Blink/Views/TasksView.swift#L711-L758)).
- **B4 · [Yuqori] · Rang tizimlari to'qnashuvi.** Priority P3 = `#4F8DFD` = Work kategoriyasi ko'ki = `palette[0]` — bir xil ko'k ([TaskItem.swift:68](Sources/BlinkCore/Models/TaskItem.swift#L68)). Bitta qatorда 3 ta mustaqil rang tizimi bir vaqtda: category accent bar + priority checkbox/flag + accent tag pills.
- **B5 · [O'rta] · Ikki xil tag UI.** Asosiy ko'rinishда: accent'li gorizontal-scroll pill'lar ([TasksView.swift:728-734](Sources/Blink/Views/TasksView.swift#L728-L734)); editor'da: `white 0.10` wrapping FlowLayout ([TaskEditorView.swift:431-457](Sources/Blink/Views/TaskEditorView.swift#L431-L457)). Boshqa shakl, rang, layout.
- **B6 · [O'rta] · Composer maydonlarni "More" ortiga yashiradi.** Default'da faqat category/priority/due; tag, estimate, repeat, project, notes yashirin ([TasksView.swift:283-335](Sources/Blink/Views/TasksView.swift#L283-L335)).
- **B7 · [O'rta] · Ko'rinmas drag affordance.** Reorder `draggable`/`dropDestination` bilan ishlaydi, lekin handle yo'q, drop indicator yo'q, category'lar orasida jimgina no-op ([TasksView.swift:645-650](Sources/Blink/Views/TasksView.swift#L645-L650)).
- **B8 · [O'rta] · Editor sheet fixed 420×560, resize yo'q; notes `TextEditor` faqat 70pt** ([TaskEditorView.swift:44](Sources/Blink/Views/TaskEditorView.swift#L44)). Uzun notes/subtask ro'yxati kichik sheet ichida scroll bo'ladi.
- **B9 · [Past] · Popover'da nested scroll.** Non-embedded `TasksView` o'zining `ScrollView`/`height: 320`'ini popover'ning 512'lik scroll'i ichiga qo'yadi ([TasksView.swift:66-74](Sources/Blink/Views/TasksView.swift#L66-L74)).
- **B10 · [Past] · Empty-state copy.** Literal `▶` glif va hardcoded `\n`, holbuki asl tugma `play.fill` doira ([TasksView.swift:614](Sources/Blink/Views/TasksView.swift#L614)).
- **B11 · [Past] · Icon overloading.** `slider.horizontal.3` = 3 xil ma'no (composer "More", category manager, row "Edit") ([TasksView.swift:113,264,874](Sources/Blink/Views/TasksView.swift#L874)).

## C. Timer / Focus surface'lari

- **C1 · [Yuqori] · TimerDetail'da hierarchy yassi.** Phase label va task tugmasi ikkalasi ham `title3 semibold` — bir xil vaznda, qaysi biri status, qaysi biri tap qilinadigan control ekani bilinmaydi ([MainWindowView.swift:310,323](Sources/Blink/Views/MainWindowView.swift#L310)).
- **C2 · [O'rta] · Scale imbalance.** Run button ~104pt vs flanker'lar 52pt, `spacing: 40` — kichik tugmalar uzoqda suzib, afterthought'day ko'rinadi ([MainWindowView.swift:336-347](Sources/Blink/Views/MainWindowView.swift#L336-L347)).
- **C3 · [O'rta] · Reset destructive belgisi yarim.** `tint: .red` faqat glif'ni qizartiradi, "Reset" matni oq qoladi ([MainWindowView.swift:344-346](Sources/Blink/Views/MainWindowView.swift#L344-L346)).
- **C4 · [O'rta] · Control tili surface'lar orasida bo'lingan.** Skip/Reset main window'da doiraviy-vertikal, menu bar'da gorizontal-capsule — bir xil amallar, ikki vizual til.
- **C5 · [O'rta] · Menu bar: 5 xil tugma shakli, hammasi full-width prominent** → primary action hierarchy yo'q; 360pt'da juda zich ([MenuBarView.swift:823-895](Sources/Blink/Views/MenuBarView.swift#L823-L895)).
- **C6 · [Yuqori] · Break lockout'da chiqish yo'q.** Screen-saver darajasidagi panel, `isMovable=false`, `cancelOperation` no-op, ⌘ yutiladi ([BreakWindowManager.swift:72-76](Sources/Blink/Services/BreakWindowManager.swift#L72-L76)); "Exit break" tugmasi default'da **yashirin** ([BreakView.swift:74](Sources/Blink/Views/BreakView.swift#L74)). Esc ham ishlamaydi — jiddiy control/a11y muammosi.
- **C7 · [Past] · Break Sharingan ko'zlari** — tematik jihatdan baland, tinch glass focus ekraniga nisbatan off-brand (subyektiv, lekin qayd etilsin) ([SharinganEyeView.swift](Sources/Blink/Views/SharinganEyeView.swift)).
- **C8 · [O'rta] · Dead code.** Ikkita orphaned eye-exercise view ([ExerciseSequenceView.swift](Sources/Blink/Views/ExerciseSequenceView.swift), [EyeExerciseAnimation.swift](Sources/Blink/Views/EyeExerciseAnimation.swift)) — hech qayerdan chaqirilmaydi va **ikkinchi vizual identity** (ko'k orbit-eye) olib yuradi. Tugallanmagan scaffolding signali.

## D. Week board

- **D1 · [Yuqori] · Sig'maydi.** 8 ustun × (204+14) ≈ **1740pt** vs 920pt min oyna → aksar kunlar ekrandan tashqarida; backlog sticky emas, Fri/Sat'ga scroll qilsangiz quick-add backlog yo'qoladi ([WeeklyBoardView.swift:21,60](Sources/Blink/Views/WeeklyBoardView.swift#L60)).
- **D2 · [O'rta] · Fixed `minHeight: 440`** — siyrak haftada katta bo'sh joy ([WeeklyBoardView.swift:261-262](Sources/Blink/Views/WeeklyBoardView.swift#L261-L262)).
- **D3 · [Past] · Weekend/weekday farqi ko'rinmas** (`white 0.02` vs `0.05`) ([WeeklyBoardView.swift:290-291](Sources/Blink/Views/WeeklyBoardView.swift#L290-L291)).
- **D4 · [Past] · Card'larda emoji glif** (`🍅 ☑`) ([WeeklyBoardView.swift:352-360](Sources/Blink/Views/WeeklyBoardView.swift#L352-L360)).
- **D5 · [Past] · Hardcoded `Locale("en_US")`** — lokalizatsiya yo'q ([WeeklyBoardView.swift:142,222-228](Sources/Blink/Views/WeeklyBoardView.swift#L142)).

## E. Progress / Stats

- **E1 · [Yuqori] · Stock-color rainbow.** 9 metric card tinti: `.orange, accent, .cyan, .green, accent, .yellow, .purple, .teal, .pink` — 7 ta stock SwiftUI rangi ([StatsSummaryView.swift:15-32](Sources/Blink/Views/StatsSummaryView.swift#L15-L32)). Bu Progress sahifasidagi eng kuchli "templated dashboard" signali. Bundan tashqari **hero metric yo'q** — hamma karta bir xil `title3` vaznda.
- **E2 · [O'rta] · Accent split (bitta sahifada).** Summary grid + heatmap theme accent'ga ergashadi, lekin focus-history chart hardcoded `paletteFocusStart` ([StatsChartView.swift:100,124-126](Sources/Blink/Views/StatsChartView.swift#L124-L126)). Neon/Cream'da kartalar rang almashtiradi, chart ko'k-yashil qoladi.
- **E3 · [Past] · Card elevation nomuvofiq.** `heatmapCard`'da `.liquidShadow` bor, `weekdayCard`/`categoryCard`'da yo'q — bitta sahifada 2 xil balandlik ([StatsExtrasView.swift:72,133,184](Sources/Blink/Views/StatsExtrasView.swift#L72)).
- **E4 · [O'rta] · Real bug: StreakBadge progress fill hardcoded 240pt.** Track full-width Capsule, fill esa `width: max(3, 240*pct)` — faqat bitta karta enida to'g'ri keladi ([StreakBadgeView.swift:64](Sources/Blink/Views/StreakBadgeView.swift#L64)).
- **E5 · [O'rta] · Data-viz zaifliklari.** Y o'qida birlik yo'q; "Focus by hour" chart Y o'qini butunlay yashiradi (kattaliklar o'lchovsiz); weekday yorliqlari `M T W T F S S` — Tue/Thu, Sat/Sun farqlanmaydi ([StatsChartView.swift:145,209](Sources/Blink/Views/StatsChartView.swift#L209), [StatsExtrasView.swift:106](Sources/Blink/Views/StatsExtrasView.swift#L106)).

## F. Settings

- **F1 · [Yuqori] · Bir xil control uch xil rangda.** Toggle: `ToggleRow` → `.tint(.green)` ([FormControl.swift:16](Sources/Blink/Views/FormControl.swift#L16)); `ReminderRow` → `.tint(.white)` ([ReminderRow.swift:19](Sources/Blink/Views/ReminderRow.swift#L19)); app-blocking Toggle → theme accent ([SettingsView.swift:368](Sources/Blink/Views/SettingsView.swift#L368)).
- **F2 · [O'rta] · Ikki stepper uslubi.** Custom `DSStepper` vs stock AppKit `Stepper` bir sahifada ([SettingsView.swift:769](Sources/Blink/Views/SettingsView.swift#L769), [ReminderRow.swift:23](Sources/Blink/Views/ReminderRow.swift#L23)).
- **F3 · [O'rta] · Ikki tugma uslubi.** `.buttonStyle(.bordered)` (stock) vs `.pressableSubtle` (custom) yonma-yon ([SettingsView.swift:318-320,385](Sources/Blink/Views/SettingsView.swift#L318-L320)).
- **F4 · [O'rta] · Slider/help caption'lari `.rounded` emas.** Barcha slider caption va tushuntirish matni `.font(.caption)` (system font) — app'ning qolgani `design: .rounded`, shu sabab form o'rtasida boshqa shrift'day o'qiladi ([SettingsView.swift:277,235-236](Sources/Blink/Views/SettingsView.swift#L277)).
- **F5 · [O'rta] · Real bug: `shortcutLegend` padding order.** `.glassRounded(18)` **keyin** `.padding(14)` — padding glass'ning tashqarisiga tushadi, kontent panel ichki chetiga tegib turadi ([SettingsView.swift:698-699](Sources/Blink/Views/SettingsView.swift#L698-L699)).
- **F6 · [O'rta] · Eye Care card overloaded.** Bitta card'da toggle'lar, stepper, Sharingan picker (26×26 thumb), Preview tugmasi, 2 slider va gorizontal-scroll TTS chip editor ([SettingsView.swift:409-474](Sources/Blink/Views/SettingsView.swift#L409-L474)).
- **F7 · [Past] · Yarim-tugallangan search.** Faqat category ro'yxatini filtrlaydi; deep-link / highlight / scroll-to yo'q — macOS System Settings search'day ko'rinadi, lekin qismini bajaradi ([SettingsView.swift:53-57](Sources/Blink/Views/SettingsView.swift#L53-L57)).

## G. Shell / Sidebar / Navigatsiya

- **G1 · [Yuqori] · Nav selection accent'ga bog'liq** → A1 sababli 3 theme'da yo'qoladi ([MainWindowView.swift:197-201](Sources/Blink/Views/MainWindowView.swift#L197-L201)).
- **G2 · [O'rta] · Section header token drift.** Sidebar `dsSectionLabel()`'ni inline qayta yozadi, lekin `white 0.42`da — Settings/Stats'da esa `0.62`. Bir xil ko'rinadigan element ikki xil xiralikda ([MainWindowView.swift:150-159](Sources/Blink/Views/MainWindowView.swift#L150-L159)).
- **G3 · [O'rta] · detailScaffold nomuvofiq.** Tasks/Progress width'i 640'ga cap'lanadi va scaffold title beradi; Week esa cap'ni chetlab o'tadi va **o'z** `largeTitle` sarlavhasini beradi — sahifa yuqori ritmi bo'limlar orasida farq qiladi ([MainWindowView.swift:217-267](Sources/Blink/Views/MainWindowView.swift#L217-L267)).
- **G4 · [Past] · Count badge faqat Tasks nav'ida** — Week/Progress'da ham mazmunli sanoq bor ([MainWindowView.swift:180](Sources/Blink/Views/MainWindowView.swift#L180)).
- **G5 · [O'rta] · Off-scale radiuslar:** sidebar `22`, nav `9`, footer `13` — DS `20/8/12` o'rniga.

---

# YAXSHILANISHLAR (Improvements)

Har bir yaxshilanish tegishli muammoga (→ A1 kabi) bog'langan. Ketma-ketlik: **P0 avval** (systemic, high-leverage) → **P1 Tasks** → **P2 per-surface polish**.

## P0 — Poydevor (avval qilinadigan, eng katta leverage)

- **Y0.1 · `resolvedAccent` kiritish** — interaktiv accent'ni `theme.gradient.first`'dan ajratish. Theme gradient'idan luminance bo'yicha dark scrim'ga kafolatlangan kontrast beradigan rangni tanlash (yoki luminance'ni clamp qilish). Nav selection, "Today" chip, streak fill, heatmap, range pill — hammasi shuni ishlatadi. **(→ A1, G1, D contrast, E2 qisman)**
- **Y0.2 · Theme'lar bo'yicha halol qaror** — yoki `cream`/`frosted`/light theme'larni olib tashlab, dark'ga to'liq commit qilish; yoki adaptive matn bilan haqiqiy light-mode surface'lar qilish. Hozirgi ziddiyatni yopish. **(→ A4)**
- **Y0.3 · Token tizimini to'ldirish + migratsiya:**
  - **`DS.Text` Font ramp** qo'shish (display / title / headline / body / caption / micro — barchasi `.rounded`), barcha `.font(.system(size:))`'ni shunga ko'chirish. Bitta "timer numeral" style. **(→ A2)**
  - Har radiusni `DS.Radius`'ga, har `white.opacity`'ni `ds*` tier'ga yo'naltirish. **(→ A3, G5)**
  - **Bitta `Chip`/`Pill`, bitta `Tag`, bitta due/priority/category menu** komponentini extract qilish — dublikat va drift'ni o'ldiradi. **(→ A7, B5)**
- **Y0.4 · Accessibility pass:**
  - `@Environment(\.accessibilityReduceMotion)` guard'ini barcha `repeatForever`/`TimelineView` animatsiyalarga (run glow, breathing, liquid slosh, Sharingan spin). **(→ A5)**
  - Dynamic Type — text style'lar orqali; icon-only control'larga `accessibilityLabel/Hint/Traits`; ikkilamchi matnга ≥4.5:1 kontrast kafolati. **(→ A5)**
  - Break'ga har doim ko'rinadigan exit + Esc. **(→ C6)**

## P1 — Tasks (todo) ni ko'tarish

- **Y1.1 · Status/smart-view qatlami** — segmented yoki top filter: **Today / Upcoming / All / Completed**; **search field**; **hide/clear-completed**. **(→ B1, B2)**
- **Y1.2 · Row redesign** — title'ni ko'tarish; meta'ni tinchroq ikkilamchi qatorga olib, qat'iy tartib + **max 2 chip + "+N" overflow**; 3 rang tizimini ajratish (category = faqat chap bar; priority = faqat flag, alohida hue to'plami; tag = neutral). **(→ B3, B4)**
- **Y1.3 · Tag UI'ni birlashtirish** — bir `Tag` komponenti, hamma joyda wrapping FlowLayout. **(→ B5, A7)**
- **Y1.4 · Composer progressive disclosure** — eng ko'p ishlatiladigan 2–3 maydonni ochib qo'yish, "More"'ni yaxshilash. **(→ B6)**
- **Y1.5 · Drag handle + drop indicator**; cross-category ko'chirishга ruxsat yoki aniq disable. **(→ B7)**
- **Y1.6 · Editor sheet'ni resizable / kattaroq min qilish, notes'ni o'stirish.** **(→ B8)**
- **Y1.7 · Popover nested scroll'ini tuzatish** (bitta scroll owner). **(→ B9)**
- **Y1.8 · Empty-state copy'ni tuzatish** (real play ikonasi, literal `\n` yo'q). **(→ B10)**
- **Y1.9 · Ikonalarni ajratish** (Edit = `pencil`, `slider.horizontal.3` emas). **(→ B11)**

## P2 — Per-surface polish

**Timer.** Bitta timer-numeral style o'rnatish; run/flanker scale'ni balanslash; Reset'ga to'liq destructive styling; Skip/Reset tilini surface'lar bo'ylab birlashtirish; menu bar tugma shakllari sonini kamaytirish, bitta primary belgilash. **(→ C1–C5)**

**Break.** Bitta exercise identity'ga commit qilish, 2 dead view'ni o'chirish; tinchroq guide (yoki Sharingan'ni opt-in "theme" qilish); har doim ko'rinadigan exit. **(→ C6–C8)**

**Week.** Sig'dirish — responsive grid'ga o'tkazish yoki backlog'ni sticky qilib, kun "peek"'i bilan horizontal scroll; content-height ustunlar; ko'rinadigan weekend farqi; emoji o'rniga SF Symbols; lokalizatsiya. **(→ D1–D5)**

**Stats.** Palette'ni kuratsiya qilish (accent + undan hosil qilingan 2–3 tint, stock rainbow emas); 1–2 hero metric o'rnatish; card elevation'ni bir xillashtirish; StreakBadge'ni relative width'ga o'tkazish (240pt bug); o'q birligi/yorliqlarini qo'shish. **(→ E1–E5)**

**Settings.** Bitta toggle tinti, bitta stepper, bitta tugma uslubi; caption'lar uchun `.rounded` shrift; `shortcutLegend` padding tartibini tuzatish; Eye Care'ni bir nechta card'ga bo'lish; search'ni yakunlash (deep-link) yoki scope'ini kichraytirish. **(→ F1–F7)**

**Shell.** `dsSectionLabel()`'ni hamma joyda ishlatish (0.42 fork'ni o'ldirish); radiuslarni token'ga; tegishli nav item'larga badge; detailScaffold'ni birlashtirish (bitta title-owner, izchil width siyosati). **(→ G2–G4)**

---

## Tavsiya etilgan ketma-ketlik (roadmap)

1. **Faza 1 — Foundation:** `DS.Text` ramp, `resolvedAccent`, a11y primitivlari, extracted Chip/Tag/Menu. *(hamma narsani unblock qiladi)*
2. **Faza 2 — Tasks redesign:** asl so'rov — B/P1 to'liq.
3. **Faza 3 — Per-surface polish:** Timer, Week, Stats, Settings, Shell.
4. **Faza 4 — Cleanup:** dead code o'chirish, lokalizatsiya, off-scale qoldiqlar.

---

## Tekshirish (verification)

Bu review hujjat bo'lgani uchun tekshirish = topilmalarni ko'z bilan tasdiqlash va keyinchalik tuzatishlarni validatsiya qilish:

- **Build + screenshot** har surface'ni (`Timer, Tasks, Week, Progress, Settings, Break`) **kamida 3 theme'da** (`liquidGlass`, `midnight`, `cream`) — A1/A4 contrast yiqilishini ko'z bilan tasdiqlash uchun. `swift build` → app'ni ishga tushirish.
- **Contrast checker** — ikkilamchi matn (`white 0.4–0.5`) va accent element'larni har theme'da WCAG AA (≥4.5:1) ga tekshirish. **(A1, A5)**
- **VoiceOver** yoqib, icon-only control'larda label bor-yo'qligini; **Reduce Motion** yoqib, animatsiyalar to'xtashini; **Dynamic Type**'ni kattalashtirib, matn scale bo'lishini tekshirish. **(A5)**
- **Break sinovi** — break'ni ishga tushirib, ko'rinadigan exit va Esc ishlashini tasdiqlash. **(C6)**
- **Before/after** — har o'zgarish uchun screenshot juftligini solishtirish.

> Eslatma: implementatsiya bu hujjatдан keyin, alohida bosqichda qilinadi. Hozircha faqat plan.
