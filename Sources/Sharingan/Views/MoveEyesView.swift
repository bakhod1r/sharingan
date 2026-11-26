import SwiftUI
import AppKit
import SharinganCore

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
    /// Arm thickness at the center, as a fraction of radius (tapers to 0).
    var width: CGFloat = 0.10

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
                let w = R * width * (1 - t)
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

/// N straight-edged shuriken wings: sharp tip at the rim, wide root near the
/// pupil. `lean` skews the tip sideways for a thrown-blade look.
struct MoveShurikenShape: Shape {
    var blades = 3
    var lean: Double = 0.30
    /// Half-width of the root, in radians at the root circle.
    var rootHalfWidth: Double = 0.42
    /// Root circle radius as a fraction of the outer radius.
    var rootRadius: CGFloat = 0.24

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let R = min(rect.width, rect.height) / 2
        let r0 = R * rootRadius
        var p = Path()
        for i in 0..<blades {
            let base = Double(i) * 2 * .pi / Double(blades) - .pi / 2
            let p1 = CGPoint(x: c.x + r0 * cos(base - rootHalfWidth),
                             y: c.y + r0 * sin(base - rootHalfWidth))
            let tip = CGPoint(x: c.x + R * cos(base + lean),
                              y: c.y + R * sin(base + lean))
            let p2 = CGPoint(x: c.x + r0 * cos(base + rootHalfWidth),
                             y: c.y + r0 * sin(base + rootHalfWidth))
            p.move(to: p1)
            p.addLine(to: tip)
            p.addLine(to: p2)
            p.closeSubpath()
        }
        return p
    }
}

/// A regular polygon, first vertex pointing up. Stroked for ring outlines.
struct MovePolygonShape: Shape {
    var sides = 3

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let R = min(rect.width, rect.height) / 2
        var p = Path()
        for i in 0..<sides {
            let a = Double(i) * 2 * .pi / Double(sides) - .pi / 2
            let pt = CGPoint(x: c.x + R * cos(a), y: c.y + R * sin(a))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
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
    /// 0…1 — how far the black pattern has whirled out of the pupil. It scales
    /// up from the pupil with an extra swirl of rotation as it opens; 0 hides
    /// the pattern entirely (bare red iris), 1 is fully formed.
    var emergence: CGFloat = 1
    /// Continuous tomoe count (1…3) for the classic family. A fractional
    /// value is mid-awakening: existing tomoe glide to their new slots while
    /// the newest grows out of the ring. nil = whole stages from the style.
    var tomoeStage: CGFloat? = nil
    /// Outgoing pattern while crossfading into `style` (nil = none).
    var previousStyle: SharinganStyle? = nil
    /// 0 = `previousStyle` only, 1 = `style` only.
    var blend: CGFloat = 1

    var body: some View {
        let r = diameter / 2
        let e = min(max(emergence, 0), 1)
        let b = Double(min(max(blend, 0), 1))
        let prev: SharinganStyle? = b < 1 ? previousStyle : nil
        ZStack {
            // Red/purple base: if the crossfade changes family, fade the base too.
            if let prev, (prev == .rinnegan) != (style == .rinnegan) {
                irisBase(rinnegan: prev == .rinnegan, r: r)
                irisBase(rinnegan: style == .rinnegan, r: r).opacity(b)
            } else {
                irisBase(rinnegan: style == .rinnegan, r: r)
            }
            Circle()
                .stroke(rimColor.opacity(0.9), lineWidth: 0.05 * r)
                .padding(0.02 * r)

            // Outgoing pattern: fades out, shrinks a touch and swirls away.
            if let prev {
                pattern(r: r, style: prev, stage: nil)
                    .scaleEffect(max((0.08 + 0.92 * e) * (1 - 0.12 * b), 0.001))
                    .opacity(Double(min(1, e * 2.4)) * (1 - b))
                    .rotationEffect(.degrees(spin - Double(1 - e) * 260 + 40 * b))
            }

            // Always in the tree (no structural if) so withAnimation-driven
            // emergence changes animate the whirl instead of a removal fade.
            pattern(r: r, style: style, stage: tomoeStage)
                .scaleEffect(max((0.08 + 0.92 * e) * (prev == nil ? 1 : 0.85 + 0.15 * b), 0.001))
                .opacity(Double(min(1, e * 2.4)) * (prev == nil ? 1 : b))
                .rotationEffect(.degrees(spin - Double(1 - e) * 260 - (prev == nil ? 0 : 40 * (1 - b))))

            Circle()
                .fill(Color.black)
                .frame(width: 0.26 * r, height: 0.26 * r)
        }
        .frame(width: diameter, height: diameter)
    }

    private func irisBase(rinnegan: Bool, r: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(stops: Self.baseStops(rinnegan: rinnegan),
                                 center: .center, startRadius: 0, endRadius: r))
    }

