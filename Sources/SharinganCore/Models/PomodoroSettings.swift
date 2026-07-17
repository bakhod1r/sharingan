import Foundation
import CoreGraphics

/// Per-tag (label) appearance: an SF Symbol and a flag color. Both optional —
/// missing fields fall back to the app defaults ("at" mark, accent color).
public struct TagStyle: Codable, Equatable, Sendable {
    public var colorHex: String?
    public var icon: String?
    public init(colorHex: String? = nil, icon: String? = nil) {
        self.colorHex = colorHex
        self.icon = icon
    }
    public var isEmpty: Bool { colorHex == nil && icon == nil }

    /// SF Symbols offered in the tag editor.
    public static let iconChoices: [String] = [
        "at", "tag.fill", "star.fill", "flame.fill", "bolt.fill", "book.fill",
        "briefcase.fill", "heart.fill", "leaf.fill", "moon.fill",
        "graduationcap.fill", "gamecontroller.fill",
    ]
}

/// Floating widget size presets, tuned to the pill's single-row layout (ring +
/// time, title row, transport buttons).
public enum FloatingWidgetSize: String, Codable, CaseIterable, Sendable {
    case small, medium, large

    /// Panel size in points.
    public var width: CGFloat {
        switch self {
        case .small:  return 280
        case .medium: return 320
        case .large:  return 380
        }
    }
    public var height: CGFloat {
        switch self {
        case .small:  return 48
        case .medium: return 56
        case .large:  return 68
        }
    }

    public var label: String {
        switch self {
        case .small:  return "Small"
        case .medium: return "Medium"
        case .large:  return "Large"
        }
    }
}

/// Which end of a bottom Dock the pill hugs; a vertical Dock ignores this
/// and always vertically centers the pill instead — see `FloatingWidgetGeometry`.
public enum FloatingWidgetAlignment: String, Codable, CaseIterable, Sendable {
    case leading, center, trailing

    public var label: String {
        switch self {
        case .leading:  return "Left"
        case .center:   return "Center"
        case .trailing: return "Right"
        }
    }
}

/// The three pomodoro sizes — a quick gear shift between short bursts and deep
/// work. Each kind carries its own (editable) focus/break lengths; the enum
/// only names the slot and supplies factory defaults.
public enum PomodoroKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case small, normal, big

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .small:  return "Small"
        case .normal: return "Normal"
        case .big:    return "Deep Work"
        }
    }

    public var systemImage: String {
        switch self {
        case .small:  return "hare.fill"
        case .normal: return "timer"
        case .big:    return "tortoise.fill"
        }
    }

    /// Factory durations: small 10/3, normal 25/5, big 90/15.
    public var defaultConfig: PomodoroKindConfig {
        switch self {
        case .small:  return .init(focusMinutes: 10, breakMinutes: 3)
        case .normal: return .init(focusMinutes: 25, breakMinutes: 5)
        case .big:    return .init(focusMinutes: 90, breakMinutes: 15)
        }
    }
}

/// Editable focus/break lengths for one pomodoro kind.
public struct PomodoroKindConfig: Codable, Equatable, Sendable {
    public var focusMinutes: Int
    public var breakMinutes: Int
    /// Per-size long-break override; nil = fall back to the global
    /// `PomodoroSettings.longBreakMinutes`. Synthesized Codable decodes a
    /// missing key as nil, so pre-per-size JSON blobs keep behaving identically.
    public var longBreakMinutes: Int? = nil
    public init(focusMinutes: Int, breakMinutes: Int, longBreakMinutes: Int? = nil) {
        self.focusMinutes = focusMinutes
        self.breakMinutes = breakMinutes
        self.longBreakMinutes = longBreakMinutes
    }
}

