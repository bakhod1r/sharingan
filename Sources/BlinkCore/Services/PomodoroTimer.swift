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

    /// The loop ticks every 200 ms for accuracy, but writing the @Published
    /// values at that cadence re-renders every observing hierarchy 5×/second
    /// for the whole session (including retained-but-hidden windows). Time is
    /// accumulated here and published only when the whole second flips.
    private var preciseRemaining: TimeInterval = 0
    private var preciseElapsed: TimeInterval = 0

    private func syncPrecise() {
        preciseRemaining = remainingSeconds
        preciseElapsed = elapsedSeconds
    }

    public var mode: TimerMode { settings.timerMode }

    public var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        switch mode {
        case .countdown: return 1 - (remainingSeconds / totalSeconds)
        case .countUp:   return min(1, elapsedSeconds / totalSeconds)
        }
    }

    /// When set (by CLI/quick commands), overrides the phase's settings duration
    /// for the current session so custom lengths survive count-up recomputation
    /// and progress stays in sync. Cleared on any phase transition.
    private var durationOverride: TimeInterval?

    public var totalSeconds: TimeInterval {
        durationOverride ?? settings.duration(for: phase == .paused ? previousPhase : phase)
    }

    public var isCountUpMode: Bool { mode == .countUp }

    private var previousPhase: PomodoroPhase = .focus
    private var fiveMinSent = false
    private var flashSent = false

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
        flashSent = false
        isFlashing = false
        runLoop()
    }

    public func pause() {
        guard isRunning else { return }
        previousPhase = phase
        phase = .paused
        isRunning = false
        cancelLoop()
        // Surface the exact stopping point (published values lag by <1 s).
        remainingSeconds = preciseRemaining
        elapsedSeconds = preciseElapsed
    }

    public func stop() {
        isRunning = false
        cancelLoop()
        cancelRepeatJob()
        durationOverride = nil
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

    /// Starts (or resumes) a focus session — the single entry point for every
    /// task-row play button. A session paused mid-focus resumes where it left
    /// off (a plain `phase != .focus` check would wrongly reset it, because
    /// pausing rewrites `phase` to `.paused`); a break is reset to a fresh
    /// focus session first.
    public func startFocusSession() {
        let effective = phase == .paused ? previousPhase : phase
        if effective != .focus { stop() }
        start()
    }

    public func toggle() {
        isRunning ? pause() : start()
    }

    public func addTime(_ seconds: TimeInterval) {
        // Extend the session total too, otherwise count-up recomputes remaining
        // from settings every tick and the adjustment vanishes. Updating both
        // keeps them consistent (next count-up tick recomputes to the same value).
        durationOverride = max(1, totalSeconds + seconds)
        remainingSeconds = max(0, remainingSeconds + seconds)
        syncPrecise()
    }

    public func removeTime(_ seconds: TimeInterval) {
        durationOverride = max(1, totalSeconds - seconds)
        remainingSeconds = max(0, remainingSeconds - seconds)
        syncPrecise()
    }

    public func setCustomDuration(_ seconds: TimeInterval) {
        guard seconds > 0 else { return }
        durationOverride = seconds
        remainingSeconds = seconds
        elapsedSeconds = 0
        isRunning = false
        cancelLoop()
        syncPrecise()
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
        syncPrecise()
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled, let s = self, s.isRunning {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                let now = Date.now
                let dt = now.timeIntervalSince(s.lastTickDate ?? now)
                s.lastTickDate = now
                switch s.mode {
                case .countdown:
                    s.preciseRemaining -= dt
                    s.preciseElapsed += dt
                case .countUp:
                    s.preciseElapsed += dt
                    s.preciseRemaining = max(0, s.totalSeconds - s.preciseElapsed)
                }
                if floor(s.preciseRemaining) != floor(s.remainingSeconds)
                    || floor(s.preciseElapsed) != floor(s.elapsedSeconds) {
                    s.remainingSeconds = s.preciseRemaining
                    s.elapsedSeconds = s.preciseElapsed
                }
                s.tickChecks()
                if s.preciseRemaining <= 0 && !s.isCountUpMode {
                    s.preciseRemaining = 0
                    s.remainingSeconds = 0
                    s.phaseComplete()
                    return
                }
                if s.isCountUpMode && s.preciseElapsed >= s.totalSeconds {
                    s.elapsedSeconds = s.preciseElapsed
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

    /// True only at the exact completion that lands on the goal, so the
    /// celebration fires once per day without any extra persisted state.
    nonisolated public static func goalJustReached(count: Int, goal: Int) -> Bool {
        goal > 0 && count == goal
    }

    private func phaseComplete() {
        isRunning = false
        cancelLoop()
        if phase == .focus {
            stats.registerFocusCompletion()
            persist(stats)
            cyclesCompletedInRound += 1
            NotificationCenter.default.post(name: .streakUpdated,
                                            object: self,
                                            userInfo: ["streak": stats.streak])
            if Self.goalJustReached(count: stats.completedTodayCount(),
                                    goal: settings.dailyPomodoroGoal) {
                NotificationCenter.default.post(
                    name: .dailyGoalReached, object: self,
                    userInfo: ["count": settings.dailyPomodoroGoal])
            }
        }
        // A repetition restarts focus WITHOUT an intervening break, so tell the
        // coordinator not to run the break sequence (overlay/dim/ambience) for it.
        // Finite repeat runs focus sessions back-to-back (no break between them);
        // endless runs the normal focus↔break cycle forever, so it must NOT skip
        // the break — it just keeps auto-advancing (see transitionToNext).
        let repeatCfg = settings.repeatConfig
        let willRepeat = repeatCfg.enabled
            && !repeatCfg.endless
            && phase == .focus
            && repeatIndex < repeatCfg.count - 1
        NotificationCenter.default.post(name: .phaseDidComplete, object: self,
                                        userInfo: ["phase": phase, "willRepeat": willRepeat])

        if willRepeat {
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
            self?.durationOverride = nil
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
        // A new phase always uses its own settings duration.
        durationOverride = nil
        switch phase {
        case .focus:
            // Guard the divisor: a user-entered `longBreakEvery` of 0 would trap
            // on `% 0` and crash the whole app.
            let every = max(1, settings.longBreakEvery)
            let isLong = cyclesCompletedInRound % every == 0
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
        // Endless repeat loops the focus↔break cycle forever, so it auto-advances
        // every phase regardless of the individual auto-start toggles.
        let endlessLoop = settings.repeatConfig.enabled && settings.repeatConfig.endless
        let shouldAutoStart = endlessLoop
            || (phase == .focus ? settings.autoStartFocus : settings.autoStartBreak)
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
        // Flash a warning when ~5 seconds remain — as the setting name promises —
        // not at 0 (which gave no advance warning).
        if settings.flashAtFiveSecLeft,
           !flashSent,
           remainingSeconds <= 5,
           remainingSeconds > 0 {
            flashSent = true
            triggerFlash()
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
    static let dailyGoalReached = Notification.Name("blink.dailyGoalReached")
}