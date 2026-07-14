import AppKit
import SwiftUI
import SharinganCore

/// Spins the Dock icon in step with the menu bar mark. The bundled app icon
/// IS the bare Sharingan disc (see IconRenderer), so rotating the whole
/// bitmap is exact. Frames are drawn only while the app is a `.regular`
/// activation-policy app — accessory mode has no Dock tile — and the base
/// artwork is restored the moment the spinner idles or the tile disappears.
///
/// The base artwork follows the user's Sharingan style (`syncStyle`):
/// `.classic` is the shipped .icns; any other style re-renders the same
/// `AppIconArtwork` the icon ships as, at the picked style. The .icns on
/// disk stays classic — Finder keeps the shipped mark.
@MainActor
final class DockIconAnimator {
    /// The artwork as shipped, captured before the first spun frame.
    private let shipped: NSImage? =
        Bundle.main.image(forResource: "AppIcon") ?? NSApp.applicationIconImage
    /// What the Dock shows at rest — shipped art, or the styled re-render.
    private var base: NSImage?
    private var baseStyle: SharinganStyle = .classic
    private var showingSpunFrame = false

    init() { base = shipped }

    /// Re-renders the Dock artwork when the Sharingan style changes (no-op
    /// otherwise). A failed render keeps the shipped art rather than a blank
    /// tile.
    func syncStyle(_ style: SharinganStyle) {
        guard style != baseStyle else { return }
        baseStyle = style
        if style == .classic {
            base = shipped
        } else {
            let renderer = ImageRenderer(content:
                AppIconArtwork(style: style).frame(width: 1024, height: 1024))
            renderer.scale = 0.5 // 512px — plenty for the Dock tile
            base = renderer.cgImage.map {
                NSImage(cgImage: $0, size: NSSize(width: 512, height: 512))
            } ?? shipped
        }
        // Swap the resting tile now; a running spinner overwrites it with
        // rotated frames of the new base on its next tick anyway.
        if !showingSpunFrame {
            NSApp.applicationIconImage = style == .classic ? nil : base
        }
    }

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
