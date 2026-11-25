import SwiftUI
import SharinganCore

/// Procedural SwiftUI re-creation of `Vedio/angry eyes.mp4`: eyes fade in from the lower
/// crescent, look around under angled lids, then dim and shut. Pure function of time: a given
/// `fixedTime` always renders the same frame (used by the render harness).
public struct AngryEyesView: View {
    private let fixedTime: TimeInterval?
    @State private var start = Date()

    /// - Parameter fixedTime: render exactly this clip time (seconds) instead of animating.
    public init(fixedTime: TimeInterval? = nil) {
        self.fixedTime = fixedTime
    }

    public var body: some View {
        Group {
            if let t = fixedTime {
                AngryFaceCanvas(pose: AngryEyesTimeline.pose(at: t), iris: .original, placement: .video)
            } else {
                TimelineView(.periodic(from: start, by: 1.0 / 30.0)) { context in
                    AngryFaceCanvas(pose: AngryEyesTimeline.pose(at: context.date.timeIntervalSince(start)),
                                    iris: .original, placement: .video)
                }
            }
        }
        .aspectRatio(1080.0 / 2340.0, contentMode: .fit)
        .background(Color.black)
    }
}

/// Where the eye space is drawn inside the canvas.
enum AngryPlacement {
    /// The reference clip: 1080x2340 on black, the eye strip starting at y 900.
    case video
    /// Only this eye-space rectangle, centred and fitted.
    case crop(CGRect)
}

/// Draws one pose of the angry eyes. `iris == .sharingan` swaps the black pupil + highlight for
/// `MoveIrisView` symbols clipped by the same eyeball and lids.
struct AngryFaceCanvas: View {
    let pose: AngryEyesPose
    var iris: BreakIrisStyle = .original
    var left = LookingForIrisSpec()
    var right = LookingForIrisSpec()
    var placement: AngryPlacement = .video

    /// Diameter the iris symbols are resolved at; drawn scaled to the pupil.
    static let irisSymbolDiameter: CGFloat = 180

    var body: some View {
        Canvas(opaque: isVideo, colorMode: .nonLinear, rendersAsynchronously: false) { ctx, size in
            var c = ctx
            switch placement {
            case .video:
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                let s = size.width / 1080
                c.translateBy(x: 0, y: -900 * s)
                c.scaleBy(x: s, y: s)
            case .crop(let r):
                let s = min(size.width / r.width, size.height / r.height)
                c.translateBy(x: (size.width - r.width * s) / 2, y: (size.height - r.height * s) / 2)
                c.scaleBy(x: s, y: s)
                c.translateBy(x: -r.minX, y: -r.minY)
                c.clip(to: Path(r))
            }
            let symL = iris == .sharingan ? ctx.resolveSymbol(id: 0) : nil
            let symR = iris == .sharingan ? ctx.resolveSymbol(id: 1) : nil
            AngryRenderer(pose: pose, irisLeft: symL, irisRight: symR).draw(into: c)
        } symbols: {
            if iris == .sharingan {
                irisView(left).tag(0)
                irisView(right).tag(1)
            }
        }
    }

    private var isVideo: Bool {
        if case .video = placement { return true }
        return false
    }

    private func irisView(_ spec: LookingForIrisSpec) -> some View {
        MoveIrisView(diameter: Self.irisSymbolDiameter, spin: spec.spin, style: spec.style,
                     emergence: spec.emergence, tomoeStage: spec.tomoeStage)
    }
}

// MARK: - Renderer

private struct AngryRenderer {
    let pose: AngryEyesPose
    var irisLeft: GraphicsContext.ResolvedSymbol? = nil
    var irisRight: GraphicsContext.ResolvedSymbol? = nil

    /// Shade (0...1) of the eyeball at distance `d` px inside its rim (or below the lid edge),
    /// measured from the clip: a dark rim that brightens to full white about 80 px in.
    private static let shade: [(d: Double, v: Double)] =
        [(0, 0.30), (8, 0.37), (15, 0.45), (25, 0.59), (40, 0.79), (60, 0.96), (80, 1)]

