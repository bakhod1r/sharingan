import AppKit
import SwiftUI
import SharinganCore

/// App-icon artwork: the bare red Sharingan disc — the exact same
/// `MoveIrisView` the menu bar shows, full-bleed on a transparent canvas, so
/// the Dock icon and the menu bar icon are one and the same mark. `style`
/// follows the user's Sharingan-eye pick at runtime (the .icns on disk stays
/// the classic mark).
struct AppIconArtwork: View {
    var style: SharinganStyle = .classic
    var body: some View {
        ZStack {
            Color.clear
            MoveIrisView(diameter: 920, style: style)
                .shadow(color: .black.opacity(0.35), radius: 28, y: 12)
        }
        .frame(width: 1024, height: 1024)
    }
}

enum IconRenderer {
    /// Render the 1024×1024 app icon to a PNG file.
    @MainActor
    static func renderAppIcon(to path: String) {
        let renderer = ImageRenderer(content: AppIconArtwork().frame(width: 1024, height: 1024))
        renderer.scale = 1
        guard let cg = renderer.cgImage else {
            FileHandle.standardError.write(Data("app-icon render failed\n".utf8))
            return
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        try? rep.representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: path))
    }
}
