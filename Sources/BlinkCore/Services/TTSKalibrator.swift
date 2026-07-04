import Foundation
import Combine
import SwiftUI

/// Sinxron TTS yo'riqnoma — BreakExercise step'lari bilan birga ovoz chiqaradi.
/// Har step boshida instruction'ni, keyin har interval'da kalib (qisqa eslatma) gapiradi.
@MainActor
public final class TTSKalibrator: ObservableObject {
    public static let shared = TTSKalibrator()

    @Published public private(set) var isActive: Bool = false

    private var stepCancellable: AnyCancellable?
    private var kalibTask: Task<Void, Never>?
    private var kalibIndex = 0
    private var settings: TTSAnnouncementsSettings = .init()
    private var ttsRate: Float = 0.5
    private var ttsPitch: Float = 1.0

    public init() {}

    public func update(settings: TTSAnnouncementsSettings,
                       rate: Float = 0.5,
                       pitch: Float = 1.0) {
        self.settings = settings
        self.ttsRate = rate
        self.ttsPitch = pitch
    }

    /// ExerciseValidator bilan ulanib, har step o'zgarganda yo'riqnoma gapiradi.
    public func attach(to validator: ExerciseValidator) {
        stop()
        guard settings.enabled else { return }
        isActive = true
        stepCancellable = validator.$currentStepIndex
            .receive(on: RunLoop.main)
            .sink { [weak self, weak validator] _ in
                guard let self, let v = validator, let step = v.currentStep else { return }
                self.speakStep(step)
                self.restartKalib(for: step.holdSeconds, direction: step.direction)
            }
        if let step = validator.currentStep {
            speakStep(step)
            restartKalib(for: step.holdSeconds, direction: step.direction)
        }
    }

    public func stop() {
        isActive = false
        stepCancellable?.cancel()
        stepCancellable = nil
        kalibTask?.cancel()
        kalibTask = nil
    }

    private func speakStep(_ step: BreakExerciseStep) {
        let text = settings.instruction(forDirection: step.direction)?.text ?? step.instruction
        TTSService.shared.speak(text, rate: ttsRate, pitch: ttsPitch)
    }

    private func restartKalib(for holdSeconds: TimeInterval, direction: String) {
        kalibTask?.cancel()
        kalibIndex = 0
        let interval = settings.kalibIntervalSeconds
        guard interval > 0, holdSeconds > interval else { return }
        let pool = settings.instruction(forDirection: direction)?.kalibTexts
            ?? settings.globalKalib
        guard !pool.isEmpty else { return }
        kalibTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                let line = pool[self.kalibIndex % pool.count]
                self.kalibIndex += 1
                TTSService.shared.speak(line, rate: self.ttsRate, pitch: self.ttsPitch)
            }
        }
    }
}