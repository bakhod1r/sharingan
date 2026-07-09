import AppKit
import SwiftUI
import BlinkCore

/// Premium app-icon artwork, rendered from the app's own Sharingan asset so the
/// icon and the in-app eye share one identity. Composition:
///   dark-glass squircle → blue pomodoro countdown ring → red Sharingan iris.
struct AppIconArtwork: View {
    var body: some View {
        ZStack {
            // Dark-glass squircle base (deep navy → near-black).
            RoundedRectangle(cornerRadius: 230, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.11, green: 0.14, blue: 0.22),
                            Color(red: 0.035, green: 0.05, blue: 0.10),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )

            // Soft top highlight — the "glass" sheen.
            RoundedRectangle(cornerRadius: 230, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.10), Color.clear],
                        startPoint: .top, endPoint: .center
                    )
                )
                .blendMode(.plusLighter)

            // Center vignette to focus the eye.
            RadialGradient(
                colors: [Color.clear, Color.black.opacity(0.35)],
                center: .center, startRadius: 240, endRadius: 640
            )

            // Blue countdown ring (pomodoro), open at the bottom, with glow.
            Circle()
                .trim(from: 0.0, to: 0.80)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.36, green: 0.52, blue: 1.0),
                            Color(red: 0.46, green: 0.40, blue: 1.0),
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 42, lineCap: .round)
                )
                .frame(width: 690, height: 690)
                .rotationEffect(.degrees(126))   // move the gap to bottom-center
                .shadow(color: Color(red: 0.34, green: 0.50, blue: 1.0).opacity(0.55), radius: 26)

            // Warm red glow behind the iris.
            Circle()
                .fill(Color(red: 0.80, green: 0.10, blue: 0.10).opacity(0.38))
                .frame(width: 520, height: 520)
                .blur(radius: 64)

            // The Sharingan iris — the app's actual vector eye artwork.
            MoveIrisView(diameter: 470)
                .shadow(color: .black.opacity(0.45), radius: 22, y: 8)
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
