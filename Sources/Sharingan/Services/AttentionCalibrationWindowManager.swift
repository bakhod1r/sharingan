import AppKit
import SwiftUI
import Combine
import SharinganCore

/// Five-point calibration: the user looks at a red dot in the centre and each
/// corner; the head-pose / gaze range seen meanwhile becomes their personal
/// "looking at the screen" envelope. The only attention panel that takes key
/// focus — Esc cancels.
@MainActor
final class AttentionCalibrationWindowManager {
    static let shared = AttentionCalibrationWindowManager()

    private static let settleSeconds = 0.4
    private static let collectSeconds = 1.1

    private let model = AttentionCalibrationModel()
    private var panel: NSPanel?
    private var task: Task<Void, Never>?
    private var cancellable: AnyCancellable?
    private var samples: [AttentionSample] = []
    private var collecting = false
    private var leased = false
    private var finishing = false

    var isRunning: Bool { panel != nil }

    /// `onFinish` gets the new calibration, or nil if cancelled / failed.
    func run(onFinish: @escaping (AttentionCalibration?) -> Void) {
        guard panel == nil, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        model.phase = .intro
        let p = CalibrationPanel(contentRect: screen.frame,
                                 styleMask: [.borderless, .fullSizeContentView],
                                 backing: .buffered, defer: false, screen: screen)
        p.level = .screenSaver
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isOpaque = true
        p.backgroundColor = .black
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.onCancel = { [weak self] in self?.finish(nil, onFinish: onFinish, delay: 0) }
        p.contentView = NSHostingView(rootView: AttentionCalibrationView(model: model))
        panel = p
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)

        task = Task { @MainActor [weak self] in
            guard let self else { return }
            let granted = await CameraService.shared.requestPermission()
            guard !Task.isCancelled else { return }
            guard granted else {
                self.model.phase = .failed("Camera access is off. Allow it in System Settings.")
                self.finish(nil, onFinish: onFinish, delay: 2.5)
                return
            }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            self.beginCollecting()
            for i in AttentionCalibrationModel.targets.indices {
                guard !Task.isCancelled else { return }
                self.model.phase = .target(i)
                // Let the eyes travel before sampling.
                try? await Task.sleep(nanoseconds: UInt64(Self.settleSeconds * 1e9))
                self.collecting = true
                try? await Task.sleep(nanoseconds: UInt64(Self.collectSeconds * 1e9))
                self.collecting = false
            }
            guard !Task.isCancelled else { return }
            let cal = AttentionCalibration.from(samples: self.samples)
            if let cal {
                self.model.phase = .done
                self.finish(cal, onFinish: onFinish, delay: 1.2)
            } else {
                self.model.phase = .failed("Your face wasn't visible. Check the camera and try again.")
                self.finish(nil, onFinish: onFinish, delay: 2.5)
            }
        }
    }

    private func beginCollecting() {
        samples = []
        EyeTracker.shared.acquire(.calibration)
        leased = true
        cancellable = EyeTracker.shared.$state.dropFirst().sink { [weak self] st in
            guard let self, self.collecting else { return }
            self.samples.append(AttentionSample(
                faceDetected: st.faceDetected, yaw: st.yaw, pitch: st.pitch,
                gaze: st.gaze, eyesClosed: st.isBlinking, at: Date()))
        }
    }

    private func finish(_ cal: AttentionCalibration?,
                        onFinish: @escaping (AttentionCalibration?) -> Void,
                        delay: TimeInterval) {
        guard !finishing else { return }
        finishing = true
        task?.cancel()
        task = nil
        collecting = false
        cancellable = nil
        if leased { leased = false; EyeTracker.shared.release(.calibration) }
        onFinish(cal)
        let close = { [weak self] in
            self?.panel?.contentView = nil
            self?.panel?.orderOut(nil)
            self?.panel = nil
            self?.finishing = false
        }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { close() } }
        } else {
            close()
        }
    }
}

private final class CalibrationPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
