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
    /// **No default value, deliberately.** A stored property that *has* one is
    /// already initialized by the time an `init` body runs, so `self.stats = …`
    /// in an initializer is an ordinary assignment — it goes through the setter
    /// and fires `didSet`. With `= .init()` here, every `PomodoroTimer` ever
    /// constructed re-encoded the stats it had just loaded and wrote them back to
    /// the user's defaults, including in a render process, which is supposed to
    /// read the user's data and never write it. (The values were identical, so
    /// nothing was lost — but a render that reloads at t₀ and writes back at t₀+ε
    /// would happily clobber a completion the real app registered in between.)
    ///
    /// Without a default, the assignment in `init` *is* the initialization, no
    /// observer runs, and nothing is persisted until something actually changes
    /// the stats. `settings` has always worked this way, which is why it never
    /// had the bug.
    @Published public private(set) var stats: PomodoroStats {
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

    /// A timer driven by a settings **value** rather than by what is on disk.
    ///
    /// **This is how a render dresses a view without writing to the user's
    /// settings.** `settings` persists in its `didSet`, so `timer.settings.x = y`
    /// — the obvious way to style a preview — rewrites the user's real
    /// preferences as a side effect of taking a screenshot. An assignment inside
    /// `init` does not run `didSet`, so building the value first and handing it
    /// here writes nothing. `--render-break-preview` is the caller (see
    /// `HeadlessRender`); any later render that needs different settings must
    /// come through here too.
    ///
    /// Mutating `settings` on the returned timer persists exactly as it always
    /// has: this initializer changes where the *initial* value comes from, and
    /// nothing else.
    public init(settings: PomodoroSettings) {
        self.settings = settings
        self.remainingSeconds = settings.focusSeconds
        self.stats = Self.loadStats()
    }

    /// The settings as they are on disk — a read, so a render can copy them,
    /// change one field and hand the copy to `init(settings:)`.
    public static func savedSettings() -> PomodoroSettings { loadSettings() }

    // MARK: - Control

    public func start() {
        guard !isRunning else { return }
        isMirroredSession = false
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
        isMirroredSession = false
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
        // Skipping while paused must advance from the REAL phase — falling
        // into transitionToNext's `.paused: break` arm changed nothing yet
        // still wiped durationOverride and repeatIndex.
        isMirroredSession = false
        if phase == .paused { phase = previousPhase }
        // Kill the tick loop BEFORE transitioning (pause/stop/phaseComplete all
        // do). A live in-flight tick wakes ≤200 ms later and writes the dead
        // phase's preciseRemaining over the fresh duration — skipping a break
        // left an idle "focus" showing the break's leftover countdown, and the
        // next start() ran focus with that leftover as its whole session.
        isRunning = false
        cancelLoop()
        transitionToNext()
    }

    /// Starts (or resumes) a focus session — the single entry point for every
    /// task-row play button. A session paused mid-focus resumes where it left
    /// off (a plain `phase != .focus` check would wrongly reset it, because
    /// pausing rewrites `phase` to `.paused`); a break is reset to a fresh
    /// focus session first.
    ///
    /// `kind` carries the task/subtask's pomodoro size (nil = keep the current
    /// one). A DIFFERENT kind restarts the session fresh — resuming 7 minutes
    /// into a Small session as a Big one would misattribute the whole block.
    public func startFocusSession(kind: PomodoroKind? = nil) {
        let kindChanged = kind != nil && kind != settings.activeKind
        if let kind { settings.activeKind = kind }
        let effective = phase == .paused ? previousPhase : phase
        if effective != .focus || kindChanged { stop() }
        start()
    }

    /// True while nothing is in flight and the pending phase is a focus — the
    /// fresh/reset state. The main window shows the in-ring size picker exactly
    /// then; any live state (running, paused, or waiting at a break) keeps the
    /// phase label instead.
    public var isIdleAtFocus: Bool { !isRunning && phase == .focus }

    /// Switches the pomodoro size (Small/Normal/Big). While idle, the pending
    /// phase duration refreshes immediately so the countdown shows the new
    /// length; a running session keeps its current block untouched.
    public func applyKind(_ kind: PomodoroKind) {
        guard settings.activeKind != kind else { return }
        settings.activeKind = kind
        guard !isRunning else { return }
        durationOverride = nil
        let effective = phase == .paused ? previousPhase : phase
        remainingSeconds = settings.duration(for: effective)
        elapsedSeconds = 0
        syncPrecise()
    }

    public func toggle() {
        isRunning ? pause() : start()
    }

    /// The real phase behind `.paused` (which masks it) — what a sync
    /// publisher must report, or a paused break would mirror as "paused
    /// nothing" on the other Mac.
    public var effectivePhase: PomodoroPhase {
        phase == .paused ? previousPhase : phase
    }

    /// True while this timer is a lockstep copy of another Mac's session.
    /// A mirrored phase that runs out completes passively: the owner Mac
    /// decides (and publishes) what comes next, so `phaseComplete` must not
    /// auto-start the following phase here — doing so made every synced Mac
    /// race the owner and kick off its own pomodoro after a break. Any local
    /// control action (start/stop/skip) takes ownership and clears it.
    public private(set) var isMirroredSession = false

    /// Mirrors another Mac's session in lockstep (iCloud timer sync).
    ///
    /// Aligned to the wall clock, not to durations: a running session adopts
    /// the remote's absolute `endsAt`, so both Macs end the phase at the same
    /// moment regardless of fetch latency. A paused session freezes at the
    /// remaining time computed against `asOf` (the pause moment on the other
    /// Mac), so it reads identically however late the record arrives.
    ///
    /// This is the ONE programmatic entry point that can set a phase directly
    /// with an explicit deadline — the sharingan:// / CLI paths can only walk
    /// the normal transitions, which cannot represent "be 7 minutes into the
    /// other Mac's break".
    public func applyMirroredSession(phase remotePhase: PomodoroPhase,
                                     isPaused: Bool,
                                     startedAt: Date,
                                     endsAt: Date?,
                                     asOf: Date,
                                     now: Date = Date()) {
        guard remotePhase != .paused else { return }   // isPaused carries that
        isMirroredSession = true
        isRunning = false
        cancelLoop()
        cancelRepeatJob()
        let referenceEnd = endsAt ?? now
        let total = max(1, referenceEnd.timeIntervalSince(startedAt))
        durationOverride = total
        let remaining = max(0, referenceEnd.timeIntervalSince(isPaused ? asOf : now))
        remainingSeconds = remaining
        elapsedSeconds = max(0, total - remaining)
        syncPrecise()
        if isPaused {
            previousPhase = remotePhase
            phase = .paused
        } else {
            phase = remotePhase
            fiveMinSent = false
            flashSent = false
            isFlashing = false
            isRunning = true
            runLoop()
        }
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
                let dt = Self.effectiveTickDelta(
                    now.timeIntervalSince(s.lastTickDate ?? now), phase: s.phase)
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

    /// Ticks land every ~200 ms; a gap of 30+ s means the machine was asleep
    /// (the process suspended). During focus that gap must NOT count — it
    /// credited entire lid-closed hours as completed pomodoros — so it
    /// collapses to a single ordinary tick. During a break the opposite holds:
    /// sleep rests the eyes just as well, and freezing the countdown left the
    /// break overlay up long after the break should have ended, so the full
    /// gap counts and the break completes on wake.
    nonisolated public static func effectiveTickDelta(_ dt: TimeInterval,
                                                      phase: PomodoroPhase) -> TimeInterval {
        guard dt > 30 else { return dt }
        return phase.isBreak ? dt : 0.2
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
        let willRepeat = !isMirroredSession
            && repeatCfg.enabled
            && !repeatCfg.endless
            && phase == .focus
            && repeatIndex < repeatCfg.count - 1
        NotificationCenter.default.post(name: .phaseDidComplete, object: self,
                                        userInfo: ["phase": phase,
                                                   "willRepeat": willRepeat,
                                                   "mirrored": isMirroredSession,
                                                   // The completed session's real
                                                   // length; count-up also ends at
                                                   // totalSeconds. Captured here
                                                   // because delivery is async and
                                                   // the timer transitions first.
                                                   "seconds": totalSeconds])

        if willRepeat {
            scheduleRepeat()
            return
        }
        // A mirrored phase completes passively: the OWNER Mac auto-starts the
        // next phase and publishes it, and this Mac follows that record —
        // auto-starting here too raced the owner and spawned a second,
        // locally-owned session (a surprise pomodoro right after the break).
        transitionToNext(auto: !isMirroredSession)
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

    private static let settingsKey = PomodoroSettings.defaultsKey
    private static let statsKey = "com.sharingan.stats"

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
    /// The one "a phase really finished" signal — posted from `phaseComplete()`
    /// and nowhere else (`pause()`, `stop()` and `skip()` never post it). Public
    /// because the app layer's notch HUD announces completions off it: the phase
    /// itself cannot be trusted for that, since pausing and resetting rewrite it
    /// just the same. `userInfo["phase"]` is the `PomodoroPhase` that completed.
    public static let phaseDidComplete = Notification.Name("sharingan.phaseDidComplete")
    static let focusFiveMinLeft = Notification.Name("sharingan.focusFiveMinLeft")
    static let breakShouldStart = Notification.Name("sharingan.breakShouldStart")
    static let breakShouldEnd   = Notification.Name("sharingan.breakShouldEnd")
    static let streakUpdated    = Notification.Name("sharingan.streakUpdated")
    static let dailyGoalReached = Notification.Name("sharingan.dailyGoalReached")
}