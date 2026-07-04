import SwiftUI
import AppKit
import BlinkCore

// MARK: - Asset cache

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

// MARK: - Almond eye shape

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

// MARK: - Tomoe shape

/// A comma-shaped tomoe (magatama): a round head with a curled tail.
/// One of three sits at 120° intervals around the pupil.
struct TomoeShape: Shape {
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

// MARK: - Sharingan iris

/// The red Sharingan iris: radial red gradient, black pupil, three rotating
/// tomoe, glossy highlight, soft inner shadow. Falls back to PNG if bundled.
struct SharinganIris: View {
    /// Iris diameter.
    var diameter: CGFloat
    /// Tomoe rotation angle (degrees) — driven externally for continuous spin.
    var spin: Double
    /// Which Sharingan artwork to show.
    var style: SharinganStyle = .classic

    var body: some View {
        if let img = SharinganAssets.image(style) {
            // Bundled artwork — overlay glossy highlight on top.
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .rotationEffect(.degrees(spin * 0.12))
                .frame(width: diameter, height: diameter)
                .overlay(glossHighlight)
                .overlay(innerShadow)
        } else {
            drawnIris
        }
    }

    /// Vector-drawn iris used when no PNG is bundled.
    private var drawnIris: some View {
        ZStack {
            // Red radial gradient base
            Circle()
                .fill(RadialGradient(
                    colors: [
                        Color(red: 0.95, green: 0.18, blue: 0.18),
                        Color(red: 0.78, green: 0.06, blue: 0.06),
                        Color(red: 0.52, green: 0.02, blue: 0.02),
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter * 0.55
                ))

            // Black ring around iris edge
            Circle()
                .stroke(Color.black.opacity(0.95), lineWidth: diameter * 0.06)

            // Three rotating tomoe
            ForEach(0..<3, id: \.self) { i in
                TomoeShape()
                    .fill(Color.black)
                    .frame(width: diameter * 0.32, height: diameter * 0.32)
                    .offset(y: -diameter * 0.30)
                    .rotationEffect(.degrees(Double(i) * 120 + spin))
            }

            // Black pupil
            Circle()
                .fill(Color.black)
                .frame(width: diameter * 0.24, height: diameter * 0.24)

            // Glossy highlight (upper-left)
            glossHighlight

            // Soft inner shadow (lower-right darkening)
            innerShadow
        }
        .frame(width: diameter, height: diameter)
    }

    /// Glossy specular highlight — a soft white blob in the upper-left.
    private var glossHighlight: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color.white.opacity(0.85), Color.white.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter * 0.18
                )
            )
            .frame(width: diameter * 0.35, height: diameter * 0.35)
            .offset(x: -diameter * 0.18, y: -diameter * 0.18)
            .blendMode(.screen)
            .allowsHitTesting(false)
    }

    /// Soft inner shadow — darkens the lower-right rim slightly for depth.
    private var innerShadow: some View {
        Circle()
            .stroke(Color.black.opacity(0.35), lineWidth: diameter * 0.04)
            .blur(radius: diameter * 0.03)
            .mask(
                Circle().fill(Color.white)
                    .overlay(Circle().fill(Color.black).frame(width: diameter * 0.92,
                                                               height: diameter * 0.92))
                    .asymmetricInset()
            )
            .frame(width: diameter, height: diameter)
            .allowsHitTesting(false)
    }
}

// MARK: - Single Sharingan eye

/// A single Sharingan eye: almond sclera, red iris, thick black outline,
/// red glow around the eye, blink animation, breathing scale, floating offset.
struct SharinganEye: View {
    /// Normalized look direction (-1…1 on each axis).
    var gaze: GazeDirection
    /// Tomoe rotation, degrees.
    var spin: Double
    /// Eye height; the almond is ~1.7× as wide.
    var size: CGFloat = 96
    /// Mirror horizontally (for the right eye).
    var mirrored: Bool = false
    /// Which Sharingan artwork to show as the iris.
    var style: SharinganStyle = .classic
    /// Eyelid openness 0…1 (1 = fully open).
    var openness: CGFloat = 1.0