/// Which live "ears" the notch HUD grows while a session runs. The ears sit in
/// the menu bar row and therefore overlap the app's menu titles (left) and the
/// status items (right) — an inherent cost of the notch, so it is a choice.
public enum NotchEarsMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case both, trailingOnly, none
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .both:         return "Both sides"
        case .trailingOnly: return "Right only"
        case .none:         return "Progress bar only"
        }
    }

    /// The mode is not a label switch: an ear the user dropped is an ear the
    /// island does not *grow*, so the black — and the hit-test mask cut from it
    /// — stops covering that stretch of the menu bar. `NotchGeometry` sizes the
    /// live island off exactly these three counts.
    public var earCount: Int {
        switch self {
        case .both:         return 2
        case .trailingOnly: return 1
        case .none:         return 0
        }
    }

    /// The countdown's ear — the one that overlaps the app's *menu titles*, so
    /// it is the first one people give up.
    public var showsLeadingEar: Bool { self == .both }
    /// The task/phase ear, over the status items.
    public var showsTrailingEar: Bool { self != .none }
}

public struct PomodoroSettings: Codable, Equatable, Sendable {
    /// Per-kind duration overrides; a missing key means the factory default.
    public var kindConfigs: [String: PomodoroKindConfig] = [:]
    /// The kind the timer currently runs (picked manually or by the task).
    public var activeKind: PomodoroKind = .normal
    public var longBreakMinutes: Int = 15
    public var longBreakEvery: Int = 4
    public var autoStartFocus: Bool = false
    public var autoStartBreak: Bool = true
    public var notifyFiveMinLeft: Bool = true
    public var blockScreenDuringBreak: Bool = true
    public var breakMessage: String = "Close your eyes, breathe, look far away."
    public var ttsRate: Float = 0.5
    public var ttsPitch: Float = 1.0

