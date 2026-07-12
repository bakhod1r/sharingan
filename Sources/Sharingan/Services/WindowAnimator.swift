import AppKit

/// Fades windows in with a subtle scale-up on show and fades them out on
/// dismiss, so panels stop popping into existence. Ordering/key calls happen
/// first and are never animated — only `alphaValue` and the frame move —
/// so focus behavior is untouched. Honors Reduce Motion (instant show/hide).
@MainActor
enum WindowAnimator {
    private static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Order the window front (key or not) with a 0.97→1 scale + fade-in.
    /// Use INSTEAD of a bare makeKeyAndOrderFront/orderFrontRegardless.
    static func present(_ window: NSWindow, makeKey: Bool = true) {
        if makeKey { window.makeKeyAndOrderFront(nil) }
        else { window.orderFrontRegardless() }
        guard !reduceMotion else { return }

        let frame = window.frame
        let inset = frame.insetBy(dx: frame.width * 0.015,
                                  dy: frame.height * 0.015)
        window.alphaValue = 0
        window.setFrame(inset, display: false)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            window.animator().setFrame(frame, display: true)
        }
    }

    /// Fade out, then hand back for orderOut/cleanup. Restores alpha so a
    /// reused window presents correctly next time.
    static func dismiss(_ window: NSWindow, completion: @escaping () -> Void) {
        guard !reduceMotion else { completion(); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: {
            completion()
            window.alphaValue = 1
        })
    }
}
