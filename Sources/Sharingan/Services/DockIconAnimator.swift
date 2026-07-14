import AppKit

/// Spins the Dock icon in step with the menu bar mark. The bundled app icon
/// IS the bare Sharingan disc (see IconRenderer), so rotating the whole
/// bitmap is exact. Frames are drawn only while the app is a `.regular`
/// activation-policy app — accessory mode has no Dock tile — and the shipped
/// artwork is restored the moment the spinner idles or the tile disappears.
@MainActor
final class DockIconAnimator {
    /// The artwork as shipped, captured before the first spun frame.
    private let base: NSImage? =
        Bundle.main.image(forResource: "AppIcon") ?? NSApp.applicationIconImage
    private var showingSpunFrame = false

    func apply(angle: Double, spinning: Bool) {
        guard let base else { return }
        guard spinning, NSApp.activationPolicy() == .regular else {
            if showingSpunFrame {
                NSApp.applicationIconImage = base
                showingSpunFrame = false
            }
            return
        }
        let side: CGFloat = 256
        let frame = NSImage(size: NSSize(width: side, height: side),
                            flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.translateBy(x: rect.midX, y: rect.midY)
            // Negative = visually clockwise in the y-up context, matching
            // the menu bar's tomoe direction.
            ctx.rotate(by: -angle * .pi / 180)
            base.draw(in: CGRect(x: -side / 2, y: -side / 2, width: side, height: side))
            return true
        }
        NSApp.applicationIconImage = frame
        showingSpunFrame = true
    }
}
