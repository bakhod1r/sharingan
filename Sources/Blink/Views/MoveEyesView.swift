import SwiftUI
import AppKit
import BlinkCore

// MARK: - Shapes (ported from the MoveEyes app — vector-only, no PNG assets)

/// Flat almond eye outline drawn as the LEFT eye: sharp outer tip at minX
/// (high), inner/nasal tip at maxX (low). `mirrored` flips for the right eye.
/// `openness` morphs the upper lid down onto the lower lash line (1 = open,
/// 0 = closed) — the corner tips stay fixed, so the shape blinks in place.
struct MoveEyeShape: Shape {
    var mirrored = false
    var openness: CGFloat = 1

    static let outerTip = CGPoint(x: 0.00, y: 0.06)
    static let innerTip = CGPoint(x: 1.00, y: 0.94)
    /// Open upper-lid cubic controls (outer→inner).
    static let upperC1 = CGPoint(x: 0.32, y: -0.10)
    static let upperC2 = CGPoint(x: 0.76, y: 0.20)
    /// Lower-lid cubic controls traversed outer→inner — also the closed
    /// position of the upper lid, so at openness 0 the lids coincide.
    static let lowerC1 = CGPoint(x: 0.07, y: 0.86)
    static let lowerC2 = CGPoint(x: 0.52, y: 1.08)

    var animatableData: CGFloat {
        get { openness }
        set { openness = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = upperLidPath(in: rect)
        p.addCurve(
            to: pt(Self.outerTip, rect),
            control1: pt(Self.lowerC2, rect),
            control2: pt(Self.lowerC1, rect)
        )
        p.closeSubpath()
        return p
    }

    func upperLidPath(in rect: CGRect) -> Path {
        let k = 1 - min(max(openness, 0), 1)
        var p = Path()
        p.move(to: pt(Self.outerTip, rect))
        p.addCurve(
            to: pt(Self.innerTip, rect),
            control1: pt(Self.lerp(Self.upperC1, Self.lowerC1, k), rect),
            control2: pt(Self.lerp(Self.upperC2, Self.lowerC2, k), rect)
        )
        return p
    }

    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ k: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
    }