    public var timerMode: TimerMode = .countdown
    public var timeFormat: TimeDisplayFormat = .minutesSeconds
    public var showExitBreakButton: Bool = false
    public var sharinganStyle: SharinganStyle = .classic
    /// O'ng ko'z uchun alohida uslub; nil = ikkala ko'z bir xil (sharinganStyle).
    public var sharinganStyleRight: SharinganStyle? = nil
    /// Break ekrani orqa foni (videodagi kulrang "graphite" default).
    public var breakBackgroundStyle: BreakBackgroundStyle = .graphite
    /// Break ekranida naqsh ochilish/yopilish (evolyutsiya) animatsiyasi tezligi.
    public var breakPatternTransition: PatternTransitionSpeed = .normal
    /// Aralash rejim: true = break davomida naqsh butun zanjir bo'ylab
    /// evolyutsiya qiladi (1 tomoe → 2 → 3 → Mangekyō…); false = faqat
    /// tanlangan uslub ko'rsatiladi (ochilish/yopilish saqlanadi).
    public var breakPatternMixed: Bool = false
    /// Break ekranida naqshning uzluksiz aylanishi: bir to'la aylanish
    /// davomiyligi soniyada (0 = aylanmaydi).
    public var breakPatternSpinSeconds: Double = 8
    /// MoveEyes ko'zlarini ish stoli orqa foni (jonli wallpaper) sifatida ko'rsatish.
    public var eyesWallpaperEnabled: Bool = false
    /// Wallpaper rejimida Sharingan qachon aylanadi.
    public var wallpaperSpinTrigger: WallpaperSpinTrigger = .idle
    /// Bir to'la aylanish davomiyligi, soniya.
    public var wallpaperSpinDuration: Double = 1.6
    /// Aylanish boshlanishidan oldin kutish (idle), soniya.
    public var wallpaperIdleDelay: Double = 1.2
    /// Mouse shuncha soniya tinch tursa wallpaper ko'zlari yumilib mudraydi.
    public var wallpaperDozeSeconds: Double = 60
    public var theme: SharinganTheme = .liquidGlass
    public var repeatConfig: RepeatConfig = .init()
    public var flashAtFiveSecLeft: Bool = true
    /// Floating widget: a control pill — active task, remaining time,
    /// Start / Stop / Reset — that docks flush against the Dock by default
    /// and can be dragged anywhere ("Return to Dock" re-docks it). NOTE: this
    /// property and the four below it keep their historical `dockWidget*`
    /// name prefix so existing settings JSON blobs decode unchanged; the
    /// feature's user-facing name is "Floating widget" everywhere else
    /// (types, UI copy, docs).
    public var dockWidgetEnabled: Bool = true
    /// Preset pill size (Small/Medium/Large).
    public var dockWidgetSize: FloatingWidgetSize = .medium
    /// Which end of a bottom Dock the pill hugs while docked; a vertical Dock
    /// ignores this and centers the pill instead — see `FloatingWidgetGeometry`.
    public var dockWidgetAlignment: FloatingWidgetAlignment = .trailing
    public var dockWidgetOpacity: Double = 1.0      // 0.3…1.0
    /// Rest compact (ring + time) and spring open under the pointer, like
    /// the Dock's now-playing widgets. Off = always fully open.
    public var dockWidgetExpandOnHover: Bool = true
    /// Always-on-desktop glass panel with today's tasks + timer state
    /// (the WidgetKit substitute for the SwiftPM build).
    public var showTodayPanel: Bool = false
    public var globalShortcutsEnabled: Bool = true
    /// Custom hotkey bindings keyed by `GlobalShortcut.rawValue`. Missing entries
    /// fall back to each shortcut's default combo.
    public var shortcutBindings: [String: ShortcutBinding] = [:]
    public var cameraEyeTrackingEnabled: Bool = false
    /// Kamera harakatni tasdiqlamaguncha mashq keyingi qadamga o'tmaydi
    /// (grace-period avto-o'tish o'chadi). Faqat kamera kuzatuvi yoqilgan va
    /// ruxsat berilgan bo'lsa kuchga kiradi.
    public var strictExerciseValidation: Bool = true
    public var alarmSound: String = AlarmSoundService.Sound.glass.rawValue
    public var alarmSoundEnabled: Bool = true
    public var ttsSettings: TTSAnnouncementsSettings = .init()
    public var exerciseSettings: ExerciseSequenceSettings = .init()
    public var reminderSettings: ReminderSettings = .init()
    public var ambienceEnabled: Bool = false
    public var ambienceSound: String = BreakAmbienceService.Ambience.rain.rawValue
    public var brightnessDimEnabled: Bool = false
    public var brightnessDimPercent: Int = 35
    public var brightnessSmooth: Bool = true
    /// Break vaqtida Night Shift bilan ekranni "isitib" (iliq ranglar)
    /// ko'zni dam oldirish; break tugagach asl holat qaytariladi.
    public var nightShiftBreakEnabled: Bool = false
    /// Night Shift kuchi break vaqtida (0…1).
    public var nightShiftBreakStrength: Double = 0.7
    public var launchAtLogin: Bool = false
    public var appBlockerSettings: AppBlockerSettings = .init()
    /// When on, a focus pomodoro cannot start unless a task is selected.
    public var requireTaskForFocus: Bool = true
    /// When on, distracting apps are blocked during the focus session too
    /// (not just during breaks).
    public var blockAppsDuringFocus: Bool = false
    /// Target number of focus pomodoros per day (0 = no goal).
    public var dailyPomodoroGoal: Int = 8
    /// Week columns/rows start on Monday (false = Sunday) in both week views.
    public var weekStartsOnMonday: Bool = true
    /// Estimate pre-filled on newly added subtasks (0 = none).
    public var defaultSubtaskEstimate: Int = 0
    /// Show 🍅 done/estimate badges on task & subtask rows.
    public var showPomodoroBadges: Bool = true
    /// Render board-card deadlines as a countdown ("2d 4h left") instead of the
    /// due date itself ("Fri 14:30"). Off = show the date. Task rows always show
    /// the date — the countdown is the board's read.
    public var deadlineAsCountdown: Bool = true
    /// Days a task stays in the Trash before it is permanently deleted
    /// automatically. 0 = keep forever (only manual "Delete forever" removes it).
    public var trashRetentionDays: Int = 30
    /// Custom display names for priority levels, keyed by String(rawValue).
    /// Missing keys fall back to the built-in Todoist-style labels.
    public var priorityNames: [String: String] = [:]
    /// Custom flag colors (hex) per priority level, keyed by String(rawValue).
    public var priorityColors: [String: String] = [:]
    /// User-added priority levels ABOVE the built-in P1 — their rawValues
    /// (each ≥ 4). Built-ins (0…3) are implicit and never stored here. Adding a
    /// custom level renumbers the built-ins down (see `priorityShortLabel`).
    public var customPriorityLevels: [Int] = []
    /// Custom icon/color per tag (label), keyed by the tag text.
    public var tagStyles: [String: TagStyle] = [:]
    /// Show the app's menu-bar icon at all. On = also rescues the icon when
    /// macOS has it parked in an invisible slot (⌘-dragged off, or pushed
    /// under a notched MacBook's camera housing by a crowded menu bar).
    public var showMenuBarIcon: Bool = true
    /// Show the MM:SS countdown next to the menu-bar icon while a session
    /// is engaged (off = icon only).
    public var showMenuBarCountdown: Bool = true
    /// Spin the Sharingan mark — the menu-bar tomoe and (while the main
    /// window is open) the Dock icon rotate slowly. Runtime-only; the .icns
    /// on disk stays static.
    public var animateIcon: Bool = true
    /// Toggle macOS Focus during focus sessions by running user-created
    /// Shortcuts (there is no public Focus API).
    public var dndEnabled: Bool = false
    public var dndShortcutOn: String = "Sharingan Focus On"
    public var dndShortcutOff: String = "Sharingan Focus Off"

