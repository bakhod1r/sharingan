import Foundation
import Combine
import SwiftUI

@MainActor
public protocol FloatingTimerController: AnyObject {
    func showFloating(timer: PomodoroTimer)
    func hideFloating()
    func toggleFloating(timer: PomodoroTimer)
    /// Re-apply appearance settings (opacity, size, level) to a visible panel.
    func refreshFloating(timer: PomodoroTimer)
}

@MainActor
public protocol QuickAddController: AnyObject {
    /// Pop up the global quick-add-task window.
    func showQuickAdd()
}

@MainActor
public final class BlinkCoordinator: ObservableObject {
    public let timer: PomodoroTimer
    public var breakPresenter: BreakPresenter?
    public var floatingController: FloatingTimerController?
    public var quickAddController: QuickAddController?
    public var shortcuts: KeyboardShortcutsService = .shared
    private var cancellables: Set<AnyCancellable> = []
    private var cliObservers: [String: Any] = [:]
    private var snapshotCancellable: AnyCancellable?

    public init(timer: PomodoroTimer) {
        self.timer = timer
        // Prime the reward baseline from the already-earned streak so restarting
        // the app doesn't re-announce milestones the user passed days ago.
        StreakRewardCenter.shared.prime(streak: timer.stats.streak.currentStreak)
        observe()
    }

    public func installShortcuts() {
        guard timer.settings.globalShortcutsEnabled else {
            shortcuts.unregister()
            return
        }
        let actions: [GlobalShortcut: () -> Void] = [
            .toggle:        { [weak self] in self?.toggleRespectingTaskGuard() },
            .skip:         { [weak self] in self?.timer.skip() },
            .reset:        { [weak self] in self?.timer.stop() },
            .addFive:      { [weak self] in self?.timer.addTime(300) },
            .showFloating: { [weak self] in
                guard let self else { return }
                self.floatingController?.toggleFloating(timer: self.timer)
            },
            .quickAddTask: { [weak self] in self?.quickAddController?.showQuickAdd() }
        ]
        var bindings: [GlobalShortcut: ShortcutBinding] = [:]
        for (key, binding) in timer.settings.shortcutBindings {
            if let shortcut = GlobalShortcut(rawValue: key) { bindings[shortcut] = binding }
        }
        shortcuts.update(actions, bindings: bindings, enabled: true)
    }

    /// Toggle the timer, but refuse to *start* a focus session when the
    /// "require a task" rule is on and nothing is selected — pop the quick-add
    /// window instead so the user can capture one.
    public func toggleRespectingTaskGuard() {
        if !timer.isRunning,
           timer.phase == .focus,
           timer.settings.requireTaskForFocus,
           TaskStore.shared.activeTask == nil {
            quickAddController?.showQuickAdd()
            return
        }
        timer.toggle()
    }

    public func syncAlarm() {
        // Honor the "alarm sound" toggle centrally: a disabled alarm maps to `.silent`
        // so every `playSelected()` call site stays a no-op without extra guards.
        AlarmSoundService.shared.selected = timer.settings.alarmSoundEnabled
            ? (AlarmSoundService.Sound(rawValue: timer.settings.alarmSound) ?? .glass)
            : .silent
    }

    public func syncCamera() {
        // The camera runs ONLY during a break (started/stopped by BreakView), never
        // during focus. So we don't start anything here — we only tear it down if
        // the feature was switched off while a break happens to be active.
        guard !timer.settings.cameraEyeTrackingEnabled else { return }
        EyeTracker.shared.stop()
        CameraService.shared.stop()
    }

    public func syncFloating() {
        guard timer.settings.floatingTimerEnabled else {
            floatingController?.hideFloating()
            return
        }
        if timer.isRunning { floatingController?.showFloating(timer: timer) }
        floatingController?.refreshFloating(timer: timer)
    }

