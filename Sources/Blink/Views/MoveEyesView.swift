import SwiftUI
import AppKit
import BlinkCore

// MARK: - Shapes (ported from the MoveEyes app — vector-only, no PNG assets)

/// Flat almond eye outline drawn as the LEFT eye: sharp outer tip at minX
/// (high), inner/nasal tip at maxX (low). `mirrored` flips for the right eye.
struct MoveEyeShape: Shape {
    var mirrored = false

    static let outerTip = CGPoint(x: 0.00, y: 0.06)
    static let innerTip = CGPoint(x: 1.00, y: 0.94)

    func path(in rect: CGRect) -> Path {
        var p = upperLidPath(in: rect)
        p.addCurve(
            to: pt(Self.outerTip, rect),
            control1: pt(CGPoint(x: 0.52, y: 1.08), rect),
            control2: pt(CGPoint(x: 0.07, y: 0.86), rect)
        )
        p.closeSubpath()
        return p
    }

    func upperLidPath(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: pt(Self.outerTip, rect))
        p.addCurve(
            to: pt(Self.innerTip, rect),
            control1: pt(CGPoint(x: 0.32, y: -0.10), rect),
            control2: pt(CGPoint(x: 0.76, y: 0.20), rect)
        )
        return p
    }

    func lowerLidPath(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: pt(Self.innerTip, rect))
        p.addCurve(
            to: pt(Self.outerTip, rect),
            control1: pt(CGPoint(x: 0.52, y: 1.08), rect),
            control2: pt(CGPoint(x: 0.07, y: 0.86), rect)
        )
        return p
    }

    private func pt(_ u: CGPoint, _ rect: CGRect) -> CGPoint {
        let x = mirrored ? 1 - u.x : u.x
        return CGPoint(x: rect.minX + x * rect.width, y: rect.minY + u.y * rect.height)
    }
}

/// Partial stroke of an eyelid curve, used for the gray edge highlights.
struct MoveEyelidStroke: Shape {
    var shape: MoveEyeShape
    var lineWidth: CGFloat
    var lower = false
    var trimFrom: CGFloat = 0
    var trimTo: CGFloat = 1

    func path(in rect: CGRect) -> Path {
        (lower ? shape.lowerLidPath(in: rect) : shape.upperLidPath(in: rect))
            .trimmedPath(from: trimFrom, to: trimTo)
            .strokedPath(StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }
}

/// Comma tail that tapers along the tomoe ring.
struct MoveTomoeTail: Shape {
    var ringRadius: CGFloat
    var headAngle: Angle
    var sweep: Angle
    var startWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let n = 26
        var outer: [CGPoint] = []
        var inner: [CGPoint] = []
        for i in 0...n {
            let t = CGFloat(i) / CGFloat(n)
            let a = headAngle.radians + sweep.radians * Double(t)
            let w = startWidth * (1 - t) * (1 - t)
            outer.append(point(at: a, radius: ringRadius + w / 2, center: c))
            inner.append(point(at: a, radius: ringRadius - w / 2, center: c))
        }
        var p = Path()
        p.move(to: outer[0])
        for pt in outer.dropFirst() { p.addLine(to: pt) }
        for pt in inner.reversed() { p.addLine(to: pt) }
        p.closeSubpath()
        return p
    }

    private func point(at angle: Double, radius: CGFloat, center: CGPoint) -> CGPoint {
        CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }
}

// MARK: - Iris pattern shapes (all vector — original geometric designs)

/// N curved pinwheel blades radiating from the pupil.
struct MovePinwheelShape: Shape {
    var blades = 3
    /// 0…1 — how much each blade leans sideways (curvature).
    var lean: CGFloat = 0.55
    /// Blade half-width at the root, as a fraction of radius.
    var rootWidth: CGFloat = 0.22

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let R = min(rect.width, rect.height) / 2
        var p = Path()
        for i in 0..<blades {
            let base = Double(i) * 2 * .pi / Double(blades)
            let tip = base + Double(lean)
            let tipPt = CGPoint(x: c.x + R * cos(tip), y: c.y + R * sin(tip))
            let a1 = base - Double(rootWidth)
            let a2 = base + Double(rootWidth)
            let r0 = R * 0.16
            let p1 = CGPoint(x: c.x + r0 * cos(a1), y: c.y + r0 * sin(a1))
            let p2 = CGPoint(x: c.x + r0 * cos(a2), y: c.y + r0 * sin(a2))
            let c1 = CGPoint(x: c.x + R * 0.62 * cos(base - 0.12), y: c.y + R * 0.62 * sin(base - 0.12))
            let c2 = CGPoint(x: c.x + R * 0.55 * cos(tip + 0.38), y: c.y + R * 0.55 * sin(tip + 0.38))
            p.move(to: p1)
            p.addQuadCurve(to: tipPt, control: c1)
            p.addQuadCurve(to: p2, control: c2)
            p.closeSubpath()
        }
        return p
    }
}

