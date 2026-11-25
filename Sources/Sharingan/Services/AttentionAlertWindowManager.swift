import AppKit
import SwiftUI
import SharinganCore

/// Red click-through tint on every screen while the focus attention guard is
/// alerting. Same panel recipe as the focus lock, but `ignoresMouseEvents`, so
/// the user keeps working through it. Repeated shows only update the model.
@MainActor
final class AttentionAlertWindowManager: AttentionAlertPresenter {
    static let shared = AttentionAlertWindowManager()
    private let model = AttentionAlertModel()
    private var panels: [NSPanel] = []
    private var screenObserver: NSObjectProtocol?

    func showAttentionAlert(state: AttentionState, taskTitle: String?) {
        // The break overlay owns the screen; never tint over it.
        guard !BreakWindowManager.shared.isBlocking else { hideAttentionAlert(); return }
        model.state = state
        model.taskTitle = taskTitle
        guard panels.isEmpty else { return }
        buildPanels(fadeIn: true)
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.panels.isEmpty else { return }
                    self.tearDown(animated: false)
                    self.buildPanels(fadeIn: false)
                }
            }
        }
    }

    func hideAttentionAlert() {
        if let obs = screenObserver {
            NotificationCenter.default.removeObserver(obs)
            screenObserver = nil
        }
        guard !panels.isEmpty else { return }
        tearDown(animated: true)
    }

    private func buildPanels(fadeIn: Bool) {
        for screen in NSScreen.screens {
            let panel = AttentionPanel(contentRect: screen.frame,
                                       styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered, defer: false, screen: screen)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                        .stationary, .ignoresCycle]
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isMovable = false
            panel.ignoresMouseEvents = true
            let hosting = NSHostingView(rootView: AttentionAlertView(model: model))
            hosting.translatesAutoresizingMaskIntoConstraints = false
            panel.contentView = hosting
            panel.alphaValue = fadeIn ? 0 : 1
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        if fadeIn {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                for p in panels { p.animator().alphaValue = 1 }
            }
        }
    }

    private func tearDown(animated: Bool) {
        let old = panels
        panels.removeAll()
        guard animated else {
            for p in old { p.contentView = nil; p.orderOut(nil) }
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            for p in old { p.animator().alphaValue = 0 }
        }, completionHandler: {
            for p in old { p.contentView = nil; p.orderOut(nil) }
        })
    }
}

private final class AttentionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
