import AppKit
import SwiftUI
import SharinganCore

@MainActor
final class FocusLockWindowManager: FocusLockPresenter {
    static let shared = FocusLockWindowManager()
    var onStopSession: (() -> Void)?
    private var panels: [NSPanel] = []
    private var screenObserver: NSObjectProtocol?
    private var current: (lock: FocusLock, backTarget: BlockedApp?)?

    @discardableResult
    func showLock(_ lock: FocusLock, backTarget: BlockedApp?) -> Bool {
        guard !BreakWindowManager.shared.isBlocking, !NSScreen.screens.isEmpty else { return false }
        current = (lock, backTarget)
        let wasShowing = !panels.isEmpty
        tearDown(animated: false)
        for screen in NSScreen.screens {
            let panel = FocusLockPanel(contentRect: screen.frame,
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
            let view = FocusLockView(
                lock: lock, backTarget: backTarget,
                onBack: { Self.open(backTarget) },
                onSnooze: { FocusLockService.shared.snooze() },
                onStop: { [weak self] in self?.onStopSession?() })
            let hosting = FocusLockHostingView(rootView: view)
            hosting.translatesAutoresizingMaskIntoConstraints = false
            panel.contentView = hosting
            panel.alphaValue = wasShowing ? 1 : 0
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        if !wasShowing {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                for p in panels { p.animator().alphaValue = 1 }
            }
        }
        NotchWindowManager.shared.setBreakOverlay(true)
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let c = self.current else { return }
                    _ = self.showLock(c.lock, backTarget: c.backTarget)
                }
            }
        }
        return true
    }

    func hideLock() {
        if let obs = screenObserver {
            NotificationCenter.default.removeObserver(obs)
            screenObserver = nil
        }
        current = nil
        guard !panels.isEmpty else { return }
        // A break overlay owns the notch now; don't stand it back up under it.
        if !BreakWindowManager.shared.isBlocking {
            NotchWindowManager.shared.setBreakOverlay(false)
        }
        tearDown(animated: true)
    }

    private func tearDown(animated: Bool) {
        let old = panels
        panels.removeAll()
        guard animated else {
            for p in old { p.contentView = nil; p.orderOut(nil) }
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            for p in old { p.animator().alphaValue = 0 }
        }, completionHandler: {
            for p in old { p.contentView = nil; p.orderOut(nil) }
        })
    }

    private static func open(_ app: BlockedApp?) {
        guard let app,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID)
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
}

private final class FocusLockPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class FocusLockHostingView<Content: View>: NSHostingView<Content> {
    // The panel never becomes key; without this the first click is swallowed.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