    func draw(into base: GraphicsContext) {
        eye(base, pose.left, irisLeft)
        eye(base, pose.right, irisRight)
        if pose.openness < 0.5 { slits(base) }
    }

    private func gray(_ v: Double, _ a: Double = 1) -> Color { Color(white: v, opacity: a) }

    // MARK: Eyeball

    private func eye(_ base: GraphicsContext, _ g: AngryEyeGeometry, _ sym: GraphicsContext.ResolvedSymbol?) {
        guard g.brightness > 0.004 else { return }
        let circle = Path(ellipseIn: CGRect(x: g.cx - g.radius, y: g.cy - g.radius,
                                            width: 2 * g.radius, height: 2 * g.radius))
        // brightness and edge blur belong to the finished eye, so they go on the layer composite
        var b = base
        b.opacity = min(1, g.brightness)
        // fitted edge ramp width -> gaussian sigma; sharp frames (ramp ~2 px) stay unblurred
        let sigma = (g.blur - 1.6) / 2.56
        if sigma > 0.35 { b.addFilter(.blur(radius: sigma)) }
        b.drawLayer { l in
            let softLid = g.lidSoft > 3.5
            var e = l
            if !softLid { e.clip(to: upperLidClip(g)) }
            e.clip(to: circle)
            e.fill(circle, with: .radialGradient(radialShade(g.radius), center: CGPoint(x: g.cx, y: g.cy),
                                                 startRadius: 0, endRadius: g.radius))
            drawPupil(e, g, sym)
            // the lid casts a soft shadow onto the ball (and the highlight)
            e.blendMode = .multiply
            let (start, end) = lidShadeAxis(g)
            e.fill(Path(CGRect(x: g.cx - 2 * g.radius, y: g.cy - 2 * g.radius, width: 4 * g.radius, height: 4 * g.radius)),
                   with: .linearGradient(lidShadeGradient(g), startPoint: start, endPoint: end))

            if softLid {
                // blurry lid edge while the eyes open and close: mask with a blurred lid region
                l.blendMode = .destinationIn
                l.drawLayer { m in
                    m.addFilter(.blur(radius: g.lidSoft / 2.56))
                    m.fill(upperLidClip(g), with: .color(.white))
                }
            }
            if lowerLidActive(g) {
                l.blendMode = .destinationIn
                let (a, b) = lowerLidAxis(g)
                l.fill(Path(CGRect(x: g.cx - 2 * g.radius, y: g.cy - 2 * g.radius, width: 4 * g.radius, height: 4 * g.radius)),
                       with: .linearGradient(Gradient(stops: [.init(color: .white, location: 0),
                                                              .init(color: .white.opacity(0), location: 1)]),
                                             startPoint: a, endPoint: b))
            }
        }
    }

    private func drawPupil(_ e: GraphicsContext, _ g: AngryEyeGeometry, _ sym: GraphicsContext.ResolvedSymbol?) {
        let c = CGPoint(x: g.pupilX, y: g.pupilY)
        if let sym {
            var q = e
            let k = g.pupilRadius * 2 / AngryFaceCanvas.irisSymbolDiameter
            q.translateBy(x: c.x, y: c.y)
            q.scaleBy(x: k, y: k)
            q.translateBy(x: -c.x, y: -c.y)
            q.draw(sym, at: c, anchor: .center)
            return
        }
        e.fill(Path(ellipseIn: CGRect(x: c.x - g.pupilRadius, y: c.y - g.pupilRadius,
                                      width: 2 * g.pupilRadius, height: 2 * g.pupilRadius)), with: .color(.black))
        let h = CGPoint(x: c.x + g.highlightX, y: c.y + g.highlightY)
        e.fill(Path(ellipseIn: CGRect(x: h.x - g.highlightRadius, y: h.y - g.highlightRadius,
                                      width: 2 * g.highlightRadius, height: 2 * g.highlightRadius)),
               with: .color(gray(0.98)))
    }

