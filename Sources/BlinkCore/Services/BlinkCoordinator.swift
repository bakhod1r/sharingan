import Foundation
import Combine
import SwiftUI

@MainActor
public protocol FloatingTimerController: AnyObject {
    func showFloating(timer: PomodoroTimer)
    func hideFloating()
    func toggleFloating(timer: PomodoroTimer)
}

@MainActor
public final class BlinkCoordinator: ObservableObject {
    public let timer: PomodoroTimer
    public var breakPresenter: BreakPresenter?
    public var floatingController: FloatingTimerController?
    public var shortcuts: KeyboardShortcutsService = .shared
    private var cancellables: Set<AnyCancellable> = []
    private var cliObservers: [String: Any] = [:]
    private var snapshotCancellable: AnyCancellable?

    public init(timer: PomodoroTimer) {
        self.timer = timer
        observe()
    }

    public func installShortcuts() {
        guard timer.settings.globalShortcutsEnabled else {
            shortcuts.unregister()
            return
        }
        let actions: [GlobalShortcut: () -> Void] = [
            .toggle:        { [weak self] in self?.timer.toggle() },
            .skip:         { [weak self] in self?.timer.skip() },
            .reset:        { [weak self] in self?.timer.stop() },
            .addFive:      { [weak self] in self?.timer.addTime(300) },
            .showFloating: { [weak self] in
                guard let self else { return }
                self.floatingController?.toggleFloating(timer: self.timer)
            }
        ]
        var bindings: [GlobalShortcut: ShortcutBinding] = [:]
        for (key, binding) in timer.settings.shortcutBindings {
            if let shortcut = GlobalShortcut(rawValue: key) { bindings[shortcut] = binding }
        }
        shortcuts.update(actions, bindings: bindings, enabled: true)
    }

    public func syncAlarm() {
        // Honor the "alarm sound" toggle centrally: a disabled alarm maps to `.silent`
        // so every `playSelected()` call site stays a no-op without extra guards.
        AlarmSoundService.shared.selected = timer.settings.alarmSoundEnabled
            ? (AlarmSoundService.Sound(rawValue: timer.settings.alarmSound) ?? .glass)
            : .silent
    }

    public func syncCamera() {
        let wantCamera = timer.settings.cameraEyeTrackingEnabled
        Task { @MainActor in
            if wantCamera {
                _ = await CameraService.shared.requestPermission()
                CameraService.shared.start()
                EyeTracker.shared.start()
            } else {
                EyeTracker.shared.stop()
                CameraService.shared.stop()
            }
        }
    }

    public func syncFloating() {
        guard timer.settings.floatingTimerEnabled else {
            floatingController?.hideFloating()
            return
        }
        if timer.isRunning { floatingController?.showFloating(timer: timer) }
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

    public func publishSnapshot() {
        let snap = CLIBridge.StateSnapshot(
            phase: timer.phase,
            remainingSeconds: timer.remainingSeconds,
            totalSeconds: timer.totalSeconds,
            isRunning: timer.isRunning,
            cyclesCompletedToday: timer.stats.completedToday,
            streak: timer.stats.streak.currentStreak
        )
        CLIBridge.writeSnapshot(snap)
    }

    private func observe() {
        NotificationCenter.default.publisher(for: .phaseDidComplete)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in self?.handlePhaseComplete(note) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .focusFiveMinLeft)
            .receive(on: RunLoop.main)
            .sink { _ in NotificationService.shared.focusFiveMinLeft() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .streakUpdated)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in self?.handleStreakUpdate(note) }
            .store(in: &cancellables)

        timer.$isRunning
            .receive(on: RunLoop.main)
            .sink { [weak self] running in
                guard let self else { return }
                // Floating timer is shown only while a pomodoro is actually running.
                if running && self.timer.settings.floatingTimerEnabled {
                    self.floatingController?.showFloating(timer: self.timer)
                } else {
                    self.floatingController?.hideFloating()
                }
            }
            .store(in: &cancellables)

        timer.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncAll() }
            .store(in: &cancellables)

        timer.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.publishSnapshot() }
            .store(in: &cancellables)
        timer.$remainingSeconds
            .receive(on: RunLoop.main)
            .dropFirst()
            .sink { [weak self] _ in self?.publishSnapshot() }
            .store(in: &cancellables)
        timer.$isRunning
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.publishSnapshot() }
            .store(in: &cancellables)
    }

    private func syncAll() {
        syncAlarm()
        installShortcuts()
        syncCamera()
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

    private func startAppBlocker() {
        guard timer.settings.appBlockerSettings.enabled, timer.settings.blockScreenDuringBreak else {
            return
        }
        AppBlockerService.shared.update(timer.settings.appBlockerSettings)
        AppBlockerService.shared.activate()
    }

    private func stopAppBlocker() {
        AppBlockerService.shared.deactivate()
    }

    private func handlePhaseComplete(_ note: Notification) {
        guard let phase = note.userInfo?["phase"] as? PomodoroPhase else { return }
        switch phase {
        case .focus:
            NotificationService.shared.notify(
                title: "Blink",
                body: "Focus complete. Starting break.",
                identifier: "blink.focusDone")
            if let taskID = TaskStore.shared.activeTaskID {
                TaskStore.shared.incrementPomodoro(taskID)
            }
            AlarmSoundService.shared.playSelected()
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
            startAppBlocker()
            if timer.settings.cameraEyeTrackingEnabled {
                EyeTracker.shared.resetBlinkWindow()
            }
        case .shortBreak, .longBreak:
            NotificationService.shared.notify(
                title: "Blink",
                body: "Break complete. Back to focus.",
                identifier: "blink.breakDone")
            AlarmSoundService.shared.playSelected()
            breakPresenter?.dismissAll()
            BreakAmbienceService.shared.stop()
            restoreBrightness()
            stopAppBlocker()
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
        StreakRewardCenter.shared.evaluate(streak: streak.currentStreak)
        if let reward = StreakRewardCenter.shared.pendingReward {
            NotificationService.shared.notify(
                title: "Blink — Milestone achieved",
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
}