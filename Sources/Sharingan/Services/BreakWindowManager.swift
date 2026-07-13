import AppKit
import SwiftUI
import SharinganCore

@MainActor
final class BreakWindowManager: BreakPresenter {
    static let shared = BreakWindowManager()
    private var panels: [NSPanel] = []
    private(set) var isBlocking = false

    func presentBreak(timer: PomodoroTimer,
                      onTapSkip: @escaping () -> Void) {
        present(timer: timer, forceExit: false, onTapSkip: onTapSkip)
    }

    /// Settings "Preview break screen" — always shows the Exit button so the
    /// preview can be dismissed even when the setting is off.
    func presentPreview(timer: PomodoroTimer,
                        onTapSkip: @escaping () -> Void) {
        present(timer: timer, forceExit: true, onTapSkip: onTapSkip)
    }

    private func present(timer: PomodoroTimer,
                         forceExit: Bool,
                         onTapSkip: @escaping () -> Void) {
        guard !isBlocking else { return }
        isBlocking = true
        // Session side effects live HERE, not in BreakView.onAppear — a view
        // is created per screen, so on multi-display setups the validator was
        // reset and the camera started once per monitor.
        beginBreakSession(timer: timer)
        NSApp.activate(ignoringOtherApps: true)

        for screen in NSScreen.screens {
            let panel = BreakPanel(contentRect: screen.frame,
                                   styleMask: [.borderless, .fullSizeContentView],
                                   backing: .buffered, defer: false, screen: screen)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                        .stationary, .ignoresCycle]
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isMovable = false
            panel.ignoresMouseEvents = false

            let view = BreakView(timer: timer,
                                 onTapSkip: { [weak self] in
                                     self?.dismissAll()
                                     onTapSkip()
                                 },
                                 forceExit: forceExit)
                .environmentObject(timer)
            let hosting = NSHostingView(rootView: view)
            hosting.translatesAutoresizingMaskIntoConstraints = false
            panel.contentView = hosting
            // Fade the whole overlay in so the screen never recolors in one
            // jarring frame — the break eases over what the user was doing.
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.6
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for p in panels { p.animator().alphaValue = 1 }
        }
        // The overlay now covers every screen. It is drawn far above the island
        // (`BreakPanel.level == .screenSaver`, the notch panel sits just above
        // the menu bar), so this is not about z-order: standing the HUD down
        // stops its hit-test mask claiming clicks in the strip of overlay it
        // covers, and stops the island surfacing again as the overlay fades out.
        // Both `presentBreak` and `presentPreview` funnel through here, so this
        // is the one place that needs the call.
        NotchWindowManager.shared.setBreakOverlay(true)
    }

    func dismissAll() {
        // Stand the island back up before anything else, so there is no frame
        // where the overlay is gone and the HUD hasn't caught up yet. Every
        // teardown path — natural break completion, the in-overlay Skip
        // button (via `timer.skip()`), and the Settings "Preview break
        // screen" button's own onTapSkip — calls this one method.
        NotchWindowManager.shared.setBreakOverlay(false)
        if isBlocking { endBreakSession() }
        let fading = panels
        panels.removeAll()
        isBlocking = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            for p in fading { p.animator().alphaValue = 0 }
        }, completionHandler: {
            for p in fading {
                p.contentView = nil
                p.orderOut(nil)
            }
        })
    }
}

extension BreakWindowManager {
    /// Runs once per break (the TTS announcement itself comes from
    /// SharinganCoordinator on real breaks; the preview stays silent).
    private func beginBreakSession(timer: PomodoroTimer) {
        TTSKalibrator.shared.update(settings: timer.settings.ttsSettings,
                                    rate: timer.settings.ttsRate,
                                    pitch: timer.settings.ttsPitch)
        TTSKalibrator.shared.attach(to: ExerciseValidator.shared)
        let validator = ExerciseValidator.shared
        validator.exercises = timer.settings.exerciseSettings.buildSequence()
        // Strict mode is armed only after the camera is confirmed usable —
        // otherwise a permission denial would leave steps waiting forever for
        // a confirmation that can never arrive.
        validator.strictValidation = false
        validator.reset()
        validator.start()
        // Camera runs only for the duration of the break screen, never in focus.
        if timer.settings.cameraEyeTrackingEnabled {
            let strict = timer.settings.strictExerciseValidation
            Task { @MainActor in
                let granted = await CameraService.shared.requestPermission()
                validator.strictValidation = strict && granted
                CameraService.shared.start()
                EyeTracker.shared.resetBlinkWindow()
                EyeTracker.shared.start()
            }
        }
    }

    private func endBreakSession() {
        TTSService.shared.stop()
        TTSKalibrator.shared.stop()
        ExerciseValidator.shared.stop()
        EyeTracker.shared.stop()
        CameraService.shared.stop()
    }
}

private final class BreakPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) { return true }
        return super.performKeyEquivalent(with: event)
    }
    override func cancelOperation(_ sender: Any?) {}
}