    /// Iris base: Sharingan red for every style except the purple Rinnegan.
    private static func baseStops(rinnegan: Bool) -> [Gradient.Stop] {
        if rinnegan {
            return [
                .init(color: Color(red: 0.80, green: 0.72, blue: 0.93), location: 0.0),
                .init(color: Color(red: 0.66, green: 0.53, blue: 0.85), location: 0.45),
                .init(color: Color(red: 0.58, green: 0.44, blue: 0.80), location: 0.65),
                .init(color: Color(red: 0.44, green: 0.30, blue: 0.66), location: 0.88),
                .init(color: Color(red: 0.30, green: 0.17, blue: 0.50), location: 1.0),
            ]
        }
        return [
            .init(color: Color(red: 0.58, green: 0.02, blue: 0.03), location: 0.0),
            .init(color: Color(red: 0.65, green: 0.05, blue: 0.05), location: 0.45),
            .init(color: Color(red: 0.71, green: 0.08, blue: 0.07), location: 0.65),
            .init(color: Color(red: 0.52, green: 0.02, blue: 0.02), location: 0.88),
            .init(color: Color(red: 0.34, green: 0.00, blue: 0.01), location: 1.0),
        ]
    }

    private var rimColor: Color {
        style == .rinnegan
            ? Color(red: 0.12, green: 0.04, blue: 0.22)
            : Color(red: 0.08, green: 0.0, blue: 0.0)
    }