    public func installCLIBridge() {
        cliObservers.removeAll()
        cliObservers["start"]    = CLIBridge.observe(CLIBridge.darwinCommandStart)    { [weak self] p in self?.cliStart(payload: p) }
        cliObservers["pause"]    = CLIBridge.observe(CLIBridge.darwinCommandPause)   { [weak self] _ in self?.timer.pause() }
        cliObservers["resume"]   = CLIBridge.observe(CLIBridge.darwinCommandResume)  { [weak self] _ in self?.timer.start() }
        cliObservers["skip"]     = CLIBridge.observe(CLIBridge.darwinCommandSkip)    { [weak self] _ in self?.timer.skip() }
        cliObservers["stop"]     = CLIBridge.observe(CLIBridge.darwinCommandStop)    { [weak self] _ in self?.timer.stop() }
        cliObservers["add"]      = CLIBridge.observe(CLIBridge.darwinCommandAdd)     { [weak self] p in self?.cliAdjust(payload: p, negative: false) }
        cliObservers["remove"]   = CLIBridge.observe(CLIBridge.darwinCommandRemove)  { [weak self] p in self?.cliAdjust(payload: p, negative: true) }
        cliObservers["setDur"]   = CLIBridge.observe(CLIBridge.darwinCommandSetDuration) { [weak self] p in self?.cliSetDuration(p) }
        publishSnapshot()
    }

    private func cliStart(payload: String?) {
        let p = payload ?? ""
        if p.isEmpty {
            if !timer.isRunning { timer.start() }
        } else if let parsed = NaturalLanguageParser.parse(p) {
            timer.applyParsed(parsed)
            if case .setDuration = parsed.kind, !timer.isRunning { timer.start() }
        } else if let mins = Int(p) {
            timer.setCustomDuration(TimeInterval(mins) * 60)
            if !timer.isRunning { timer.start() }
        }
        publishSnapshot()
    }

    private func cliAdjust(payload: String?, negative: Bool) {
        let p = payload ?? "5m"
        let parsed = NaturalLanguageParser.parse(p)
        if case .addTime(let d) = parsed?.kind {
            timer.addTime(negative ? -d : d)
        } else if case .removeTime(let d) = parsed?.kind {
            timer.addTime(negative ? d : -d)
        } else if let mins = Int(p.trimmingCharacters(in: .letters).trimmingCharacters(in: .whitespaces)),
                  mins > 0 {
            timer.addTime(Double(negative ? -mins : mins) * 60)
        }
        publishSnapshot()
    }

    private func cliSetDuration(_ p: String?) {
        guard let p = p, !p.isEmpty else { return }
        if let parsed = NaturalLanguageParser.parse(p), case .setDuration(let d) = parsed.kind {
            timer.setCustomDuration(d)
        } else if let mins = Int(p.trimmingCharacters(in: .letters).trimmingCharacters(in: .whitespaces)), mins > 0 {
            timer.setCustomDuration(TimeInterval(mins) * 60)
        }
        publishSnapshot()
    }

    /// Reference point of the last write, used to skip writes the CLI can
    /// reconstruct on its own (the natural 1 s countdown).
    private var lastSnapshotRef: (remaining: TimeInterval, at: Date)?

    public func publishSnapshot() {
        let snap = CLIBridge.StateSnapshot(
            phase: timer.phase,
            remainingSeconds: timer.remainingSeconds,
            totalSeconds: timer.totalSeconds,
            isRunning: timer.isRunning,
            cyclesCompletedToday: timer.stats.completedTodayCount(),
            streak: timer.stats.streak.currentStreak,
            updatedAt: Date()
        )
        lastSnapshotRef = (timer.remainingSeconds, Date())
        CLIBridge.writeSnapshot(snap)
    }