/// N-arm spiral of tapering arcs (vortex look).
struct MoveSpiralShape: Shape {
    var arms = 3
    var turns: Double = 0.9

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let R = min(rect.width, rect.height) / 2
        var p = Path()
        let steps = 40
        for arm in 0..<arms {
            let phase = Double(arm) * 2 * .pi / Double(arms)
            var outer: [CGPoint] = []
            var inner: [CGPoint] = []
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let a = phase + t * turns * 2 * .pi
                let radius = R * (0.16 + 0.84 * t)
                let w = R * 0.10 * (1 - t)
                outer.append(CGPoint(x: c.x + (radius + w) * cos(a), y: c.y + (radius + w) * sin(a)))
                inner.append(CGPoint(x: c.x + max(radius - w, 0) * cos(a), y: c.y + max(radius - w, 0) * sin(a)))
            }
            p.move(to: outer[0])
            for pt in outer.dropFirst() { p.addLine(to: pt) }
            for pt in inner.reversed() { p.addLine(to: pt) }
            p.closeSubpath()
        }
        return p
    }
}

/// A pointed star polygon.
struct MoveStarShape: Shape {
    var points = 6
    var innerRatio: CGFloat = 0.45

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let R = min(rect.width, rect.height) / 2
        let r = R * innerRatio
        var p = Path()
        for i in 0..<(points * 2) {
            let a = Double(i) * .pi / Double(points) - .pi / 2
            let radius = i.isMultiple(of: 2) ? R : r
            let pt = CGPoint(x: c.x + radius * cos(a), y: c.y + radius * sin(a))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }
}

/// A band along the ring that tapers at both ends (crescent).
struct MoveArcBandShape: Shape {
    var ringRadius: CGFloat      // fraction handled by caller via frame
    var centerAngle: Angle
    var sweep: Angle
    var maxWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let n = 26
        var outer: [CGPoint] = []
        var inner: [CGPoint] = []
        let start = centerAngle.radians - sweep.radians / 2
        for i in 0...n {
            let t = CGFloat(i) / CGFloat(n)
            let a = start + sweep.radians * Double(t)
            let w = maxWidth * sin(.pi * t)
            outer.append(CGPoint(x: c.x + (ringRadius + w / 2) * cos(a), y: c.y + (ringRadius + w / 2) * sin(a)))
            inner.append(CGPoint(x: c.x + (ringRadius - w / 2) * cos(a), y: c.y + (ringRadius - w / 2) * sin(a)))
        }
        var p = Path()
        p.move(to: outer[0])
        for pt in outer.dropFirst() { p.addLine(to: pt) }
        for pt in inner.reversed() { p.addLine(to: pt) }
        p.closeSubpath()
        return p
    }
}

/// A rounded rosette: N petals as overlapping circles around the pupil.
struct MoveRosetteShape: Shape {
    var petals = 3
    var petalRadius: CGFloat = 0.34   // fraction of radius
    var orbit: CGFloat = 0.52         // petal center distance, fraction of radius

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let R = min(rect.width, rect.height) / 2
        var p = Path()
        for i in 0..<petals {
            let a = Double(i) * 2 * .pi / Double(petals) - .pi / 2
            let pc = CGPoint(x: c.x + R * orbit * cos(a), y: c.y + R * orbit * sin(a))
            let pr = R * petalRadius
            p.addEllipse(in: CGRect(x: pc.x - pr, y: pc.y - pr, width: pr * 2, height: pr * 2))
        }
        return p
    }
}

// MARK: - Iris

/// Red vector iris: radial gradient base, pupil, and a style-specific black
/// pattern. All styles are drawn in code — no PNG assets.
struct MoveIrisView: View {
    var diameter: CGFloat
    var spin: Double = 0
    var style: SharinganStyle = .classic

