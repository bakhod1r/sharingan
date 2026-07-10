import AppKit
import SwiftUI
import BlinkCore

/// Premium app-icon artwork, rendered from the app's own Sharingan artwork so
/// the icon and the in-app eye share one identity. Composition:
///   dark-graphite squircle → soft red aura → almond eye with attached lid
///   outline → big centered Sharingan iris (the app's `MoveIrisView`).
/// The lid is a stroke of the almond itself, so nothing floats detached from
/// the eye the way the old grey accent arcs did.
struct AppIconArtwork: View {
    private let eyeSize = CGSize(width: 780, height: 420)

    var body: some View {
        ZStack {
            // Dark-graphite squircle base.
            RoundedRectangle(cornerRadius: 230, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.14, green: 0.15, blue: 0.18),
                            Color(red: 0.04, green: 0.04, blue: 0.06),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )

            // Soft top highlight — the "glass" sheen.
            RoundedRectangle(cornerRadius: 230, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.09), Color.clear],
                        startPoint: .top, endPoint: .center
                    )
                )
                .blendMode(.plusLighter)

            // Center vignette to focus the eye.
            RadialGradient(
                colors: [Color.clear, Color.black.opacity(0.32)],
                center: .center, startRadius: 260, endRadius: 660
            )

            // Warm red aura behind the eye.
            Ellipse()
                .fill(Color(red: 0.75, green: 0.08, blue: 0.09).opacity(0.32))
                .frame(width: 760, height: 460)
                .blur(radius: 80)

            eye.shadow(color: .black.opacity(0.45), radius: 24, y: 10)
        }
        .frame(width: 1024, height: 1024)
    }

    /// Almond eye: white sclera, big centered Sharingan iris clipped by the
    /// lids, and a black lid outline stroked along the almond itself.
    private var eye: some View {
        let shape = AlmondEyeShape()
        let irisD = eyeSize.height * 0.82
        return ZStack {
            // Sclera.
            shape.fill(
                LinearGradient(
                    colors: [Color.white, Color(red: 0.91, green: 0.89, blue: 0.89)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            // Pink glow around the iris + the iris itself, clipped by the lids.
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.95, green: 0.68, blue: 0.70).opacity(0.55),
                                Color(red: 0.95, green: 0.74, blue: 0.76).opacity(0.0),
                            ],
                            center: .center,
                            startRadius: irisD * 0.42,
                            endRadius: irisD * 0.85
                        )
                    )
                    .frame(width: irisD * 1.7, height: irisD * 1.7)
                MoveIrisView(diameter: irisD)
            }
            .clipShape(shape)
            // Lid outline hugging the almond — no detached arcs.
            shape.stroke(Color(red: 0.07, green: 0.07, blue: 0.09),
                         style: StrokeStyle(lineWidth: 30, lineCap: .round, lineJoin: .round))
        }
        .frame(width: eyeSize.width, height: eyeSize.height)
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