    private func radialShade(_ radius: Double) -> Gradient {
        var stops = [Gradient.Stop(color: gray(1), location: 0)]
        for s in Self.shade.reversed() {
            stops.append(.init(color: gray(s.v), location: max(0, min(1, 1 - s.d / radius))))
        }
        // locations must not decrease
        var last = 0.0
        stops = stops.map { s in
            let loc = max(last, s.location)
            last = loc
            return .init(color: s.color, location: loc)
        }
        return Gradient(stops: stops)
    }

    // MARK: Lids

    /// Region below the angled upper lid (extended along its end tangents).
    private func upperLidClip(_ g: AngryEyeGeometry) -> Path {
        let n = 24
        var pts = [CGPoint]()
        for i in 0...n {
            let u = -1.25 + 2.5 * Double(i) / Double(n)
            pts.append(CGPoint(x: g.cx + u * g.radius, y: g.lidY(atU: u)))
        }
        var p = Path()
        p.move(to: pts[0])
        for q in pts.dropFirst() { p.addLine(to: q) }
        p.addLine(to: CGPoint(x: pts[n].x, y: 4000))
        p.addLine(to: CGPoint(x: pts[0].x, y: 4000))
        p.closeSubpath()
        return p
    }

    /// Axis (perpendicular to the lid line at the eye centre) along which the lid shadow ramps.
    private func lidShadeAxis(_ g: AngryEyeGeometry) -> (CGPoint, CGPoint) {
        let m = g.lidSlope / g.radius
        let norm = (1 + m * m).squareRoot()
        let n = CGPoint(x: -m / norm, y: 1 / norm)
        let p0 = CGPoint(x: g.cx, y: g.lidY0)
        let len = 80 / max(0.2, g.lidShade)
        return (p0, CGPoint(x: p0.x + n.x * len, y: p0.y + n.y * len))
    }

    private func lidShadeGradient(_ g: AngryEyeGeometry) -> Gradient {
        Gradient(stops: Self.shade.map { .init(color: gray($0.v), location: $0.d / 80) })
    }

    private func lowerLidActive(_ g: AngryEyeGeometry) -> Bool {
        g.lowerY0 - abs(g.lowerSlope) - g.lowerSoft < g.cy + g.radius + 4
    }

    /// Soft lower-lid edge: opaque above the line, transparent below it over `lowerSoft` px.
    private func lowerLidAxis(_ g: AngryEyeGeometry) -> (CGPoint, CGPoint) {
        let m = g.lowerSlope / g.radius
        let norm = (1 + m * m).squareRoot()
        let n = CGPoint(x: -m / norm, y: 1 / norm)
        let half = max(1.2, g.lowerSoft) / norm / 2
        let p0 = CGPoint(x: g.cx, y: g.lowerY0)
        return (CGPoint(x: p0.x - n.x * half, y: p0.y - n.y * half),
                CGPoint(x: p0.x + n.x * half, y: p0.y + n.y * half))
    }

    // MARK: Closed eyes

    /// A shut eye is only a slit along the lower rim.
    private func slits(_ base: GraphicsContext) {
        let a = BreakGazePath01.smooth((0.5 - pose.openness) / 0.5)
        for g in [pose.left, pose.right] {
            var p = Path()
            let r = g.radius - 10
            for i in 0...24 {
                let ang = (25 + 130 * Double(i) / 24) * .pi / 180
                let pt = CGPoint(x: g.cx + cos(ang) * r, y: g.cy + sin(ang) * r)
                i == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
            base.stroke(p, with: .color(gray(0.42, a * min(1, g.brightness))),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round))
        }
    }
}

private enum BreakGazePath01 {
    static func smooth(_ u: Double) -> Double {
        let c = min(max(u, 0), 1)
        return c * c * (3 - 2 * c)
    }
}

#Preview("Angry eyes") {
    AngryEyesView()
        .frame(width: 360, height: 780)
}

#Preview("Angry eyes t=4.8") {
    AngryEyesView(fixedTime: 4.8)
        .frame(width: 360, height: 780)
}