    var body: some View {
        let r = diameter / 2
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: Color(red: 0.58, green: 0.02, blue: 0.03), location: 0.0),
                            .init(color: Color(red: 0.65, green: 0.05, blue: 0.05), location: 0.45),
                            .init(color: Color(red: 0.71, green: 0.08, blue: 0.07), location: 0.65),
                            .init(color: Color(red: 0.52, green: 0.02, blue: 0.02), location: 0.88),
                            .init(color: Color(red: 0.34, green: 0.00, blue: 0.01), location: 1.0),
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: r
                    )
                )
            Circle()
                .stroke(Color(red: 0.08, green: 0.0, blue: 0.0).opacity(0.9), lineWidth: 0.05 * r)
                .padding(0.02 * r)

            pattern(r: r)
                .rotationEffect(.degrees(spin))

            Circle()
                .fill(Color.black)
                .frame(width: 0.26 * r, height: 0.26 * r)
        }
        .frame(width: diameter, height: diameter)
    }

    /// The spinning black pattern for each style.
    @ViewBuilder
    private func pattern(r: CGFloat) -> some View {
        let ringR = 0.52 * r
        switch style {
        case .classic:
            ZStack {
                Circle()
                    .stroke(Color(red: 0.22, green: 0.0, blue: 0.01).opacity(0.85), lineWidth: 0.035 * r)
                    .frame(width: ringR * 2, height: ringR * 2)
                ForEach(0..<3, id: \.self) { i in
                    let head = Angle(degrees: -80 + Double(i) * 120)
                    MoveTomoeTail(
                        ringRadius: ringR,
                        headAngle: head,
                        sweep: .degrees(-60),
                        startWidth: 0.20 * r
                    )
                    .fill(Color.black)
                    Circle()
                        .fill(Color.black)
                        .frame(width: 0.28 * r, height: 0.28 * r)
                        .offset(x: ringR * cos(head.radians), y: ringR * sin(head.radians))
                }
            }
        case .mangekyou:
            MovePinwheelShape(blades: 3, lean: 0.62, rootWidth: 0.26)
                .fill(Color.black)
                .frame(width: 1.72 * r, height: 1.72 * r)
        case .mangekyouKamui:
            MoveSpiralShape(arms: 3, turns: 0.85)
                .fill(Color.black)
                .frame(width: 1.76 * r, height: 1.76 * r)
        case .mangekyouEternal:
            ZStack {
                MovePinwheelShape(blades: 3, lean: 0.55, rootWidth: 0.22)
                    .fill(Color.black)
                    .frame(width: 1.72 * r, height: 1.72 * r)
                MovePinwheelShape(blades: 3, lean: 0.55, rootWidth: 0.22)
                    .fill(Color.black)
                    .frame(width: 1.30 * r, height: 1.30 * r)
                    .rotationEffect(.degrees(60))
            }
        case .itachi:
            MoveRosetteShape(petals: 3, petalRadius: 0.36, orbit: 0.50)
                .fill(Color.black)
                .frame(width: 1.9 * r, height: 1.9 * r)
        case .sixStar:
            MoveStarShape(points: 6, innerRatio: 0.42)
                .fill(Color.black)
                .frame(width: 1.5 * r, height: 1.5 * r)
        case .blade:
            MovePinwheelShape(blades: 3, lean: 0.18, rootWidth: 0.14)
                .fill(Color.black)
                .frame(width: 1.8 * r, height: 1.8 * r)
        case .orbit:
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Ellipse()
                        .stroke(Color.black, lineWidth: 0.07 * r)
                        .frame(width: 1.7 * r, height: 0.72 * r)
                        .rotationEffect(.degrees(Double(i) * 60))
                }
            }
        case .crescent:
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    MoveArcBandShape(
                        ringRadius: ringR,
                        centerAngle: .degrees(-90 + Double(i) * 120),
                        sweep: .degrees(120),
                        maxWidth: 0.30 * r
                    )
                    .fill(Color.black)
                }
            }
        case .fourBlade:
            MovePinwheelShape(blades: 4, lean: 0.55, rootWidth: 0.20)
                .fill(Color.black)
                .frame(width: 1.72 * r, height: 1.72 * r)
        }
    }
}

// MARK: - Single eye

/// One MoveEyes-style eye. `gaze` is a normalized look direction (−1…1 per
/// axis); the iris travels inside the sclera and clips behind the lids.
/// Mirroring happens inside the shape, so gaze applies unflipped to both eyes.
struct MoveEyeView: View {
    var gaze: GazeDirection
    var spin: Double = 0
    /// Eye height; the almond is ~2.1× as wide.
    var size: CGFloat = 96
    var mirrored: Bool = false
    var style: SharinganStyle = .classic