    // NOTE: all sinks hop via DispatchQueue.main, NOT RunLoop.main — the
    // RunLoop scheduler only fires in the .default run-loop mode, so an open
    // menu or a drag/scroll (event-tracking mode) would stall the break
    // overlay, alarm, and DND toggle until tracking ends.
    private func observe() {
        NotificationCenter.default.publisher(for: .phaseDidComplete)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in self?.handlePhaseComplete(note) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .focusFiveMinLeft)
            .receive(on: DispatchQueue.main)
            .sink { _ in NotificationService.shared.focusFiveMinLeft() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .streakUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in self?.handleStreakUpdate(note) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .dailyGoalReached)
            .receive(on: DispatchQueue.main)
            .sink { note in
                let n = note.userInfo?["count"] as? Int ?? 0
                NotificationService.shared.notify(
                    title: "Daily goal reached 🎯",
                    body: "\(n)/\(n) pomodoros today. Great work!",
                    identifier: "blink.dailyGoal")
            }
            .store(in: &cancellables)

        timer.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                guard let self else { return }
                // Floating timer is shown only while a pomodoro is actually running.
                if running && self.timer.settings.floatingTimerEnabled {
                    self.floatingController?.showFloating(timer: self.timer)
                } else {
                    self.floatingController?.hideFloating()
                }
                // Blocking distracting apps follows the running state so pausing
                // a focus session releases them, resuming re-blocks.
                self.refreshAppBlocker()
                self.syncDND()
                self.publishSnapshot()
            }
            .store(in: &cancellables)

        timer.$settings
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] s in
                self?.syncChanged(s)
                self?.syncDND()
            }
            .store(in: &cancellables)

        timer.$phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.publishSnapshot()
                self?.refreshAppBlocker()
            }
            .store(in: &cancellables)
        // The CLI reconstructs a running countdown from `updatedAt`, so the
        // per-second tick needs no write — only publish when remaining jumps
        // in a way wall-clock can't explain (addTime, set, stop, …).
        timer.$remainingSeconds
            .receive(on: DispatchQueue.main)
            .dropFirst()
            .sink { [weak self] rem in
                guard let self else { return }
                guard let last = self.lastSnapshotRef else { self.publishSnapshot(); return }
                let elapsed = Date().timeIntervalSince(last.at)
                let expected = self.timer.isRunning ? last.remaining - elapsed : last.remaining
                if abs(rem - expected) > 2 { self.publishSnapshot() }
            }
            .store(in: &cancellables)
    }

    /// The last settings value each service group was synced against. Syncing
    /// everything on every `$settings` emission re-registered all Carbon
    /// hotkeys and re-queried SMAppService dozens of times per second while a
    /// slider was being dragged — so each group only syncs when its own slice
    /// of the settings actually changed.
    private var lastSyncedSettings: PomodoroSettings?

    private func syncChanged(_ new: PomodoroSettings) {
        guard let old = lastSyncedSettings else {
            lastSyncedSettings = new
            syncAll()
            return
        }
        lastSyncedSettings = new
        if old.alarmSoundEnabled != new.alarmSoundEnabled
            || old.alarmSound != new.alarmSound { syncAlarm() }
        if old.globalShortcutsEnabled != new.globalShortcutsEnabled
            || old.shortcutBindings != new.shortcutBindings { installShortcuts() }
        if old.cameraEyeTrackingEnabled != new.cameraEyeTrackingEnabled { syncCamera() }
        if old.floatingTimerEnabled != new.floatingTimerEnabled
            || old.floatingOpacity != new.floatingOpacity
            || old.floatingCompact != new.floatingCompact
            || old.floatingAlwaysOnTop != new.floatingAlwaysOnTop { syncFloating() }
        if old.appBlockerSettings != new.appBlockerSettings
            || old.blockScreenDuringBreak != new.blockScreenDuringBreak
            || old.blockAppsDuringFocus != new.blockAppsDuringFocus { refreshAppBlocker() }
        if old.ttsSettings.enabled != new.ttsSettings.enabled { syncTTS() }
        if old.ambienceEnabled != new.ambienceEnabled
            || old.ambienceSound != new.ambienceSound { syncAmbience() }
        if old.reminderSettings != new.reminderSettings { syncReminders() }
        if old.launchAtLogin != new.launchAtLogin { syncLaunchAtLogin() }
        if old.ttsSettings != new.ttsSettings
            || old.ttsRate != new.ttsRate
            || old.ttsPitch != new.ttsPitch {
            TTSKalibrator.shared.update(settings: new.ttsSettings,
                                        rate: new.ttsRate,
                                        pitch: new.ttsPitch)
        }
        if old.exerciseSettings != new.exerciseSettings {
            ExerciseValidator.shared.exercises = new.exerciseSettings.buildSequence()
        }
    }

    private func syncAll() {
        syncAlarm()
        installShortcuts()
        syncCamera()
        syncFloating()
        refreshAppBlocker()
        syncTTS()
        syncAmbience()
        syncReminders()
        syncLaunchAtLogin()
        TTSKalibrator.shared.update(settings: timer.settings.ttsSettings,
                                    rate: timer.settings.ttsRate,
                                    pitch: timer.settings.ttsPitch)
        ExerciseValidator.shared.exercises = timer.settings.exerciseSettings.buildSequence()
    }

    private func syncLaunchAtLogin() {
        let want = timer.settings.launchAtLogin
        guard want != LaunchAtLoginService.shared.isEnabled else { return }
        LaunchAtLoginService.shared.setEnabled(want)
    }

    private func syncTTS() {
        guard timer.settings.ttsSettings.enabled else {
            TTSService.shared.stop()
            return
        }
    }

    private func syncAmbience() {
        BreakAmbienceService.shared.selected =
            BreakAmbienceService.Ambience(rawValue: timer.settings.ambienceSound) ?? .rain
        if timer.settings.ambienceEnabled, timer.phase.isBreak {
            BreakAmbienceService.shared.start()
        } else if !timer.settings.ambienceEnabled {
            BreakAmbienceService.shared.stop()
        }
    }

    private func syncReminders() {
        ReminderService.shared.update(timer.settings.reminderSettings,
                                      focusPhase: timer.phase == .focus)
    }

    private func startAmbience() {
        guard timer.settings.ambienceEnabled else { return }
        BreakAmbienceService.shared.selected =
            BreakAmbienceService.Ambience(rawValue: timer.settings.ambienceSound) ?? .rain
        BreakAmbienceService.shared.start()
    }

    private func startBrightnessDim() {
        BrightnessService.shared.enabled = timer.settings.brightnessDimEnabled
        BrightnessService.shared.levelPercent = Float(timer.settings.brightnessDimPercent)
        BrightnessService.shared.smooth = timer.settings.brightnessSmooth
        BrightnessService.shared.dimToBreak()
    }

    private func restoreBrightness() {
        BrightnessService.shared.restore()
    }

    /// Drive the app blocker from the current phase + settings: block during a
    /// break (when "block screen" is on) and/or during a running focus session
    /// (when "block during focus" is on).
    func refreshAppBlocker() {
        let s = timer.settings
        let blocker = s.appBlockerSettings
        guard blocker.enabled else {
            AppBlockerService.shared.deactivate()
            return
        }
        // "Always block" mode (onlyDuringBreak == false): keep distracting apps
        // blocked the whole time the app runs, regardless of phase.
        if !blocker.onlyDuringBreak {
            AppBlockerService.shared.update(blocker)
            AppBlockerService.shared.activate()
            return
        }
        // Otherwise blocking is phase-driven: during a break (when "block screen"
        // is on) and/or during a running focus session (when "block during focus").
        let isBreak = (timer.phase == .shortBreak || timer.phase == .longBreak)
        let isFocus = (timer.phase == .focus)
        let shouldBlock = (isBreak && s.blockScreenDuringBreak)
            || (isFocus && s.blockAppsDuringFocus && timer.isRunning)
        if shouldBlock {
            AppBlockerService.shared.update(blocker)
            AppBlockerService.shared.activate()
        } else {
            AppBlockerService.shared.deactivate()
        }
    }

    /// DND follows "a focus session is actually running" — pausing or
    /// finishing focus restores normal mode; breaks never engage it.
    public func syncDND() {
        DNDShortcutService.shared.sync(
            focusActive: timer.isRunning && timer.phase == .focus,
            settings: timer.settings)
    }

    private func handlePhaseComplete(_ note: Notification) {
        guard let phase = note.userInfo?["phase"] as? PomodoroPhase else { return }
        syncDND()
        let willRepeat = note.userInfo?["willRepeat"] as? Bool ?? false
        switch phase {
        case .focus:
            // A completed focus still counts as a pomodoro for the active task.
            if let taskID = TaskStore.shared.activeTaskID {
                TaskStore.shared.incrementPomodoro(taskID)
            }
            AlarmSoundService.shared.playSelected()

            // Repetition: no break happens, so skip the entire break sequence
            // (overlay, dim, ambience, blocker) — just note the rep and return.
            if willRepeat {
                NotificationService.shared.notify(
                    title: "Blink",
                    body: "Focus session done — next repetition starting.",
                    identifier: "blink.repeat")
                return
            }

            NotificationService.shared.notify(
                title: "Blink",
                body: "Focus complete. Starting break.",
                identifier: "blink.focusDone")
            ReminderService.shared.pauseForBreak()
            floatingController?.hideFloating()
            if let p = breakPresenter, timer.settings.blockScreenDuringBreak {
                p.presentBreak(
                    timer: timer,
                    onTapSkip: { [weak self] in self?.timer.skip() }
                )
            }
            speakBreakStart()
            startAmbience()
            startBrightnessDim()
            refreshAppBlocker()
        case .shortBreak, .longBreak:
            NotificationService.shared.notify(
                title: "Blink",
                body: "Break complete. Back to focus.",
                identifier: "blink.breakDone")
            AlarmSoundService.shared.playSelected()
            breakPresenter?.dismissAll()
            BreakAmbienceService.shared.stop()
            restoreBrightness()
            refreshAppBlocker()
            // Belt-and-suspenders: BreakView.onDisappear stops the camera, but make
            // sure it's released even if the break was dismissed some other way.
            EyeTracker.shared.stop()
            CameraService.shared.stop()
            speakFocusStart()
            ReminderService.shared.resumeForFocus()
        case .paused:
            break
        }
    }

    private func speakBreakStart() {
        guard timer.settings.ttsSettings.enabled else { return }
        TTSService.shared.speak(
            "Break started. \(timer.settings.breakMessage)",
            rate: timer.settings.ttsRate,
            pitch: timer.settings.ttsPitch)
    }

    private func speakFocusStart() {
        guard timer.settings.ttsSettings.enabled else { return }
        TTSService.shared.speak(
            "Break complete. You can return to focus.",
            rate: timer.settings.ttsRate,
            pitch: timer.settings.ttsPitch)
    }

    private func handleStreakUpdate(_ note: Notification) {
        guard let streak = note.userInfo?["streak"] as? StreakStore else { return }
        // Announce ONLY a newly-unlocked milestone. Reading the lingering
        // pendingReward instead made it re-speak "First pomodoro" on every
        // pomodoro until the banner was dismissed.
        guard let reward = StreakRewardCenter.shared.evaluate(streak: streak.currentStreak) else {
            return
        }
        NotificationService.shared.notify(
            title: "Sharingan — Milestone achieved",
            body: "\(reward.badge.emoji) \(reward.badge.title): \(reward.badge.subtitle)",
            identifier: "blink.streak.\(reward.badge.id)"
        )
        if timer.settings.ttsSettings.enabled {
            TTSService.shared.speak(
                "Achievement unlocked: \(reward.badge.title). \(reward.badge.subtitle)",
                rate: timer.settings.ttsRate,
                pitch: timer.settings.ttsPitch)
        }
    }
}