    /// Notch HUD — the island around the camera housing.
    public var notchHUDEnabled: Bool = true
    public var notchEars: NotchEarsMode = .both
    public var notchLiveActivity: Bool = true
    /// What the *expanded* island shows. These are not cosmetic: the island's
    /// height is computed from them (`NotchGeometry.expandedSize`), so a section
    /// switched off is black the HUD stops hanging over the screen. They default
    /// to the always-on behavior the HUD shipped with.
    public var notchShowTimerControls: Bool = true
    public var notchShowTasks: Bool = true
    public var notchShowQuickActions: Bool = true
    public var notchShowStatusStrip: Bool = true
    /// How many of today's tasks the island lists. Clamped to
    /// `NotchContentConfig.taskRowRange` — the range the panel was measured for.
    public var notchTaskRows: Int = NotchTaskRows.defaultLimit

    /// The notch settings, projected into what the geometry actually needs. One
    /// projection, so the layout, the drawn shape and the hit-test mask cannot
    /// be reading three different ideas of what the island shows.
    public var notchContent: NotchContentConfig {
        NotchContentConfig(ears: notchEars,
                           showTimerControls: notchShowTimerControls,
                           showTasks: notchShowTasks,
                           showQuickActions: notchShowQuickActions,
                           showStatusStrip: notchShowStatusStrip,
                           taskRows: notchTaskRows)
    }

    /// UserDefaults key of the persisted settings JSON blob (owned by
    /// PomodoroTimer; exposed so tier seeding can detect an existing user).
    public static let defaultsKey = "com.sharingan.settings"

    public init() {}

    /// Durations for a kind — the user's override, else the factory default.
    public func config(for kind: PomodoroKind) -> PomodoroKindConfig {
        kindConfigs[kind.rawValue] ?? kind.defaultConfig
    }

    public mutating func setConfig(_ config: PomodoroKindConfig, for kind: PomodoroKind) {
        kindConfigs[kind.rawValue] = config
    }

    /// Focus length of the ACTIVE kind. Kept as a property (not renamed) so the
    /// timer, stats and CLI paths read whichever kind is currently selected.
    public var focusMinutes: Int {
        get { config(for: activeKind).focusMinutes }
        set {
            var c = config(for: activeKind)
            c.focusMinutes = newValue
            kindConfigs[activeKind.rawValue] = c
        }
    }

    /// Short-break length of the ACTIVE kind (long break stays global).
    public var shortBreakMinutes: Int {
        get { config(for: activeKind).breakMinutes }
        set {
            var c = config(for: activeKind)
            c.breakMinutes = newValue
            kindConfigs[activeKind.rawValue] = c
        }
    }

