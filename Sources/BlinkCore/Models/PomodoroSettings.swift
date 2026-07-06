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

    public init() {}

    public var focusSeconds: TimeInterval { TimeInterval(focusMinutes) * 60 }
    public var shortBreakSeconds: TimeInterval { TimeInterval(shortBreakMinutes) * 60 }
    public var longBreakSeconds: TimeInterval { TimeInterval(longBreakMinutes) * 60 }

    public func duration(for phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .focus:      return focusSeconds
        case .shortBreak: return shortBreakSeconds
        case .longBreak:  return longBreakSeconds
        case .paused:     return 0
        }
    }
}