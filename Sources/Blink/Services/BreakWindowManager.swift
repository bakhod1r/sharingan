import AppKit
import SwiftUI
import BlinkCore

@MainActor
final class BreakWindowManager: BreakPresenter {
    static let shared = BreakWindowManager()
    private var panels: [NSPanel] = []
    private(set) var isBlocking = false

    func presentBreak(timer: PomodoroTimer,
                      onTapSkip: @escaping () -> Void) {
        guard !isBlocking else { return }
        isBlocking = true
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
                                 })
                .environmentObject(timer)
            let hosting = NSHostingView(rootView: view)
            hosting.translatesAutoresizingMaskIntoConstraints = false
            panel.contentView = hosting
            panel.orderFrontRegardless()
            panels.append(panel)
        }
    }

    func dismissAll() {
        for p in panels {
            p.contentView = nil
            p.orderOut(nil)
        }
        panels.removeAll()
        isBlocking = false
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