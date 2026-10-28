import AppKit
import SwiftUI
import SharinganCore

/// Keeps the Dock icon on the user's Sharingan style. The Dock tile no
/// longer spins with the menu bar mark: every spun frame set
/// `applicationIconImage`, a Dock round-trip that cost tens of percent CPU
/// at 12 fps. Only the menu bar animates now.
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
        NSApp.applicationIconImage = style == .classic ? nil : base
    }
}