    @State private var breathe: Bool = false
    @State private var float: Bool = false

    private let bgColor = Color(red: 0.05, green: 0.05, blue: 0.05)

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
                // Iris that travels across the sclera toward gaze direction.
                SharinganIris(diameter: size * 0.40, spin: spin, style: style)
                    .offset(x: -w * 0.06 + CGFloat(gaze.dx) * size * 0.42,
                            y: CGFloat(gaze.dy) * size * 0.22)
            }
            .clipShape(AlmondEyeShape())

            // Crisp dark rim.
            AlmondEyeShape()
                .stroke(Color.black, lineWidth: size * 0.05)

            // Eyelid blink overlay — scales vertically from center.
            AlmondEyeShape()
                .fill(Color(red: 0.05, green: 0.05, blue: 0.05))
                .scaleEffect(y: 1.0 - openness, anchor: .center)
                .opacity(openness < 1.0 ? 1 : 0)
        }
        .frame(width: w, height: size)
        .scaleEffect(x: mirrored ? -1 : 1, y: 1)
        // Red glow around the eye
        .shadow(color: Color(red: 0.85, green: 0.10, blue: 0.10).opacity(0.55),
                radius: size * 0.20, x: 0, y: 0)
        // Breathing animation
        .scaleEffect(breathe ? 1.02 : 0.98)
        // Floating offset
        .offset(y: float ? -size * 0.04 : size * 0.04)
        .animation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true),
                   value: breathe)
        .animation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true),
                   value: float)
        .onAppear {
            breathe = true
            float = true
        }
    }
}

private extension View {
    /// Asymmetric inset helper for the inner shadow mask.
    func asymmetricInset() -> some View {
        self
    }
}

// MARK: - Sharingan pair (break exercise guide)

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
                SharinganEye(gaze: live, spin: t * 70, size: eyeSize, style: style)
                SharinganEye(gaze: live, spin: t * 70, size: eyeSize,
                             mirrored: true, style: style)
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

// MARK: - Full Sharingan view (standalone showcase)

/// The full Sharingan showcase view: near-black background, two large eyes,
/// automatic blink every 4–6 seconds, continuous tomoe rotation, breathing
/// and floating animations. Responsive — eye size scales to container.
struct SharinganView: View {
    var style: SharinganStyle = .classic
    var eyeSize: CGFloat = 120
    @State private var openness: CGFloat = 1.0
    @State private var nextBlink: Double = 4.0

    private let bgColor = Color(red: 0.05, green: 0.05, blue: 0.05)

    var body: some View {
        ZStack {
            // Near-black background (#0D0D0D)
            bgColor.ignoresSafeArea()

            // Eyes centered horizontally
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                HStack(spacing: eyeSize * 0.35) {
                    SharinganEye(gaze: .center,
                                 spin: t * 60,
                                 size: eyeSize,
                                 style: style,
                                 openness: openness)
                    SharinganEye(gaze: .center,
                                 spin: t * 60,
                                 size: eyeSize,
                                 mirrored: true,
                                 style: style,
                                 openness: openness)
                }
            }
        }
        .onAppear { scheduleBlink() }
    }

    /// Schedule a blink at a random interval between 4 and 6 seconds.
    private func scheduleBlink() {
        let delay = Double.random(in: 4.0...6.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            blink()
        }
    }

    /// One blink cycle: close (0.15s) → open (0.15s) → schedule next.
    private func blink() {
        withAnimation(.easeInOut(duration: 0.15)) { openness = 0.0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.15)) { openness = 1.0 }
            DispatchQueue.main.mainAsyncAfterSafe(deadline: .now() + 0.2) {
                scheduleBlink()
            }
        }
    }
}

private extension DispatchQueue {
    /// Helper to avoid repeating the same name; semantically identical.
    func mainAsyncAfterSafe(deadline: DispatchTime, execute: @escaping () -> Void) {
        asyncAfter(deadline: deadline, execute: execute)
    }
}