import Foundation
import SwiftUI
import Combine

@MainActor
public final class PomodoroTimer: ObservableObject {
    @Published public private(set) var phase: PomodoroPhase = .focus
    @Published public private(set) var remainingSeconds: TimeInterval = 0
    @Published public private(set) var elapsedSeconds: TimeInterval = 0
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var cyclesCompletedInRound: Int = 0
    @Published public private(set) var repeatIndex: Int = 0
    @Published public private(set) var stats: PomodoroStats = .init() {
        didSet { persist(stats) }
    }

    public func applyRemoteStats(_ value: PomodoroStats) {
        stats = value
    }
    @Published public private(set) var isFlashing: Bool = false

    @Published public var settings: PomodoroSettings {
        didSet { persist(settings) }
    }

    private var tickTask: Task<Void, Never>?
    private var lastTickDate: Date?
    private var repeatJob: Task<Void, Never>?

    public var mode: TimerMode { settings.timerMode }

    public var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        switch mode {
        case .countdown: return 1 - (remainingSeconds / totalSeconds)
        case .countUp:   return min(1, elapsedSeconds / totalSeconds)
        }
    }

    public var totalSeconds: TimeInterval {
        settings.duration(for: phase == .paused ? previousPhase : phase)
    }

    public var isCountUpMode: Bool { mode == .countUp }

    private var previousPhase: PomodoroPhase = .focus
    private var fiveMinSent = false

    public init() {
        let saved = Self.loadSettings()
        self.settings = saved
        self.remainingSeconds = saved.focusSeconds
        self.stats = Self.loadStats()
    }

    // MARK: - Control

    public func start() {
        guard !isRunning else { return }
        if phase == .paused { phase = previousPhase }
        isRunning = true
        fiveMinSent = false
        isFlashing = false
        runLoop()
    }

    public func pause() {
        guard isRunning else { return }
        previousPhase = phase
        phase = .paused
        isRunning = false
        cancelLoop()
    }

    public func stop() {
        isRunning = false
        cancelLoop()
        cancelRepeatJob()
        remainingSeconds = settings.duration(for: .focus)
        elapsedSeconds = 0
        phase = .focus
        cyclesCompletedInRound = 0
        repeatIndex = 0
        isFlashing = false
    }

    public func skip() {
        transitionToNext()
    }

    public func toggle() {
        isRunning ? pause() : start()
    }

    public func addTime(_ seconds: TimeInterval) {
        remainingSeconds = max(0, remainingSeconds + seconds)
    }

    public func removeTime(_ seconds: TimeInterval) {
        remainingSeconds = max(0, remainingSeconds - seconds)
    }

    public func setCustomDuration(_ seconds: TimeInterval) {
        guard seconds > 0 else { return }
        remainingSeconds = seconds
        elapsedSeconds = 0
        isRunning = false
        cancelLoop()
    }

    public func setTargetTime(_ date: Date) {
        let delta = max(0, date.timeIntervalSinceNow)
        setCustomDuration(delta)
    }

    public func applyParsed(_ input: ParsedTimerInput) {
        switch input.kind {
        case .setDuration(let d) where d == 0:
            stop()
        case .setDuration(let d):
            setCustomDuration(d)
        case .setTargetTime(let date):
            setTargetTime(date)
        case .addTime(let d):
            addTime(d)
        case .removeTime(let d):
            removeTime(d)
        }
    }

    // MARK: - Loop

    private func runLoop() {
        cancelLoop()
        lastTickDate = .now
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled, let s = self, s.isRunning {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                let now = Date.now
                let dt = now.timeIntervalSince(s.lastTickDate ?? now)
                s.lastTickDate = now
                switch s.mode {
                case .countdown:
                    s.remainingSeconds -= dt
                    s.elapsedSeconds += dt
                case .countUp:
                    s.elapsedSeconds += dt
                    s.remainingSeconds = max(0, s.totalSeconds - s.elapsedSeconds)
                }
                s.tickChecks()
                if s.remainingSeconds <= 0 && !s.isCountUpMode {
                    s.remainingSeconds = 0
                    s.phaseComplete()
                    return
                }
                if s.isCountUpMode && s.elapsedSeconds >= s.totalSeconds {
                    s.phaseComplete()
                    return
                }
            }
        }
    }

    private func cancelLoop() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func phaseComplete() {
        isRunning = false
        cancelLoop()
        if settings.flashAtFiveSecLeft { triggerFlash() }
        if phase == .focus {
            stats.registerFocusCompletion()
            persist(stats)
            cyclesCompletedInRound += 1
            NotificationCenter.default.post(name: .streakUpdated,
                                            object: self,
                                            userInfo: ["streak": stats.streak])
        }
        NotificationCenter.default.post(name: .phaseDidComplete, object: self,
                                        userInfo: ["phase": phase])

        if settings.repeatConfig.enabled,
           phase == .focus,
           repeatIndex < settings.repeatConfig.count - 1 {
            scheduleRepeat()
            return
        }
        transitionToNext(auto: true)
    }

    private func scheduleRepeat() {
        cancelRepeatJob()
        let delay = settings.repeatConfig.delaySeconds
        repeatJob = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
            }
            self?.repeatIndex += 1
            self?.remainingSeconds = self?.settings.duration(for: .focus) ?? 0
            self?.elapsedSeconds = 0
            self?.phase = .focus
            self?.start()
        }
    }

    private func cancelRepeatJob() {
        repeatJob?.cancel()
        repeatJob = nil
    }

    private func triggerFlash() {
        isFlashing = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.isFlashing = false
        }
    }

    private func transitionToNext(auto: Bool = false) {
        switch phase {
        case .focus:
            let isLong = cyclesCompletedInRound % settings.longBreakEvery == 0
                && cyclesCompletedInRound > 0
            let next: PomodoroPhase = isLong ? .longBreak : .shortBreak
            remainingSeconds = settings.duration(for: next)
            elapsedSeconds = 0
            phase = next
        case .shortBreak, .longBreak:
            if phase == .longBreak { cyclesCompletedInRound = 0 }
            remainingSeconds = settings.duration(for: .focus)
            elapsedSeconds = 0
            phase = .focus
        case .paused:
            break
        }
        repeatIndex = 0
        let shouldAutoStart = phase == .focus ? settings.autoStartFocus : settings.autoStartBreak
        if auto && shouldAutoStart {
            start()
        } else {
            isRunning = false
        }
    }

    public func tickChecks() {
        if settings.notifyFiveMinLeft,
           !fiveMinSent,
           remainingSeconds <= 300,
           remainingSeconds > 0,
           phase == .focus {
            fiveMinSent = true
            NotificationCenter.default.post(name: .focusFiveMinLeft, object: self)
        }
    }

    // MARK: - Persistence

    private static let settingsKey = "com.blink.settings"
    private static let statsKey = "com.blink.stats"

    private static func loadSettings() -> PomodoroSettings {
        guard let d = UserDefaults.standard.data(forKey: settingsKey),
              let s = try? JSONDecoder().decode(PomodoroSettings.self, from: d) else {
            return .init()
        }
        return s
    }
    private func persist(_ s: PomodoroSettings) {
        if let d = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(d, forKey: Self.settingsKey)
        }
    }
    private static func loadStats() -> PomodoroStats {
        guard let d = UserDefaults.standard.data(forKey: statsKey),
              let s = try? JSONDecoder().decode(PomodoroStats.self, from: d) else {
            return .init()
        }
        return s
    }
    private func persist(_ s: PomodoroStats) {
        if let d = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(d, forKey: Self.statsKey)
        }
    }
}

extension Notification.Name {
    static let phaseDidComplete = Notification.Name("blink.phaseDidComplete")
    static let focusFiveMinLeft = Notification.Name("blink.focusFiveMinLeft")
    static let breakShouldStart = Notification.Name("blink.breakShouldStart")
    static let breakShouldEnd   = Notification.Name("blink.breakShouldEnd")
    static let streakUpdated    = Notification.Name("blink.streakUpdated")
}