    /// The spinning black pattern for each style.
    @ViewBuilder
    private func pattern(r: CGFloat, style: SharinganStyle, stage tomoeStage: CGFloat?) -> some View {
        let ringR = 0.52 * r
        switch style {
        case .classic:
            classicTomoe(stage: tomoeStage ?? 3, r: r, ringR: ringR)
        case .tomoe1:
            classicTomoe(stage: tomoeStage ?? 1, r: r, ringR: ringR)
        case .tomoe2:
            classicTomoe(stage: tomoeStage ?? 2, r: r, ringR: ringR)
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
        case .madara:
            // Wide, hooked fan blades that nearly close into a ring.
            MovePinwheelShape(blades: 3, lean: 0.95, rootWidth: 0.50)
                .fill(Color.black)
                .frame(width: 1.9 * r, height: 1.9 * r)
        case .shuriken:
            ZStack {
                Circle()
                    .stroke(Color.black, lineWidth: 0.07 * r)
                    .frame(width: ringR * 2, height: ringR * 2)
                MoveShurikenShape(blades: 3, lean: 0.22, rootHalfWidth: 0.60,
                                  rootRadius: 0.34)
                    .fill(Color.black)
                    .frame(width: 1.8 * r, height: 1.8 * r)
            }
        case .swirl:
            MoveSpiralShape(arms: 1, turns: 2.1, width: 0.22)
                .fill(Color.black)
                .frame(width: 1.76 * r, height: 1.76 * r)
        case .triangleTomoe:
            ZStack {
                MovePolygonShape(sides: 3)
                    .stroke(Color.black, lineWidth: 0.06 * r)
                    .frame(width: 1.16 * r, height: 1.16 * r)
                ForEach(0..<3, id: \.self) { i in
                    let head = Angle(degrees: -90 + Double(i) * 120)
                    MoveTomoeTail(
                        ringRadius: 0.58 * r,
                        headAngle: head,
                        sweep: .degrees(-50),
                        startWidth: 0.16 * r
                    )
                    .fill(Color.black)
                    Circle()
                        .fill(Color.black)
                        .frame(width: 0.26 * r, height: 0.26 * r)
                        .offset(x: 0.58 * r * cos(head.radians),
                                y: 0.58 * r * sin(head.radians))
                }
            }
        case .ringCrescents:
            ZStack {
                Circle()
                    .stroke(Color.black, lineWidth: 0.05 * r)
                    .frame(width: 1.56 * r, height: 1.56 * r)
                ForEach(0..<3, id: \.self) { i in
                    MoveArcBandShape(
                        ringRadius: 0.44 * r,
                        centerAngle: .degrees(-90 + Double(i) * 120),
                        sweep: .degrees(110),
                        maxWidth: 0.24 * r
                    )
                    .fill(Color.black)
                }
            }
        case .rinnegan:
            // Concentric rings with two staggered tomoe orbits (Rinne look).
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    let rr = (0.30 + 0.25 * CGFloat(i)) * r
                    Circle()
                        .stroke(Color.black.opacity(0.78), lineWidth: 0.035 * r)
                        .frame(width: rr * 2, height: rr * 2)
                }
                ForEach(0..<3, id: \.self) { i in
                    let head = Angle(degrees: -90 + Double(i) * 120)
                    tomoe(ringRadius: 0.55 * r, head: head, r: r)
                }
                ForEach(0..<3, id: \.self) { i in
                    let head = Angle(degrees: -30 + Double(i) * 120)
                    tomoe(ringRadius: 0.80 * r, head: head, r: r)
                }
            }
        }
    }

    /// Classic-family pattern at a continuous stage (1…3 tomoe). Whole
    /// numbers are resting states; a fractional stage is mid-awakening —
    /// the existing tomoe glide toward their new slots while the newest one
    /// grows out of the ring (head swells in place, tail sweeps out behind).
    @ViewBuilder
    private func classicTomoe(stage: CGFloat, r: CGFloat, ringR: CGFloat) -> some View {
        let s = min(max(stage, 1), 3)
        let grown = Int(s)
        let frac = s - CGFloat(grown)
        let count = frac > 0.001 ? grown + 1 : grown
        ZStack {
            Circle()
                .stroke(Color(red: 0.22, green: 0.0, blue: 0.01).opacity(0.85), lineWidth: 0.035 * r)
                .frame(width: ringR * 2, height: ringR * 2)
            ForEach(0..<count, id: \.self) { i in
                let head = Angle(degrees: -80 + Double(i) * 360 / Double(s))
                let grow = i < grown ? CGFloat(1) : frac
                // Pronounced comma: a long, wide tail hooking around the ring
                // so the mark reads as tomoe (not plain dots) even at Dock and
                // menu bar sizes.
                MoveTomoeTail(
                    ringRadius: ringR,
                    headAngle: head,
                    sweep: .degrees(-100 * Double(grow)),
                    startWidth: 0.27 * r * grow
                )
                .fill(Color.black)
                Circle()
                    .fill(Color.black)
                    .frame(width: max(0.32 * r * grow, 0.001),
                           height: max(0.32 * r * grow, 0.001))
                    .offset(x: ringR * cos(head.radians), y: ringR * sin(head.radians))
            }
        }
    }

    /// One comma tomoe riding a ring: filled head + tapering tail.
    @ViewBuilder
    private func tomoe(ringRadius: CGFloat, head: Angle, r: CGFloat) -> some View {
        MoveTomoeTail(
            ringRadius: ringRadius,
            headAngle: head,
            sweep: .degrees(-45),
            startWidth: 0.11 * r
        )
        .fill(Color.black)
        Circle()
            .fill(Color.black)
            .frame(width: 0.18 * r, height: 0.18 * r)
            .offset(x: ringRadius * cos(head.radians),
                    y: ringRadius * sin(head.radians))
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
    /// Pattern emergence passed through to the iris (see MoveIrisView).
    var emergence: CGFloat = 1
    /// Fractional tomoe stage passed through to the iris (see MoveIrisView).
    var tomoeStage: CGFloat? = nil
    /// Outgoing pattern + blend, passed through to the iris (crossfade).
    var previousStyle: SharinganStyle? = nil
    var blend: CGFloat = 1
    /// `.original` swaps the Sharingan iris for a black pupil with a small white highlight.
    var iris: BreakIrisStyle = .sharingan

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
                    if iris == .original {
                        // Black pupil as wide as the Sharingan iris, highlight towards the outer corner.
                        Circle().fill(Color.black)
                            .frame(width: irisD, height: irisD)
                        Circle().fill(Color.white)
                            .frame(width: irisD * 0.2, height: irisD * 0.2)
                            .offset(x: (mirrored ? 1 : -1) * irisD * 0.22, y: -irisD * 0.06)
                    } else {
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
                        MoveIrisView(diameter: irisD, spin: spin, style: style,
                                     emergence: emergence, tomoeStage: tomoeStage,
                                     previousStyle: previousStyle, blend: blend)
                    }
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
        let irisUnitR = irisD / 2 / sh
        // Horizontal position across the eye, in screen terms: dx = ±1 slides the iris out to where
        // the almond (the smaller of the two mirrored eyes) still shows most of it. Both eyes use
        // the same screen position, so a left/right gaze reads the same in both.
        func apertureAt(_ uScreen: CGFloat, mirrored m: Bool) -> (midY: CGFloat, halfH: CGFloat) {
            EyeAperture.sample(at: m ? 1 - uScreen : uScreen)
        }
        let uScreen = CGFloat(MoveEyeTravel.uScreen(dx: gaze.dx, irisUnitR: Double(irisUnitR)) { u in
            Double(min(apertureAt(CGFloat(u), mirrored: false).halfH, apertureAt(CGFloat(u), mirrored: true).halfH))
        })
        let ap = apertureAt(uScreen, mirrored: mirrored)
        // Vertical slack inside the opening at this x; lets up/down gazes tuck
        // the iris well under the lids without losing it entirely.
        func slack(_ a: (midY: CGFloat, halfH: CGFloat)) -> CGFloat { max(0, a.halfH - irisUnitR * 0.28) }
        let baseY = EyeAperture.sample(at: 0.5).midY
        let s = slack(ap)
        let own = min(max(baseY + CGFloat(gaze.dy) * s, ap.midY - s), ap.midY + s)
        // The almond is slanted, so near the tips the two mirrored eyes' openings sit at different
        // heights. For a (near) level gaze put both irises at one common height inside both openings
        // when such a height exists; up/down gazes keep their own travel.
        let a0 = apertureAt(uScreen, mirrored: false), a1 = apertureAt(uScreen, mirrored: true)
        let lo = max(a0.midY - slack(a0), a1.midY - slack(a1))
        let hi = min(a0.midY + slack(a0), a1.midY + slack(a1))
        var y = own
        if lo <= hi {
            let common = min(max(baseY, lo), hi)
            let k = min(1, abs(CGFloat(gaze.dy)) / 0.1)        // 0 = level gaze, 1 = vertical gaze
            y = common + (own - common) * k
        }
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
    /// Separate style for the right (mirrored) eye; nil = same as `style`.
    var rightStyle: SharinganStyle? = nil
    /// Duration of the current step; lets path animations (circle, figure-8)
    /// finish cleanly — the iris eases back to center as the step ends
    /// instead of cutting off mid-sweep. 0 = unknown (ease-in only).
    var holdSeconds: Double = 0
    /// Pattern opening/closing animation: the pattern whirls out of the pupil
    /// at break start, collapses and reopens as the NEXT style on every step
    /// change, and collapses shut at break end. Off = static pattern.
    var transition: PatternTransitionSpeed = .normal
    /// When the break ends — drives the closing bookend (pattern + lids).
    var endDate: Date? = nil
    /// false = play the opening/closing whirls with the configured styles
    /// but never evolve along the chain (style-picker previews).
    var evolves = true
    /// Continuous ambient rotation: seconds per full turn (0 = off). The
    /// activation whirls layer on top of it.
    var spinSeconds: Double = 0
    /// Eye drawn inside the almond: the Sharingan iris or the original black pupil.
    var iris: BreakIrisStyle = .sharingan

    @State private var activation = ActivationSpin()
    /// When the pair appeared — drives the closed→open "awakening" reveal.
    @State private var appearStart: TimeInterval = 0
    /// When the current step began — clock for blink cycles and lid eases.
    @State private var phaseStart: TimeInterval = 0
    /// Lid position at the moment the step changed, for a continuous blend.
    @State private var transitionFrom: Double = 1
    /// Previous step direction, so the blend can start from its lid value.
    @State private var lastDirection: String = ""
    /// Step gaze target of the previous step, to rebuild the old step's live offset on a change.
    @State private var lastGaze: GazeDirection = .center
    /// Iris offset at the moment the step changed: it glides from here back to center, then out.
    @State private var previousGaze: GazeDirection = .center
    /// How many steps the pattern has evolved past the configured base style.
    @State private var evolutionCount: Int = 0
    /// Base-style change tracking: the old pattern crossfades into the new one.
    @State private var crossfade = StyleCrossfade()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let spinDuration: Double = 1.6
    private let spinTurns: Double = 3.0

    var body: some View {
        // 60 fps cap: the break screen is full-screen and rendered at display rate.
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let off = offset(at: t)
            let live = GazeDirection(dx: off.x, dy: off.y)
            let s = activationSpin(at: t)
            let pf = evolution.frame(at: t)
            let lid = openness(at: t) * CGFloat(pf.endFade)
            HStack(spacing: eyeSize * 0.42) {
                MoveEyeView(gaze: live, spin: s, size: eyeSize,
                            style: pf.left, openness: lid,
                            emergence: pf.emergence, tomoeStage: pf.tomoeStage,
                            previousStyle: pf.previousLeft, blend: pf.blend, iris: iris)
                MoveEyeView(gaze: live, spin: s, size: eyeSize, mirrored: true,
                            style: pf.right, openness: lid,
                            emergence: pf.emergence, tomoeStage: pf.tomoeStage,
                            previousStyle: pf.previousRight, blend: pf.blend, iris: iris)
            }
        }
        .onAppear {
            let now = Date().timeIntervalSinceReferenceDate
            appearStart = now
            phaseStart = now
            // Delay the tomoe whirl so it plays just as the lids finish opening.
            activation.reset(start: now + 1.1)
            transitionFrom = 1
            lastDirection = direction
            lastGaze = gaze
            previousGaze = .center
        }
        .onChange(of: style) { old, new in
            registerStyleChange(oldLeft: old, newLeft: new, oldRight: rightStyle ?? old, newRight: rightStyle ?? new)
        }
        .onChange(of: rightStyle) { old, new in
            registerStyleChange(oldLeft: style, newLeft: style, oldRight: old ?? style, newRight: new ?? style)
        }
        .onChange(of: direction) { _, newDirection in
            let now = Date().timeIntervalSinceReferenceDate
            transitionFrom = steadyOpenness(of: lastDirection, at: now)
            // Live iris offset under the OLD step, no sway: the glide starts exactly where the iris is.
            let live = BreakGazePath.gazeOffset(gazeInput(at: now, direction: lastDirection, gaze: lastGaze), sway: false)
            previousGaze = GazeDirection(dx: live.x, dy: live.y)
            lastDirection = newDirection
            lastGaze = gaze
            phaseStart = now
            activation.restart(at: now, now: now)
            evolutionCount += 1
        }
    }

    private func registerStyleChange(oldLeft: SharinganStyle, newLeft: SharinganStyle,
                                     oldRight: SharinganStyle, newRight: SharinganStyle) {
        crossfade.change(oldLeft: oldLeft, oldRight: oldRight, newLeft: newLeft, newRight: newRight,
                         at: Date().timeIntervalSinceReferenceDate,
                         transition: transition, reduceMotion: reduceMotion)
    }

    /// The evolution timeline for the current state — pure math shared with
    /// the headless GIF renderer, so previews match the app exactly.
    private var evolution: PatternEvolution {
        PatternEvolution(transition: transition,
                         appearStart: appearStart,
                         phaseStart: phaseStart,
                         evolutionCount: evolutionCount,
                         end: endDate?.timeIntervalSinceReferenceDate,
                         reduceMotion: reduceMotion,
                         baseLeft: style,
                         baseRight: rightStyle ?? style,
                         evolves: evolves,
                         crossfade: crossfade)
    }

    /// Activation burst (tomoe accelerate, whirl and settle) layered on the
    /// optional continuous ambient rotation.
    private func activationSpin(at t: TimeInterval) -> Double {
        if reduceMotion { return 0 }
        var s = activation.angle(at: t)
        if spinSeconds > 0 {
            s += max(0, t - appearStart) * 360 / spinSeconds
        }
        return s
    }

    // MARK: - Eyelids

    /// Lid position for the current frame: the break-start awakening gates a
    /// per-step value (blink wave, closed hold, or open), blended smoothly
    /// from wherever the lids were when the step changed.
    private func openness(at t: TimeInterval) -> CGFloat {
        if reduceMotion { return direction == "closed" ? 0 : 1 }

        // Awakening: eyes hold shut, then open once at break start.
        let awaken = PatternEvolution.awakenOpenness(at: t, since: appearStart)

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
        BreakGazePath.gazeOffset(gazeInput(at: t, direction: direction, gaze: gaze))
    }

    /// Same gaze path as the Looking-for and Angry faces: glide back to center, then out to the target.
    private func gazeInput(at t: TimeInterval, direction: String, gaze: GazeDirection) -> BreakFaceInput {
        BreakFaceInput(elapsed: max(0, t - appearStart), remaining: nil, direction: direction, gaze: gaze,
                       phaseElapsed: max(0, t - phaseStart), holdSeconds: holdSeconds,
                       reduceMotion: reduceMotion, previousGaze: previousGaze)
    }
}
