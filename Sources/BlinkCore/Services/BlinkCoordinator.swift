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

        timer.$isRunning
            .receive(on: RunLoop.main)
            .sink { [weak self] running in
                guard let self else { return }
                if running && self.timer.settings.floatingTimerEnabled {
                    self.floatingController?.showFloating(timer: self.timer)
                } else if !running {
                    // Keep floating visible while paused so the user can
                    // re-resume at a glance; hide only when stopped via
                    // floating toggle.
                }
            }
            .store(in: &cancellables)
    }

    private func handlePhaseComplete(_ note: Notification) {
        guard let phase = note.userInfo?["phase"] as? PomodoroPhase else { return }
        switch phase {
        case .focus:
            NotificationService.shared.notify(
                title: "Blink",
                body: "Diqqat tugadi. Tanaffus boshlanadi.",
                identifier: "blink.focusDone")
            floatingController?.hideFloating()
            if let p = breakPresenter, timer.settings.blockScreenDuringBreak {
                p.presentBreak(
                    timer: timer,
                    onTapSkip: { [weak self] in self?.timer.skip() }
                )
            }
            speakBreakStart()
        case .shortBreak, .longBreak:
            NotificationService.shared.notify(
                title: "Blink",
                body: "Tanaffus tugadi. Diqqatga qaytamiz.",
                identifier: "blink.breakDone")
            breakPresenter?.dismissAll()
            speakFocusStart()
        case .paused:
            break
        }
    }

    private func speakBreakStart() {
        guard timer.settings.ttsEnabled else { return }
        TTSService.shared.speak(
            "Tanaffus boshlandi. \(timer.settings.breakMessage)",
            rate: timer.settings.ttsRate,
            pitch: timer.settings.ttsPitch)
    }

    private func speakFocusStart() {
        guard timer.settings.ttsEnabled else { return }
        TTSService.shared.speak(
            "Tanaffus tugadi. Diqqatga qaytashingiz mumkin.",
            rate: timer.settings.ttsRate,
            pitch: timer.settings.ttsPitch)
    }
}