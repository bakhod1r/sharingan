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
        shortcuts.update(actions, enabled: true)
    }

    public func syncAlarm() {
        AlarmSoundService.shared.selected =
            AlarmSoundService.Sound(rawValue: timer.settings.alarmSound) ?? .glass
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
                if running && self.timer.settings.floatingTimerEnabled {
                    self.floatingController?.showFloating(timer: self.timer)
                }
            }
            .store(in: &cancellables)

        timer.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncAll() }
            .store(in: &cancellables)
    }

    private func syncAll() {
        syncAlarm()
        installShortcuts()
        syncCamera()
        syncTTS()
        syncAmbience()
        syncReminders()
        TTSKalibrator.shared.update(settings: timer.settings.ttsSettings,
                                    rate: timer.settings.ttsRate,
                                    pitch: timer.settings.ttsPitch)
        ExerciseValidator.shared.exercises = timer.settings.exerciseSettings.buildSequence()
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
        let failures = timer.phase == .focus || timer.phase == .shortBreak
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

    private func handlePhaseComplete(_ note: Notification) {
        guard let phase = note.userInfo?["phase"] as? PomodoroPhase else { return }
        switch phase {
        case .focus:
            NotificationService.shared.notify(
                title: "Blink",
                body: "Focus complete. Starting break.",
                identifier: "blink.focusDone")
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