    func lowerLidPath(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: pt(Self.innerTip, rect))
        p.addCurve(
            to: pt(Self.outerTip, rect),
            control1: pt(Self.lowerC2, rect),
            control2: pt(Self.lowerC1, rect)
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

/// Sampled geometry of the OPEN eye aperture in unit space (the almond's
/// bounding square, unmirrored). For a horizontal position x it answers:
/// where is the opening's vertical midline, and how tall is the opening?
/// Built once from the same Bézier control points `MoveEyeShape` draws with.
private enum EyeAperture {
    static let steps = 16
    static let table: [(midY: CGFloat, halfH: CGFloat)] = {
        func bez(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p3: CGPoint,
                 _ t: CGFloat) -> CGPoint {
            let m = 1 - t
            let a = m * m * m, b = 3 * m * m * t, c = 3 * m * t * t, d = t * t * t
            return CGPoint(x: a * p0.x + b * c1.x + c * c2.x + d * p3.x,
                           y: a * p0.y + b * c1.y + c * c2.y + d * p3.y)
        }
        // Both lids traversed outer→inner so x grows monotonically.
        let upper = (0...32).map {
            bez(MoveEyeShape.outerTip, MoveEyeShape.upperC1,
                MoveEyeShape.upperC2, MoveEyeShape.innerTip, CGFloat($0) / 32)
        }
        let lower = (0...32).map {
            bez(MoveEyeShape.outerTip, MoveEyeShape.lowerC1,
                MoveEyeShape.lowerC2, MoveEyeShape.innerTip, CGFloat($0) / 32)
        }
        func y(at x: CGFloat, on pts: [CGPoint]) -> CGFloat {
            guard x > pts[0].x else { return pts[0].y }
            for i in 1..<pts.count where pts[i].x >= x {
                let a = pts[i - 1], b = pts[i]
                let f = (x - a.x) / max(b.x - a.x, 0.0001)
                return a.y + (b.y - a.y) * f
            }
            return pts[pts.count - 1].y
        }
        return (0...steps).map { i in
            let x = CGFloat(i) / CGFloat(steps)
            let yu = y(at: x, on: upper), yl = y(at: x, on: lower)
            return (midY: (yu + yl) / 2, halfH: max(0, (yl - yu) / 2))
        }
    }()

    static func sample(at x: CGFloat) -> (midY: CGFloat, halfH: CGFloat) {
        let u = min(max(x, 0), 1) * CGFloat(steps)
        let i = min(Int(u), steps - 1)
        let f = u - CGFloat(i)
        let a = table[i], b = table[i + 1]
        return (a.midY + (b.midY - a.midY) * f, a.halfH + (b.halfH - a.halfH) * f)
    }
}

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
    /// Eyelid position, 1 = fully open, 0 = closed.
    var openness: CGFloat = 1

    var body: some View {
        let h = size
        let w = size * 2.1
        let sw = 0.90 * w
        let sh = 0.96 * h
        let scleraDX = (mirrored ? -1 : 1) * (w - sw) / 2
        let irisD = 0.52 * sh
        let shape = MoveEyeShape(mirrored: mirrored, openness: openness)
        let off = irisOffset(sw: sw, sh: sh, irisD: irisD)

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
                .offset(x: off.x, y: off.y)
            }
            .frame(width: sw, height: sh)
            .clipShape(shape)
            .offset(x: scleraDX, y: -0.047 * h)
        }
        .frame(width: w, height: size)
    }

    /// Iris offset from the sclera-frame center, in points. The iris rides the
    /// eye's actual opening: horizontally it stops short of the pointed tips,
    /// vertically it stays level for left/right gazes but is clamped into the
    /// slanted aperture band so it never vanishes into a corner.
    private func irisOffset(sw: CGFloat, sh: CGFloat, irisD: CGFloat) -> CGPoint {
        // Horizontal position across the eye, in screen terms. ±0.20 keeps the
        // iris out of the slanted corner zones, so a left/right gaze reads at
        // the same height in both (mirrored) eyes instead of diverging.
        let uScreen = min(max(0.5 + CGFloat(gaze.dx) * 0.20, 0.12), 0.88)
        // The aperture table describes the unmirrored shape.
        let uShape = mirrored ? 1 - uScreen : uScreen
        let ap = EyeAperture.sample(at: uShape)
        let irisUnitR = irisD / 2 / sh
        // Vertical slack inside the opening at this x; lets up/down gazes tuck
        // the iris well under the lids without losing it entirely.
        let slack = max(0, ap.halfH - irisUnitR * 0.28)
        let baseY = EyeAperture.sample(at: 0.5).midY
        let y = min(max(baseY + CGFloat(gaze.dy) * slack, ap.midY - slack),
                    ap.midY + slack)
        return CGPoint(x: (uScreen - 0.5) * sw, y: (y - 0.5) * sh)
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
    /// Duration of the current step; lets path animations (circle, figure-8)
    /// finish cleanly — the iris eases back to center as the step ends
    /// instead of cutting off mid-sweep. 0 = unknown (ease-in only).
    var holdSeconds: Double = 0

    private var isPath: Bool {
        direction == "circle_cw" || direction == "circle_ccw" || direction == "figure8"
    }

    @State private var spinStart: TimeInterval = 0
    /// When the pair appeared — drives the closed→open "awakening" reveal.
    @State private var appearStart: TimeInterval = 0
    /// When the current step began — clock for blink cycles and lid eases.
    @State private var phaseStart: TimeInterval = 0
    /// Lid position at the moment the step changed, for a continuous blend.
    @State private var transitionFrom: Double = 1
    /// Previous step direction, so the blend can start from its lid value.
    @State private var lastDirection: String = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let spinDuration: Double = 1.6
    private let spinTurns: Double = 3.0

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let off = offset(at: t)
            let live = GazeDirection(dx: off.x, dy: off.y)
            let s = activationSpin(at: t)
            let lid = openness(at: t)
            HStack(spacing: eyeSize * 0.42) {
                MoveEyeView(gaze: live, spin: s, size: eyeSize, style: style,
                            openness: lid)
                MoveEyeView(gaze: live, spin: s, size: eyeSize, mirrored: true,
                            style: style, openness: lid)
            }
            .animation(isPath ? nil : .easeInOut(duration: 0.5), value: gaze)
        }
        .onAppear {
            let now = Date().timeIntervalSinceReferenceDate
            appearStart = now
            phaseStart = now
            // Delay the tomoe whirl so it plays just as the lids finish opening.
            spinStart = now + 1.1
            transitionFrom = 1
            lastDirection = direction
        }
        .onChange(of: direction) { newDirection in
            let now = Date().timeIntervalSinceReferenceDate
            transitionFrom = steadyOpenness(of: lastDirection, at: now)
            lastDirection = newDirection
            phaseStart = now
            spinStart = now
        }
    }

    /// Activation burst: tomoe accelerate, whirl and settle (smootherstep).
    private func activationSpin(at t: TimeInterval) -> Double {
        if reduceMotion { return 0 }
        let u = min(max((t - spinStart) / spinDuration, 0), 1)
        let eased = u * u * u * (u * (u * 6 - 15) + 10)
        return spinTurns * 360 * eased
    }

    // MARK: - Eyelids

    /// Lid position for the current frame: the break-start awakening gates a
    /// per-step value (blink wave, closed hold, or open), blended smoothly
    /// from wherever the lids were when the step changed.
    private func openness(at t: TimeInterval) -> CGFloat {
        if reduceMotion { return direction == "closed" ? 0 : 1 }

        // Awakening: eyes hold shut, then open once at break start.
        let ta = t - appearStart
        let awaken: Double
        if ta < 0.35 {
            awaken = 0
        } else {
            let u = min(max((ta - 0.35) / 0.9, 0), 1)
            awaken = u * u * u * (u * (u * 6 - 15) + 10)
        }

        let mode = steadyOpenness(of: direction, at: t)
        let blend = min(max((t - phaseStart) / 0.35, 0), 1)
        let eased = blend * blend * (3 - 2 * blend)
        let value = transitionFrom + (mode - transitionFrom) * eased
        return CGFloat(min(awaken, value))
    }

    /// The step's own lid value, ignoring transitions: closed steps hold shut,
    /// the blink step sweeps shut-and-open once per second, all else is open.
    private func steadyOpenness(of dir: String, at t: TimeInterval) -> Double {
        switch dir {
        case "closed":
            return 0
        case "blink":
            // Natural blink: a quick snap shut, then a slightly slower reopen.
            let ph = max(0, t - phaseStart).truncatingRemainder(dividingBy: 1.0)
            func smooth(_ u: Double) -> Double {
                let c = min(max(u, 0), 1)
                return c * c * (3 - 2 * c)
            }
            if ph < 0.12 { return 1 - smooth(ph / 0.12) }
            if ph < 0.34 { return smooth((ph - 0.12) / 0.22) }
            return 1
        default:
            return 1
        }
    }

    private func offset(at t: TimeInterval) -> (x: Double, y: Double) {
        let tp = max(0, t - phaseStart)
        switch direction {
        case "circle_cw":
            let a = tp * 1.7, r = pathEnvelope(tp)
            return (cos(a) * r, sin(a) * r)
        case "circle_ccw":
            let a = -tp * 1.7, r = pathEnvelope(tp)
            return (cos(a) * r, sin(a) * r)
        case "figure8":
            let a = tp * 1.7, r = pathEnvelope(tp)
            return (sin(a) * r, sin(2 * a) / 2 * r)
        default:
            // A barely-there slow drift keeps the eyes alive during long
            // fixed holds (e.g. the 20 s far gaze) without moving the target.
            if reduceMotion { return (gaze.dx, gaze.dy) }
            let sway = 0.018
            return (gaze.dx + sin(t * 0.7) * sway,
                    gaze.dy + sin(t * 0.53 + 1.3) * sway)
        }
    }

    /// Radius envelope for path sweeps: the iris eases out from center when
    /// the step starts and eases back to center as the hold runs out, so the
    /// animation always completes instead of cutting off mid-sweep.
    private func pathEnvelope(_ tp: Double) -> Double {
        func smooth(_ u: Double) -> Double {
            let c = min(max(u, 0), 1)
            return c * c * (3 - 2 * c)
        }
        let rampIn = smooth(tp / 0.6)
        guard holdSeconds > 1.4 else { return rampIn }
        let rampOut = smooth((holdSeconds - tp) / 0.6)
        return min(rampIn, rampOut)
    }
}