    var body: some View {
        let h = size
        let w = size * 2.1
        let sw = 0.90 * w
        let sh = 0.96 * h
        let scleraDX = (mirrored ? -1 : 1) * (w - sw) / 2
        let irisD = 0.52 * sh
        let shape = MoveEyeShape(mirrored: mirrored)
        let off = CGPoint(x: CGFloat(gaze.dx) * 0.30 * w, y: CGFloat(gaze.dy) * 0.34 * h)

        ZStack {
            // subtle gray edge highlights peeking out from behind the black
            MoveEyelidStroke(shape: shape, lineWidth: 0.14 * h, trimTo: 0.62)
                .fill(Color(red: 0.55, green: 0.57, blue: 0.59))
                .offset(y: -0.048 * h)
            MoveEyelidStroke(shape: shape, lineWidth: 0.035 * h, lower: true, trimFrom: 0.22, trimTo: 0.78)
                .fill(Color(red: 0.26, green: 0.28, blue: 0.30))
                .offset(y: 0.018 * h)

            // black lid base: full shape + thicker upper lid line
            shape.fill(Color.black)
            MoveEyelidStroke(shape: shape, lineWidth: 0.10 * h)
                .fill(Color.black)
                .offset(y: -0.028 * h)

            // sclera + iris, clipped to the (slightly inset) almond
            ZStack {
                shape.fill(
                    LinearGradient(
                        colors: [Color.white, Color(red: 0.93, green: 0.91, blue: 0.91)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 0.95, green: 0.68, blue: 0.70).opacity(0.50),
                                    Color(red: 0.95, green: 0.74, blue: 0.76).opacity(0.0),
                                ],
                                center: .center,
                                startRadius: irisD * 0.44,
                                endRadius: irisD * 0.88
                            )
                        )
                        .frame(width: irisD * 1.6, height: irisD * 1.6)
                    MoveIrisView(diameter: irisD, spin: spin, style: style)
                }
                .offset(
                    x: (mirrored ? -1 : 1) * 0.025 * sw + off.x,
                    y: 0.08 * sh + off.y
                )
            }
            .frame(width: sw, height: sh)
            .clipShape(shape)
            .offset(x: scleraDX, y: -0.047 * h)
        }
        .frame(width: w, height: size)
    }
}

// MARK: - Pair (break-screen exercise guide)

/// A pair of MoveEyes eyes used as the break-time eye-movement guide.
/// Fixed directions hold the target gaze; `circle_cw`, `circle_ccw` and
/// `figure8` trace the path continuously.
struct MoveEyePair: View {
    var direction: String
    var gaze: GazeDirection
    var eyeSize: CGFloat = 92
    var style: SharinganStyle = .classic

    private var isPath: Bool {
        direction == "circle_cw" || direction == "circle_ccw" || direction == "figure8"
    }

    @State private var spinStart: TimeInterval = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let spinDuration: Double = 1.6
    private let spinTurns: Double = 3.0

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let off = offset(at: t)
            let live = GazeDirection(dx: off.x, dy: off.y)
            let s = activationSpin(at: t)
            HStack(spacing: eyeSize * 0.42) {
                MoveEyeView(gaze: live, spin: s, size: eyeSize, style: style)
                MoveEyeView(gaze: live, spin: s, size: eyeSize, mirrored: true, style: style)
            }
            .animation(isPath ? nil : .easeInOut(duration: 0.5), value: gaze)
        }
        .onAppear { spinStart = Date().timeIntervalSinceReferenceDate }
        .onChange(of: direction) { _ in
            spinStart = Date().timeIntervalSinceReferenceDate
        }
    }

    /// Activation burst: tomoe accelerate, whirl and settle (smootherstep).
    private func activationSpin(at t: TimeInterval) -> Double {
        if reduceMotion { return 0 }
        let u = min(max((t - spinStart) / spinDuration, 0), 1)
        let eased = u * u * u * (u * (u * 6 - 15) + 10)
        return spinTurns * 360 * eased
    }

    private func offset(at t: TimeInterval) -> (x: Double, y: Double) {
        switch direction {
        case "circle_cw":  let a = t * 1.7;  return (cos(a), sin(a))
        case "circle_ccw": let a = -t * 1.7; return (cos(a), sin(a))
        case "figure8":    let a = t * 1.7;  return (sin(a), sin(2 * a) / 2)
        default:           return (gaze.dx, gaze.dy)
        }
    }
}