    // Pre-kinds blobs stored flat focus/short-break minutes; those keys are no
    // longer stored properties, so they need their own decode container.
    private enum LegacyKeys: String, CodingKey {
        case focusMinutes, shortBreakMinutes
    }

    // Defensive decoding: settings are stored as one JSON blob and new fields are
    // added often. With synthesized Decodable, an older blob missing ANY key would
    // throw and the whole settings object would silently reset to defaults. Decode
    // every field optionally, falling back to the default value.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PomodoroSettings()
        kindConfigs = try c.decodeIfPresent([String: PomodoroKindConfig].self,
                                            forKey: .kindConfigs) ?? [:]
        activeKind = ((try? c.decodeIfPresent(PomodoroKind.self, forKey: .activeKind)) ?? nil)
            ?? d.activeKind
        // Migrate a pre-kinds blob: its custom focus/break lengths become the
        // "normal" kind so an update doesn't reset the user's durations.
        if kindConfigs[PomodoroKind.normal.rawValue] == nil {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            let focus = try legacy.decodeIfPresent(Int.self, forKey: .focusMinutes)
            let brk = try legacy.decodeIfPresent(Int.self, forKey: .shortBreakMinutes)
            if focus != nil || brk != nil {
                kindConfigs[PomodoroKind.normal.rawValue] = PomodoroKindConfig(
                    focusMinutes: focus ?? 25, breakMinutes: brk ?? 5)
            }
        }
        longBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? d.longBreakMinutes
        longBreakEvery = try c.decodeIfPresent(Int.self, forKey: .longBreakEvery) ?? d.longBreakEvery
        autoStartFocus = try c.decodeIfPresent(Bool.self, forKey: .autoStartFocus) ?? d.autoStartFocus
        autoStartBreak = try c.decodeIfPresent(Bool.self, forKey: .autoStartBreak) ?? d.autoStartBreak
        notifyFiveMinLeft = try c.decodeIfPresent(Bool.self, forKey: .notifyFiveMinLeft) ?? d.notifyFiveMinLeft
        blockScreenDuringBreak = try c.decodeIfPresent(Bool.self, forKey: .blockScreenDuringBreak) ?? d.blockScreenDuringBreak
        breakMessage = try c.decodeIfPresent(String.self, forKey: .breakMessage) ?? d.breakMessage
        ttsRate = try c.decodeIfPresent(Float.self, forKey: .ttsRate) ?? d.ttsRate
        ttsPitch = try c.decodeIfPresent(Float.self, forKey: .ttsPitch) ?? d.ttsPitch
        timerMode = try c.decodeIfPresent(TimerMode.self, forKey: .timerMode) ?? d.timerMode
        timeFormat = try c.decodeIfPresent(TimeDisplayFormat.self, forKey: .timeFormat) ?? d.timeFormat
        showExitBreakButton = try c.decodeIfPresent(Bool.self, forKey: .showExitBreakButton) ?? d.showExitBreakButton
        sharinganStyle = try c.decodeIfPresent(SharinganStyle.self, forKey: .sharinganStyle) ?? d.sharinganStyle
        sharinganStyleRight = try c.decodeIfPresent(SharinganStyle.self, forKey: .sharinganStyleRight) ?? d.sharinganStyleRight
        breakBackgroundStyle = try c.decodeIfPresent(BreakBackgroundStyle.self, forKey: .breakBackgroundStyle) ?? d.breakBackgroundStyle
        breakPatternTransition = try c.decodeIfPresent(PatternTransitionSpeed.self, forKey: .breakPatternTransition) ?? d.breakPatternTransition
        breakPatternMixed = try c.decodeIfPresent(Bool.self, forKey: .breakPatternMixed) ?? d.breakPatternMixed
        breakPatternSpinSeconds = try c.decodeIfPresent(Double.self, forKey: .breakPatternSpinSeconds) ?? d.breakPatternSpinSeconds
        eyesWallpaperEnabled = try c.decodeIfPresent(Bool.self, forKey: .eyesWallpaperEnabled) ?? d.eyesWallpaperEnabled
        wallpaperSpinTrigger = try c.decodeIfPresent(WallpaperSpinTrigger.self, forKey: .wallpaperSpinTrigger) ?? d.wallpaperSpinTrigger
        wallpaperSpinDuration = try c.decodeIfPresent(Double.self, forKey: .wallpaperSpinDuration) ?? d.wallpaperSpinDuration
        wallpaperIdleDelay = try c.decodeIfPresent(Double.self, forKey: .wallpaperIdleDelay) ?? d.wallpaperIdleDelay
        wallpaperDozeSeconds = try c.decodeIfPresent(Double.self, forKey: .wallpaperDozeSeconds) ?? d.wallpaperDozeSeconds
        theme = try c.decodeIfPresent(SharinganTheme.self, forKey: .theme) ?? d.theme
        repeatConfig = try c.decodeIfPresent(RepeatConfig.self, forKey: .repeatConfig) ?? d.repeatConfig
        flashAtFiveSecLeft = try c.decodeIfPresent(Bool.self, forKey: .flashAtFiveSecLeft) ?? d.flashAtFiveSecLeft
        // Note: the `floating*` fields (Task 11 removed the floating timer) are
        // gone from this struct on purpose. `CodingKeys` is synthesized from the
        // struct's stored properties, so it no longer has those cases either —
        // an older persisted blob that still carries those JSON keys decodes fine
        // regardless, because `JSONDecoder`'s keyed container silently ignores
        // any key it has no matching `CodingKeys` case for.
        dockWidgetEnabled = try c.decodeIfPresent(Bool.self, forKey: .dockWidgetEnabled) ?? d.dockWidgetEnabled
        // Unknown raw values (a preset/side written by a newer build) fall back
        // to the default rather than throwing the whole blob away.
        dockWidgetSize = ((try? c.decodeIfPresent(FloatingWidgetSize.self, forKey: .dockWidgetSize)) ?? nil)
            ?? d.dockWidgetSize
        dockWidgetAlignment = ((try? c.decodeIfPresent(FloatingWidgetAlignment.self, forKey: .dockWidgetAlignment)) ?? nil)
            ?? d.dockWidgetAlignment
        dockWidgetOpacity = try c.decodeIfPresent(Double.self, forKey: .dockWidgetOpacity) ?? d.dockWidgetOpacity
        dockWidgetExpandOnHover = try c.decodeIfPresent(Bool.self, forKey: .dockWidgetExpandOnHover) ?? d.dockWidgetExpandOnHover
        showTodayPanel = try c.decodeIfPresent(Bool.self, forKey: .showTodayPanel) ?? d.showTodayPanel
        globalShortcutsEnabled = try c.decodeIfPresent(Bool.self, forKey: .globalShortcutsEnabled) ?? d.globalShortcutsEnabled
        shortcutBindings = try c.decodeIfPresent([String: ShortcutBinding].self, forKey: .shortcutBindings) ?? d.shortcutBindings
        cameraEyeTrackingEnabled = try c.decodeIfPresent(Bool.self, forKey: .cameraEyeTrackingEnabled) ?? d.cameraEyeTrackingEnabled
        strictExerciseValidation = try c.decodeIfPresent(Bool.self, forKey: .strictExerciseValidation) ?? d.strictExerciseValidation
        alarmSound = try c.decodeIfPresent(String.self, forKey: .alarmSound) ?? d.alarmSound
        alarmSoundEnabled = try c.decodeIfPresent(Bool.self, forKey: .alarmSoundEnabled) ?? d.alarmSoundEnabled
        ttsSettings = try c.decodeIfPresent(TTSAnnouncementsSettings.self, forKey: .ttsSettings) ?? d.ttsSettings
        exerciseSettings = try c.decodeIfPresent(ExerciseSequenceSettings.self, forKey: .exerciseSettings) ?? d.exerciseSettings
        reminderSettings = try c.decodeIfPresent(ReminderSettings.self, forKey: .reminderSettings) ?? d.reminderSettings
        ambienceEnabled = try c.decodeIfPresent(Bool.self, forKey: .ambienceEnabled) ?? d.ambienceEnabled
        ambienceSound = try c.decodeIfPresent(String.self, forKey: .ambienceSound) ?? d.ambienceSound
        brightnessDimEnabled = try c.decodeIfPresent(Bool.self, forKey: .brightnessDimEnabled) ?? d.brightnessDimEnabled
        brightnessDimPercent = try c.decodeIfPresent(Int.self, forKey: .brightnessDimPercent) ?? d.brightnessDimPercent
        brightnessSmooth = try c.decodeIfPresent(Bool.self, forKey: .brightnessSmooth) ?? d.brightnessSmooth
        nightShiftBreakEnabled = try c.decodeIfPresent(Bool.self, forKey: .nightShiftBreakEnabled) ?? d.nightShiftBreakEnabled
        nightShiftBreakStrength = try c.decodeIfPresent(Double.self, forKey: .nightShiftBreakStrength) ?? d.nightShiftBreakStrength
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        appBlockerSettings = try c.decodeIfPresent(AppBlockerSettings.self, forKey: .appBlockerSettings) ?? d.appBlockerSettings
        requireTaskForFocus = try c.decodeIfPresent(Bool.self, forKey: .requireTaskForFocus) ?? d.requireTaskForFocus
        blockAppsDuringFocus = try c.decodeIfPresent(Bool.self, forKey: .blockAppsDuringFocus) ?? d.blockAppsDuringFocus
        dailyPomodoroGoal = try c.decodeIfPresent(Int.self, forKey: .dailyPomodoroGoal) ?? d.dailyPomodoroGoal
        weekStartsOnMonday = try c.decodeIfPresent(Bool.self, forKey: .weekStartsOnMonday) ?? d.weekStartsOnMonday
        defaultSubtaskEstimate = try c.decodeIfPresent(Int.self, forKey: .defaultSubtaskEstimate) ?? d.defaultSubtaskEstimate
        showPomodoroBadges = try c.decodeIfPresent(Bool.self, forKey: .showPomodoroBadges) ?? d.showPomodoroBadges
        deadlineAsCountdown = try c.decodeIfPresent(Bool.self, forKey: .deadlineAsCountdown) ?? d.deadlineAsCountdown
        trashRetentionDays = try c.decodeIfPresent(Int.self, forKey: .trashRetentionDays) ?? d.trashRetentionDays
        priorityNames = try c.decodeIfPresent([String: String].self, forKey: .priorityNames) ?? d.priorityNames
        priorityColors = try c.decodeIfPresent([String: String].self, forKey: .priorityColors) ?? d.priorityColors
        customPriorityLevels = try c.decodeIfPresent([Int].self, forKey: .customPriorityLevels) ?? d.customPriorityLevels
        tagStyles = try c.decodeIfPresent([String: TagStyle].self, forKey: .tagStyles) ?? d.tagStyles
        showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? d.showMenuBarIcon
        showMenuBarCountdown = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarCountdown) ?? d.showMenuBarCountdown
        animateIcon = try c.decodeIfPresent(Bool.self, forKey: .animateIcon) ?? d.animateIcon
        dndEnabled = try c.decodeIfPresent(Bool.self, forKey: .dndEnabled) ?? d.dndEnabled
        dndShortcutOn = try c.decodeIfPresent(String.self, forKey: .dndShortcutOn) ?? d.dndShortcutOn
        dndShortcutOff = try c.decodeIfPresent(String.self, forKey: .dndShortcutOff) ?? d.dndShortcutOff
        notchHUDEnabled = try c.decodeIfPresent(Bool.self, forKey: .notchHUDEnabled) ?? d.notchHUDEnabled
        // An unknown raw value (a mode a newer build wrote) falls back to the
        // default rather than throwing the whole blob away, like `dockWidgetSize`.
        notchEars = ((try? c.decodeIfPresent(NotchEarsMode.self, forKey: .notchEars)) ?? nil)
            ?? d.notchEars
        notchLiveActivity = try c.decodeIfPresent(Bool.self, forKey: .notchLiveActivity) ?? d.notchLiveActivity
        notchShowTimerControls = try c.decodeIfPresent(Bool.self, forKey: .notchShowTimerControls) ?? d.notchShowTimerControls
        notchShowTasks = try c.decodeIfPresent(Bool.self, forKey: .notchShowTasks) ?? d.notchShowTasks
        notchShowQuickActions = try c.decodeIfPresent(Bool.self, forKey: .notchShowQuickActions) ?? d.notchShowQuickActions
        notchShowStatusStrip = try c.decodeIfPresent(Bool.self, forKey: .notchShowStatusStrip) ?? d.notchShowStatusStrip
        notchTaskRows = try c.decodeIfPresent(Int.self, forKey: .notchTaskRows) ?? d.notchTaskRows
    }

    /// Custom flag color (hex) for a tag, nil when the default should apply.
    public func tagColorHex(_ tag: String) -> String? {
        tagStyles[tag]?.colorHex
    }

    /// SF Symbol for a tag's mark ("at" by default).
    public func tagIcon(_ tag: String) -> String {
        tagStyles[tag]?.icon ?? "at"
    }

    /// Display name for a priority level — custom override, else the built-in.
    public func priorityName(_ p: TaskPriority) -> String {
        let custom = priorityNames[String(p.rawValue)]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (custom?.isEmpty == false ? custom! : p.menuLabel)
    }

    /// Flag color (hex) for a priority level — custom override, else built-in
    /// (nil for `.none`, which renders no flag).
    public func priorityColorHex(_ p: TaskPriority) -> String? {
        priorityColors[String(p.rawValue)] ?? p.colorHex
    }

    /// Rank-based chip label ("P1", "P2", …) computed against the current level
    /// ordering: customs sit above the built-ins, so adding one custom level
    /// makes IT "P1" and pushes built-in high to "P2". `.none` gets no chip.
    public func priorityShortLabel(_ p: TaskPriority) -> String {
        guard p != .none else { return "" }
        let ordered = TaskPriority.levels(custom: customPriorityLevels)
            .filter { $0 != .none }
        guard let idx = ordered.firstIndex(of: p) else { return p.label }
        return "P\(idx + 1)"
    }

    /// "Auto" mode: the whole focus ↔ break cycle runs hands-free (25 focus →
    /// break → focus → break → …), with no manual Start between phases. It maps
    /// to both auto-start flags so it reads as a single mode toggle.
    public var autoCycle: Bool {
        get { autoStartFocus && autoStartBreak }
        set { autoStartFocus = newValue; autoStartBreak = newValue }
    }

    public var focusSeconds: TimeInterval { TimeInterval(focusMinutes) * 60 }
    public var shortBreakSeconds: TimeInterval { TimeInterval(shortBreakMinutes) * 60 }
    /// Long-break length of the ACTIVE kind: per-size override, else the
    /// stored global value (pre-per-size blobs keep behaving identically).
    public var longBreakSeconds: TimeInterval {
        TimeInterval(config(for: activeKind).longBreakMinutes ?? longBreakMinutes) * 60
    }

    public func duration(for phase: PomodoroPhase) -> TimeInterval {
        // Floor real phases at 1s: a 0-minute duration (from decoded/CLI garbage)
        // would make the phase complete on its very first tick and, under auto
        // mode, spin through phases every tick — inflating stats and streaks.
        switch phase {
        case .focus:      return max(1, focusSeconds)
        case .shortBreak: return max(1, shortBreakSeconds)
        case .longBreak:  return max(1, longBreakSeconds)
        case .paused:     return 0
        }
    }

    /// Start of the week containing `now`, shifted by `offset` whole weeks.
    /// Anchored on Monday or Sunday per `weekStartsOnMonday` — the single week
    /// origin shared by the main-window board and the menu bar Week tab.
    public func weekStart(offset: Int = 0, now: Date = Date(),
                          calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)     // 1=Sun … 7=Sat
        let target = weekStartsOnMonday ? 2 : 1
        let sinceStart = (weekday - target + 7) % 7
        let start = calendar.date(byAdding: .day, value: -sinceStart, to: today) ?? today
        return calendar.date(byAdding: .day, value: offset * 7, to: start) ?? start
    }
}