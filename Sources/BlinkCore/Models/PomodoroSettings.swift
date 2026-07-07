import Foundation

public struct PomodoroSettings: Codable, Equatable, Sendable {
    public var focusMinutes: Int = 25
    public var shortBreakMinutes: Int = 5
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
    public var theme: BlinkTheme = .liquidGlass
    public var repeatConfig: RepeatConfig = .init()
    public var flashAtFiveSecLeft: Bool = true
    public var floatingTimerEnabled: Bool = true
    /// Floating timer appearance (position is remembered separately, in
    /// UserDefaults, to avoid churning settings on every drag).
    public var floatingOpacity: Double = 1.0        // 0.3…1.0
    public var floatingCompact: Bool = false        // smaller pill
    public var floatingAlwaysOnTop: Bool = true      // above other apps
    public var globalShortcutsEnabled: Bool = true
    /// Custom hotkey bindings keyed by `GlobalShortcut.rawValue`. Missing entries
    /// fall back to each shortcut's default combo.
    public var shortcutBindings: [String: ShortcutBinding] = [:]
    public var cameraEyeTrackingEnabled: Bool = false
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
    public var launchAtLogin: Bool = false
    public var appBlockerSettings: AppBlockerSettings = .init()
    /// When on, a focus pomodoro cannot start unless a task is selected.
    public var requireTaskForFocus: Bool = true
    /// When on, distracting apps are blocked during the focus session too
    /// (not just during breaks).
    public var blockAppsDuringFocus: Bool = false
    /// Target number of focus pomodoros per day (0 = no goal).
    public var dailyPomodoroGoal: Int = 8

    public init() {}

    // Defensive decoding: settings are stored as one JSON blob and new fields are
    // added often. With synthesized Decodable, an older blob missing ANY key would
    // throw and the whole settings object would silently reset to defaults. Decode
    // every field optionally, falling back to the default value.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PomodoroSettings()
        focusMinutes = try c.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? d.focusMinutes
        shortBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? d.shortBreakMinutes
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
        theme = try c.decodeIfPresent(BlinkTheme.self, forKey: .theme) ?? d.theme
        repeatConfig = try c.decodeIfPresent(RepeatConfig.self, forKey: .repeatConfig) ?? d.repeatConfig
        flashAtFiveSecLeft = try c.decodeIfPresent(Bool.self, forKey: .flashAtFiveSecLeft) ?? d.flashAtFiveSecLeft
        floatingTimerEnabled = try c.decodeIfPresent(Bool.self, forKey: .floatingTimerEnabled) ?? d.floatingTimerEnabled
        floatingOpacity = try c.decodeIfPresent(Double.self, forKey: .floatingOpacity) ?? d.floatingOpacity
        floatingCompact = try c.decodeIfPresent(Bool.self, forKey: .floatingCompact) ?? d.floatingCompact
        floatingAlwaysOnTop = try c.decodeIfPresent(Bool.self, forKey: .floatingAlwaysOnTop) ?? d.floatingAlwaysOnTop
        globalShortcutsEnabled = try c.decodeIfPresent(Bool.self, forKey: .globalShortcutsEnabled) ?? d.globalShortcutsEnabled
        shortcutBindings = try c.decodeIfPresent([String: ShortcutBinding].self, forKey: .shortcutBindings) ?? d.shortcutBindings
        cameraEyeTrackingEnabled = try c.decodeIfPresent(Bool.self, forKey: .cameraEyeTrackingEnabled) ?? d.cameraEyeTrackingEnabled
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
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        appBlockerSettings = try c.decodeIfPresent(AppBlockerSettings.self, forKey: .appBlockerSettings) ?? d.appBlockerSettings
        requireTaskForFocus = try c.decodeIfPresent(Bool.self, forKey: .requireTaskForFocus) ?? d.requireTaskForFocus
        blockAppsDuringFocus = try c.decodeIfPresent(Bool.self, forKey: .blockAppsDuringFocus) ?? d.blockAppsDuringFocus
        dailyPomodoroGoal = try c.decodeIfPresent(Int.self, forKey: .dailyPomodoroGoal) ?? d.dailyPomodoroGoal
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
    public var longBreakSeconds: TimeInterval { TimeInterval(longBreakMinutes) * 60 }

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
}