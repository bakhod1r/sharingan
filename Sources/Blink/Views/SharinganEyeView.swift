import SwiftUI
import AppKit
import BlinkCore

/// Loads and caches the bundled Sharingan iris PNGs (chosen in Settings).
enum SharinganAssets {
    private static var cache: [SharinganStyle: NSImage] = [:]

    static func image(_ style: SharinganStyle) -> NSImage? {
        if let img = cache[style] { return img }
        let url = Bundle.module.url(forResource: style.fileName, withExtension: "png",
                                    subdirectory: "Sharingan")
            ?? Bundle.module.url(forResource: style.fileName, withExtension: "png")
        guard let url, let img = NSImage(contentsOf: url) else { return nil }
        cache[style] = img
        return img
    }
}

/// A sharp, tilted almond eye — drawn as the LEFT eye: the outer corner sits at
/// `minX` (high) and the inner/nasal corner at `maxX` (low), so a mirrored pair
/// slants down toward the centre, matching the reference Sharingan artwork.
struct AlmondEyeShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        let outer = CGPoint(x: r.minX, y: r.minY + h * 0.42)   // outer corner, high
        let inner = CGPoint(x: r.maxX, y: r.minY + h * 0.60)   // nasal corner, low
        p.move(to: outer)
        // Bold upper lid: tall arch over the iris — sharp, pointed corners.
        p.addQuadCurve(to: inner, control: CGPoint(x: r.minX + w * 0.34, y: r.minY - h * 0.30))
        // Lower lid: shallow belly so the almond reads sharp, not round.
        p.addQuadCurve(to: outer, control: CGPoint(x: r.minX + w * 0.50, y: r.maxY + h * 0.10))
        p.closeSubpath()
        return p
    }
}

/// A single Sharingan eye drawn in SwiftUI — almond sclera, red iris, black
/// pupil, three rotating tomoe, on a dark eyelid surround (matches the video).
/// The iris translates within the almond to "look" toward `gaze`.
struct SharinganEyeView: View {
    /// Normalized look direction (-1…1 on each axis).
    var gaze: GazeDirection
    /// Tomoe rotation, degrees.
    var spin: Double
    /// Eye height; the almond is ~2× as wide.
    var size: CGFloat = 96
    /// Mirror horizontally (for the right eye).
    var mirrored: Bool = false
    /// Which Sharingan artwork to show as the iris.
    var style: SharinganStyle = .classic

    var body: some View {
        let w = size * 1.7
        ZStack {
            // Bold black eyelid surround, so the eye reads on any background.
            AlmondEyeShape()
                .fill(Color.black)
                .blur(radius: size * 0.05)
                .scaleEffect(1.14)

            // Sclera + iris, clipped to the almond. Pure white interior.
            ZStack {
                AlmondEyeShape().fill(Color.white)
                // Small iris that travels across the sclera — the wider swing
                // makes the exercise's look-direction unmistakable.
                iris
                    .offset(x: -w * 0.06 + CGFloat(gaze.dx) * size * 0.42,
                            y:  CGFloat(gaze.dy) * size * 0.22)
            }
            .clipShape(AlmondEyeShape())

            // Crisp dark rim.
            AlmondEyeShape()
                .stroke(Color.black, lineWidth: size * 0.05)
        }
        .frame(width: w, height: size)
        .scaleEffect(x: mirrored ? -1 : 1, y: 1)
        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
    }

    @ViewBuilder
    private var iris: some View {
        // Small iris — a compact Sharingan dot with plenty of sclera around it.
        let d = size * 0.40
        if let img = SharinganAssets.image(style) {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .rotationEffect(.degrees(spin * 0.12))
                .frame(width: d, height: d)
        } else {
            drawnIris(d)
        }
    }

    /// Vector fallback if the PNG can't be loaded.
    private func drawnIris(_ d: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.90, green: 0.14, blue: 0.14),
                                              Color(red: 0.52, green: 0.02, blue: 0.02)],
                                     center: .center, startRadius: 1, endRadius: d * 0.55))
            Circle().stroke(Color.black.opacity(0.95), lineWidth: d * 0.06)
            ForEach(0..<3, id: \.self) { i in
                Tomoe()
                    .fill(Color.black)
                    .frame(width: d * 0.32, height: d * 0.32)
                    .offset(y: -d * 0.30)
                    .rotationEffect(.degrees(Double(i) * 120 + spin))
            }
            Circle().fill(Color.black).frame(width: d * 0.24, height: d * 0.24)
            Circle().fill(Color.white.opacity(0.8))
                .frame(width: d * 0.09, height: d * 0.09)
                .offset(x: -d * 0.11, y: -d * 0.11)
        }
        .frame(width: d, height: d)
    }
}

/// A comma-shaped tomoe (magatama): a round head with a curled tail.
struct Tomoe: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let headR = w * 0.30
        let cx = rect.midX
        // Head
        p.addEllipse(in: CGRect(x: cx - headR, y: rect.minY,
                                width: headR * 2, height: headR * 2))
        // Tail curling down and around
        p.move(to: CGPoint(x: cx + headR, y: rect.minY + headR))
        p.addQuadCurve(to: CGPoint(x: cx, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.midY))
        p.addQuadCurve(to: CGPoint(x: cx - headR, y: rect.minY + headR),
                       control: CGPoint(x: cx - headR * 0.4, y: rect.midY))
        p.closeSubpath()
        return p
    }
}

/// A pair of Sharingan eyes used as the break-time eye-movement guide.
///
/// For fixed directions (left/right/up/down/diagonals) the irises hold the
/// target offset; for `circle_cw`, `circle_ccw` and `figure8` steps they trace
/// the path continuously, matching classic eye-exercise charts one-to-one.
struct SharinganEyePair: View {
    /// The exercise step's raw direction (drives path motions).
    var direction: String
    /// Target gaze for fixed directions.
    var gaze: GazeDirection
    var eyeSize: CGFloat = 92
    /// Which Sharingan artwork to render.
    var style: SharinganStyle = .classic

    private var isPath: Bool {
        direction == "circle_cw" || direction == "circle_ccw" || direction == "figure8"
    }

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let off = offset(at: t)
            let live = GazeDirection(dx: off.x, dy: off.y)
            HStack(spacing: eyeSize * 0.35) {
                SharinganEyeView(gaze: live, spin: t * 70, size: eyeSize, style: style)
                SharinganEyeView(gaze: live, spin: t * 70, size: eyeSize, mirrored: true, style: style)
            }
            .animation(isPath ? nil : .easeInOut(duration: 0.5), value: gaze)
        }
    }

    /// A short human cue for the current motion (used by the break screen caption).
    var motionCaption: String {
        switch direction {
        case "circle_cw":  return "Roll clockwise"
        case "circle_ccw": return "Roll counter-clockwise"
        case "figure8":    return "Trace a figure 8"
        default:           return gaze.magnitude < 0.05 ? "Look straight ahead"
                                                        : "Look \(gaze.label)"
        }
    }

    /// Iris offset at time `t`. Fixed directions ignore `t`.
    private func offset(at t: TimeInterval) -> (x: Double, y: Double) {
        switch direction {
        case "circle_cw":  let a = t * 1.7;  return (cos(a), sin(a))
        case "circle_ccw": let a = -t * 1.7; return (cos(a), sin(a))
        case "figure8":    let a = t * 1.7;  return (sin(a), sin(2 * a) / 2)
        default:           return (gaze.dx, gaze.dy)
        }
    }

}
