import SwiftUI
import SharinganCore

/// Procedural SwiftUI re-creation of `Vedio/looking for eyes.mp4`:
/// curious wide eyes -> angry squint -> eyes scan left/right -> blue sparks ->
/// pupils ignite -> flames rise and fade -> eyes snap open again, looping.
///
/// Pure function of time: a given `fixedTime` always renders the same frame.
/// Drawing happens in the clip's 1080x750 face space; the face band sits at
/// y 650...1650 of the 1440x2560 (9:16) design canvas on pure black.
public struct LookingForEyesView: View {
    private let fixedTime: TimeInterval?
    @State private var start = Date()

    /// - Parameter fixedTime: render exactly this clip time (seconds) instead of animating.
    public init(fixedTime: TimeInterval? = nil) {
        self.fixedTime = fixedTime
    }

    public var body: some View {
        Group {
            if let t = fixedTime {
                LookingForEyesCanvas(time: t)
            } else {
                // The clip is 30 fps, so tick at 30 fps instead of every display frame.
                TimelineView(.periodic(from: start, by: 1 / LookingForEyesTimeline.fps)) { context in
                    LookingForEyesCanvas(time: context.date.timeIntervalSince(start))
                }
            }
        }
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
        .background(Color.black)
    }
}

private struct LookingForEyesCanvas: View {
    let time: TimeInterval

    var body: some View {
        LookingForFaceCanvas(pose: LookingForEyesTimeline.pose(at: time),
                             iris: .original, placement: .video)
            .background(Color.black)
    }
}

/// One Sharingan iris to draw inside the face (Sharingan iris mode).
struct LookingForIrisSpec: Equatable {
    var style: SharinganStyle = .classic
    var spin: Double = 0
    var emergence: CGFloat = 1
    var tomoeStage: CGFloat? = nil
}

/// Where the face is drawn inside the canvas.
enum LookingForPlacement {
    /// The reference clip: 9:16 canvas, face band at y 650...1650 on black.
    case video
    /// Only this face-space rectangle (eyes, brows, flames), centred and fitted.
    case crop(CGRect)
}

/// Draws one pose of the face. Layering: glow, eyeball (sclera, iris, lids), sparks,
/// fire, crease, brows. `iris == .sharingan` swaps the black pupil + highlight for
/// `MoveIrisView` symbols clipped by the same eye opening.
struct LookingForFaceCanvas: View {
    let pose: LookingForEyesPose
    var iris: BreakIrisStyle = .original
    var left = LookingForIrisSpec()
    var right = LookingForIrisSpec()
    var placement: LookingForPlacement = .video

    private var irisDiameter: CGFloat { 2 * 85.7 }

    var body: some View {
        Canvas(opaque: isVideo, colorMode: .nonLinear, rendersAsynchronously: false) { ctx, size in
            var c = ctx
            var mouth = true
            switch placement {
            case .video:
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                let s = min(size.width / 1440, size.height / 2560)
                c.translateBy(x: (size.width - 1440 * s) / 2, y: (size.height - 2560 * s) / 2 + 650 * s)
                c.scaleBy(x: s * 4.0 / 3.0, y: s * 4.0 / 3.0)
            case .crop(let r):
                let s = min(size.width / r.width, size.height / r.height)
                c.translateBy(x: (size.width - r.width * s) / 2, y: (size.height - r.height * s) / 2)
                c.scaleBy(x: s, y: s)
                c.translateBy(x: -r.minX, y: -r.minY)
                c.clip(to: Path(r))
                mouth = false
            }
            let symL = iris == .sharingan ? ctx.resolveSymbol(id: 0) : nil
            let symR = iris == .sharingan ? ctx.resolveSymbol(id: 1) : nil
            FaceRenderer(pose: pose, irisLeft: symL, irisRight: symR, showMouth: mouth).draw(into: c)
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
        MoveIrisView(diameter: irisDiameter, spin: spec.spin, style: spec.style,
                     emergence: spec.emergence, tomoeStage: spec.tomoeStage)
    }
}

// MARK: - Renderer

private struct FaceRenderer {
    let pose: LookingForEyesPose
    var irisLeft: GraphicsContext.ResolvedSymbol? = nil
    var irisRight: GraphicsContext.ResolvedSymbol? = nil
    var showMouth = true

    private var ringRX: Double { pose.ringRX }
    private var ringRY: Double { pose.ringRY }
    private var whiteRX: Double { pose.whiteRX }
    private var whiteRY: Double { pose.whiteRY }
    /// Pupil size follows the pose (the exercise phase fits the iris to the opening).
    private var pupilRX: Double { pose.pupilRadiusX * pose.irisRadius / 85.7 }
    private var pupilRY: Double { pose.irisRadius }
    private let creaseGrey = 27.5 / 255.0

    func draw(into base: GraphicsContext) {
        // the soft glow belongs to the open eye: fade it as the lids shut
        if pose.lidOpenness > 0.001 {
            for mirrored in [false, true] {
                eye(base, mirrored) { c in
                    var g = c
                    g.opacity = pose.lidOpenness
                    glow(g)
                }
            }
        }
        if showMouth { drawMouth(base) }
        for mirrored in [false, true] { eye(base, mirrored) { eyeball($0, mirrored) } }
        if pose.lidOpenness < 0.999 {
            for mirrored in [false, true] { eye(base, mirrored) { lidLine($0) } }
        }
        for mirrored in [false, true] { eye(base, mirrored) { sparks($0, mirrored) } }
        for mirrored in [false, true] { eye(base, mirrored) { fire($0, mirrored) } }
        for mirrored in [false, true] {
            eye(base, mirrored) { shape($0, pose.crease) }
            eye(base, mirrored) { shape($0, pose.brow) }
        }
    }

    /// Runs `body` in the eye's local frame (right eye = left eye mirrored about the axis).
    private func eye(_ base: GraphicsContext, _ mirrored: Bool, _ body: (GraphicsContext) -> Void) {
        var c = base
        if mirrored {
            c.translateBy(x: 2 * pose.axis, y: 0)
            c.scaleBy(x: -1, y: 1)
        }
        body(c)
    }

    // MARK: Geometry helpers

    private var ringLeft: Double { pose.ringLeft }
    private var ringCX: Double { ringLeft + ringRX }
    private var ringCY: Double { pose.ringBottom - ringRY }
    private func pupilCenter(_ mirrored: Bool) -> CGPoint {
        CGPoint(x: ringLeft + 185.5 + (mirrored ? -pose.pupilShift : pose.pupilShift),
                y: pose.irisCenter.y)
    }

    private func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> Path {
        Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry))
    }

    private func gray(_ v: Double, _ a: Double = 1) -> Color { Color(white: v, opacity: a) }

    /// Open Catmull-Rom spline through `pts`, appended to `path` (assumes current point == pts[0]).
    private func spline(_ path: inout Path, _ pts: [CGPoint]) {
        guard pts.count > 1 else { return }
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(i - 1, 0)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(i + 2, pts.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
    }

    private func crescent(top: [CGPoint], bottom: [CGPoint]) -> Path {
        var p = Path()
        p.move(to: top[0])
        spline(&p, top)
        p.addLine(to: bottom[bottom.count - 1])
        spline(&p, bottom.reversed())
        p.closeSubpath()
        return p
    }

    // MARK: Glow under each eye

    /// Soft light spill below the ring: gaussian across x, exponential falloff down.
    private func glow(_ c: GraphicsContext) {
        // soft bloom hugging the outer edge of the ring
        var b = c
        b.clip(to: lidClip())
        b.drawLayer { l in
            l.addFilter(.blur(radius: 8))
            l.fill(ellipse(ringCX, ringCY, ringRX, ringRY), with: .color(gray(0.36)))
        }
        spill(c, cx: ringCX - 2, top: ringCY + 20, sigma: 82, fall: 55, amp: 0.2, height: 400, solid: pose.ringBottom - (ringCY + 20))
    }

    private func spill(_ c: GraphicsContext, cx: Double, top: Double,
                       sigma: Double, fall: Double, amp: Double, height: Double, solid: Double = 0) {
        let rect = CGRect(x: cx - 3 * sigma, y: top, width: 6 * sigma, height: height)
        c.drawLayer { l in
            let hs = (0...12).map { i -> Gradient.Stop in
                let u = (Double(i) / 12 - 0.5) * 6
                return .init(color: .white.opacity(amp * exp(-u * u / 2)), location: Double(i) / 12)
            }
            l.fill(Path(rect), with: .linearGradient(Gradient(stops: hs),
                                                     startPoint: CGPoint(x: rect.minX, y: 0),
                                                     endPoint: CGPoint(x: rect.maxX, y: 0)))
            l.blendMode = .destinationIn
            let vs = (0...12).map { i -> Gradient.Stop in
                let y = Double(i) / 12 * height
                let d = max(0, y - solid)
                let ramp = solid > 0 ? min(1, y / 40) : 1
                return .init(color: .white.opacity(ramp * (0.5 * exp(-d / 17) + 0.5 * exp(-d / fall))), location: Double(i) / 12)
            }
            l.fill(Path(rect), with: .linearGradient(Gradient(stops: vs),
                                                     startPoint: CGPoint(x: 0, y: rect.minY),
                                                     endPoint: CGPoint(x: 0, y: rect.maxY)))
        }
    }

    // MARK: Mouth

    private func drawMouth(_ c: GraphicsContext) {
        let m = pose.mouth
        guard m.count == 13, m[2] > m[0] else { return }
        let a = CGPoint(x: m[0], y: m[1]), b = CGPoint(x: m[2], y: m[3])
        let top = [a, CGPoint(x: m[4], y: m[5]), CGPoint(x: m[7], y: m[8]), CGPoint(x: m[10], y: m[11]), b]
        let bot = [a, CGPoint(x: m[4], y: m[6]), CGPoint(x: m[7], y: m[9]), CGPoint(x: m[10], y: m[12]), b]
        let shape = crescent(top: top, bottom: bot)
        c.drawLayer { l in
            l.addFilter(.blur(radius: 7))
            l.translateBy(x: 0, y: 7)
            l.fill(shape, with: .color(gray(0.13)))
        }
        c.drawLayer { l in
            l.addFilter(.blur(radius: 16))
            l.translateBy(x: 0, y: 16)
            l.fill(shape, with: .color(gray(0.05)))
        }
        c.fill(shape, with: .color(gray(0.322)))
        c.stroke(shape, with: .color(gray(0.322)), lineWidth: 0.8)
    }

    // MARK: Eyeball (ring, white, pupil, highlight) cut by the lid

    private func lidClip() -> Path {
        let xs = (0..<9).map { ringLeft + 12 + 34.5 * Double($0) }
        let ys = pose.lid.map { $0 - 3 }
        let slopeL = (ys[1] - ys[0]) / 34.5, slopeR = (ys[8] - ys[7]) / 34.5
        let xl = xs[0] - 90, xr = xs[8] + 110
        var p = Path()
        p.move(to: CGPoint(x: xl, y: ys[0] - slopeL * 90))
        for i in 0..<9 { p.addLine(to: CGPoint(x: xs[i], y: ys[i])) }
        p.addLine(to: CGPoint(x: xr, y: ys[8] + slopeR * 110))
        p.addLine(to: CGPoint(x: xr, y: 3000))
        p.addLine(to: CGPoint(x: xl, y: 3000))
        p.closeSubpath()
        return p
    }

    /// Edge of the shutting lid so a closed eye reads as a closed eye (choreography only
    /// lowers `lidOpenness` below 1; the video itself never does).
    private func lidLine(_ c: GraphicsContext) {
        let xs = (0..<9).map { ringLeft + 12 + 34.5 * Double($0) }
        var path = Path()
        path.move(to: CGPoint(x: xs[0], y: pose.lid[0] - 3))
        spline(&path, (0..<9).map { CGPoint(x: xs[$0], y: pose.lid[$0] - 3) })
        let a = min(1, (1 - pose.lidOpenness) * 4)
        c.stroke(path, with: .color(gray(0.36, a)), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
    }

    private func eyeball(_ c: GraphicsContext, _ mirrored: Bool) {
        var e = c
        e.clip(to: lidClip())
        let ringTop = ringCY - ringRY
        e.fill(ellipse(ringCX, ringCY, ringRX, ringRY), with: .linearGradient(
            Gradient(stops: [
                .init(color: gray(0.20), location: 0),
                .init(color: gray(0.73), location: 0.14),
                .init(color: gray(0.74), location: 1)]),
            startPoint: CGPoint(x: 0, y: ringTop), endPoint: CGPoint(x: 0, y: pose.ringBottom)))
        // ring is darker towards its outer rim (outer side only; the lower rim stays flat grey)
        e.drawLayer { l in
            var t = l
            t.translateBy(x: ringCX, y: ringCY)
            t.scaleBy(x: 1, y: ringRY / ringRX)
            t.fill(Path(ellipseIn: CGRect(x: -ringRX, y: -ringRX, width: 2 * ringRX, height: 2 * ringRX)),
                   with: .radialGradient(Gradient(stops: [
                    .init(color: .black.opacity(0), location: 0.68),
                    .init(color: .black.opacity(mirrored ? 0.2 : 0.1), location: 1)]),
                    center: .zero, startRadius: 0, endRadius: ringRX))
            l.blendMode = .destinationIn
            let x0 = ringLeft - 400, x1 = ringCX + 800
            l.fill(Path(CGRect(x: x0, y: 0, width: x1 - x0, height: 3000)),
                   with: .linearGradient(Gradient(stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white, location: (ringLeft - x0) / (x1 - x0)),
                    .init(color: .white.opacity(0), location: (ringCX - x0) / (x1 - x0)),
                    .init(color: .white.opacity(0), location: 1)]),
                    startPoint: CGPoint(x: x0, y: 0), endPoint: CGPoint(x: x1, y: 0)))
        }
        let wcy = pose.whiteCY
        let whiteCX = pose.whiteCX
        let white = ellipse(whiteCX, wcy, whiteRX, whiteRY)
        e.fill(white, with: .color(gray(0.99)))
        var p = e
        p.clip(to: white)
        let pc = pupilCenter(mirrored)
        if let sym = mirrored ? irisRight : irisLeft {
            // Sharingan iris: un-mirror it (the right eye is drawn flipped), then let the
            // white clip + lid clip cut it like the black pupil.
            var q = p
            if mirrored {
                q.translateBy(x: pc.x, y: 0)
                q.scaleBy(x: -1, y: 1)
                q.translateBy(x: -pc.x, y: 0)
            }
            let k = pose.irisRadius / 85.7
            if abs(k - 1) > 1e-6 {
                q.translateBy(x: pc.x, y: pc.y)
                q.scaleBy(x: k, y: k)
                q.translateBy(x: -pc.x, y: -pc.y)
            }
            q.draw(sym, at: pc, anchor: .center)
            return
        }
        p.fill(ellipse(pc.x, pc.y, pupilRX, pupilRY), with: .color(.black))
        if pose.highlightAlpha > 0.001 {
            p.fill(ellipse(pc.x + 5, pc.y, pupilRX * 0.68, pupilRY * 0.68), with: .color(gray(0.018, pose.highlightAlpha)))
            p.fill(ellipse(pc.x + 5, pc.y, pupilRX * 0.47, pupilRY * 0.47), with: .color(.black))
        }
        if pose.highlightAlpha > 0.001 {
            // right eye is drawn mirrored, so the left-eye offset is correct in local space
            p.fill(ellipse(pc.x + pose.highlightRelX, pose.pupilY + pose.highlightRelY, 10, 5.5),
                   with: .color(gray(1, pose.highlightAlpha)))
        }
    }

    // MARK: Brow / crease

    private func shape(_ c: GraphicsContext, _ v: [Double]) {
        guard v.count == 27 else { return }
        var top = [CGPoint](), bot = [CGPoint]()
        for i in 0..<9 {
            let x = pose.axis + v[i * 3]
            top.append(CGPoint(x: x, y: v[i * 3 + 1]))
            bot.append(CGPoint(x: x, y: max(v[i * 3 + 2], v[i * 3 + 1])))
        }
        // brows are slightly translucent so flames show through them
        c.drawLayer { l in
            l.addFilter(.blur(radius: 1.1))
            l.fill(crescent(top: top, bottom: bot), with: .color(gray(creaseGrey / 0.5, 0.5)))
        }
    }

    // MARK: Deterministic noise

    private struct RNG {
        var s: UInt64
        init(_ seed: Int) { s = UInt64(truncatingIfNeeded: seed) &* 0x9E3779B97F4A7C15 &+ 0x1234567 }
        mutating func next() -> Double {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return Double((s >> 33) & 0xFFFFFF) / Double(0x1000000)
        }
        mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }
    }

    // MARK: Blue sparks

    private func sparks(_ c: GraphicsContext, _ mirrored: Bool) {
        guard pose.spark > 0.01 else { return }
        var e = c
        e.clip(to: lidClip())
        let pc = pupilCenter(mirrored)
        var rng = RNG(Int(pose.frame) * 31 + (mirrored ? 7 : 0))
        let count = 1 + Int(pose.spark * 3)
        var path = Path()
        let low = pc.y + 45                       // only the lower part of the pupil shows below the lid
        if pose.frame >= 101 && pose.frame <= 115 {
            // radial crack figure seen just before the pupils ignite
            let cx = pc.x + 5 + rng.range(-6, 6), cy = low - 8
            for k in 0..<4 {
                let a = Double(k) * 1.1 + 0.4 + rng.range(-0.25, 0.25), len = rng.range(20, 30)
                path.move(to: CGPoint(x: cx, y: cy))
                path.addLine(to: CGPoint(x: cx + cos(a) * len, y: cy + sin(a) * len * 0.8))
            }
            path.addEllipse(in: CGRect(x: cx - 9, y: cy - 7, width: 18, height: 14))
        } else {
            for _ in 0..<count {
                let a = rng.range(0, .pi * 2), r = rng.range(5, 50)
                var p = CGPoint(x: pc.x + cos(a) * r, y: low + sin(a) * r * 0.35)
                path.move(to: p)
                for _ in 0..<Int(rng.range(3, 6)) {
                    p.x += rng.range(-14, 14)
                    p.y += rng.range(-9, 9)
                    path.addLine(to: p)
                }
            }
        }
        let tint = Color(red: 0.3, green: 0.45, blue: 1)
        e.drawLayer { l in
            l.addFilter(.blur(radius: 3))
            l.stroke(path, with: .color(tint.opacity(0.4 + 0.6 * pose.spark)), lineWidth: 3 + 8 * pose.spark)
        }
        e.stroke(path, with: .color(Color(red: 0.85, green: 0.92, blue: 1).opacity(0.45 + 0.55 * pose.spark)), lineWidth: 1.3 + 1.9 * pose.spark)
    }

    // MARK: Fire

    private let fireRed = Color(red: 1, green: 0.17, blue: 0.05)
    private let fireDeep = Color(red: 0.72, green: 0.09, blue: 0.03)
    private let fireOrange = Color(red: 1, green: 0.5, blue: 0.08)
    private let fireYellow = Color(red: 1, green: 0.88, blue: 0.22)

    /// Irregular blob: 8 vertices with jittered radius, stretched vertically by `tall`.
    private func ragged(_ rng: inout RNG, _ x: Double, _ y: Double, _ r: Double, _ tall: Double) -> Path {
        var p = Path()
        let n = 9, rot = rng.range(0, .pi)
        for i in 0..<n {
            let a = rot + Double(i) / Double(n) * .pi * 2
            let rr = r * rng.range(0.55, 1.25)
            let pt = CGPoint(x: x + cos(a) * rr, y: y + sin(a) * rr * tall)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }

    /// Curved flame ribbon: a Catmull-Rom centre line swept into a polygon tapered at both ends.
    private func ribbon(_ pts: [CGPoint], width: Double) -> Path {
        var dense = [CGPoint]()
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(i - 1, 0)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(i + 2, pts.count - 1)]
            for k in 0..<8 {
                let t = Double(k) / 8, t2 = t * t, t3 = t2 * t
                func f(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
                    0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
                }
                dense.append(CGPoint(x: f(p0.x, p1.x, p2.x, p3.x), y: f(p0.y, p1.y, p2.y, p3.y)))
            }
        }
        dense.append(pts[pts.count - 1])
        var left = [CGPoint](), right = [CGPoint]()
        for (i, pt) in dense.enumerated() {
            let prev = dense[max(i - 1, 0)], next = dense[min(i + 1, dense.count - 1)]
            var nx = -(next.y - prev.y), ny = next.x - prev.x
            let len = max(hypot(nx, ny), 0.001)
            nx /= len; ny /= len
            let u = Double(i) / Double(dense.count - 1)
            let w = width * 0.5 * (pow(max(sin(.pi * u), 0), 0.55) * 0.92 + 0.08)
            left.append(CGPoint(x: pt.x + nx * w, y: pt.y + ny * w))
            right.append(CGPoint(x: pt.x - nx * w, y: pt.y - ny * w))
        }
        var path = Path()
        path.move(to: left[0])
        for pt in left.dropFirst() { path.addLine(to: pt) }
        for pt in right.reversed() { path.addLine(to: pt) }
        path.closeSubpath()
        return path
    }

    private func fire(_ c: GraphicsContext, _ mirrored: Bool) {
        let level = pose.fireLevel
        guard level > 0.03 else { return }
        let pc = pupilCenter(mirrored)
        // The flames are NOT mirrored between the eyes (same hook on the same side),
        // so x offsets flip with the mirrored eye frame.
        let sgn = mirrored ? -1.0 : 1.0
        let step = Int(floor((pose.frame - 112) / 2))          // flames animate at 15 fps like the clip
        let top = pose.fireTop
        let body = pose.frame < 125 ? min(1, level * 1.7) : max(0, 1 - (pose.frame - 125) / 4.5)
        let wisp = min(1, level * 2.2)
        let pupilTop = pc.y - pupilRY

        func shapes(_ l: GraphicsContext, core: Bool) {
            var rng = RNG(step * 7919 + (mirrored ? 104729 : 0) + 17)
            func X(_ dx: Double) -> Double { pc.x + sgn * dx }

            // 1. flame mass inside the pupil, ragged top edge at `fireTop`
            if body > 0.02 {
                var b = l
                b.clip(to: ellipse(pc.x, pc.y, pupilRX, pupilRY))
                let edge = max(top, pupilTop - 4)
                var poly = Path()
                poly.move(to: CGPoint(x: pc.x - pupilRX - 14, y: pc.y + pupilRY + 14))
                for dx in stride(from: -pupilRX - 14, through: pupilRX + 14, by: 13) {
                    poly.addLine(to: CGPoint(x: pc.x + dx, y: edge + rng.range(-8, 20)))
                }
                poly.addLine(to: CGPoint(x: pc.x + pupilRX + 14, y: pc.y + pupilRY + 14))
                poly.closeSubpath()
                b.fill(poly, with: .color(fireDeep.opacity(min(1, body * 1.1))))
                let span = max(20, pc.y + pupilRY - edge)
                func place(_ count: Int, _ rMin: Double, _ rMax: Double, _ color: Color, _ alpha: Double, _ tall: Double) {
                    for _ in 0..<count {
                        let x = pc.x + rng.range(-0.85, 0.85) * pupilRX
                        let y = edge + 6 + rng.range(0, 1) * (span - 10)
                        b.fill(ragged(&rng, x, y, rng.range(rMin, rMax), tall), with: .color(color.opacity(alpha * min(1, body * 1.5))))
                    }
                }
                place(6 + Int(body * 14), 8, 19, fireRed, 0.95, 1.5)
                place(5 + Int(body * 12), 6, 15, fireOrange, 0.95, 1.6)
                if core { place(4 + Int(body * 16), 5, 13, fireYellow, 0.98, 1.8) }
                // flame tongues leaving the top of the mass
                if top < pupilTop + 30 {
                    var up = l
                    for _ in 0..<(3 + Int(level * 5)) {
                        let x = pc.x + rng.range(-0.7, 0.7) * pupilRX
                        let yBase = pupilTop + 28
                        let tip = top + rng.range(0, 0.45) * (yBase - top)
                        let rx = rng.range(8, 15)
                        let blob = ragged(&rng, x, (yBase + tip) / 2, rx, max(1, (yBase - tip) / (2 * rx)))
                        up.fill(blob, with: .color(fireRed.opacity(0.92 * body)))
                        if core { up.fill(ragged(&rng, x, (yBase + tip) / 2 + 8, rx * 0.5, max(1, (yBase - tip) / (2.6 * rx))), with: .color(fireOrange.opacity(0.9 * body))) }
                    }
                }
            }

            // 2. curly ribbons and scattered blobs (positions measured on frames 128-133)
            if wisp > 0.05 && top < 345 {
                let bt = pc.y - 28
                let h = max(40, bt - (top + 6))
                // the hooked "?" ribbon on the outer-right of each eye
                let q = [CGPoint(x: X(110), y: bt), CGPoint(x: X(114 + rng.range(-4, 4)), y: bt - 0.33 * h),
                         CGPoint(x: X(108), y: bt - 0.62 * h), CGPoint(x: X(104), y: bt - 0.82 * h),
                         CGPoint(x: X(96), y: bt - 0.95 * h), CGPoint(x: X(82), y: bt - h),
                         CGPoint(x: X(70), y: bt - 0.9 * h)]
                l.fill(ribbon(q, width: 18 * wisp), with: .color(fireRed.opacity(0.95)))
                if core && level > 0.25 {
                    l.fill(ribbon(Array(q[3...]), width: 6 * wisp), with: .color(fireYellow.opacity(0.95)))
                }
                // left group: a wavy ribbon
                let h2 = max(30, bt - (top + 70))
                let lft = [CGPoint(x: X(-66), y: bt + 6), CGPoint(x: X(-82 + rng.range(-5, 5)), y: bt - 0.3 * h2),
                           CGPoint(x: X(-70), y: bt - 0.55 * h2), CGPoint(x: X(-86), y: bt - 0.8 * h2),
                           CGPoint(x: X(-76), y: bt - h2)]
                l.fill(ribbon(lft, width: 16 * wisp), with: .color(fireRed.opacity(0.95)))
                if core && level > 0.3 {
                    l.fill(ribbon(Array(lft[1...3]), width: 4.5 * wisp), with: .color(fireYellow.opacity(0.95)))
                }
                // chunky cluster of the left group with a yellow streak
                for _ in 0..<(3 + Int(level * 6)) {
                    let y = bt - rng.range(0.1, 0.9) * h2
                    l.fill(ragged(&rng, X(rng.range(-95, -55)), y, rng.range(7, 14) * (0.6 + wisp * 0.5), 1.7),
                           with: .color(fireRed.opacity(0.92)))
                }
                if core && level > 0.3 {
                    l.fill(ragged(&rng, X(-84), bt - 0.55 * h2, 4.5, 3.6), with: .color(fireYellow.opacity(0.95)))
                }
                // scattered blobs around both groups
                for _ in 0..<(6 + Int(level * 30)) {
                    let group = rng.next() < 0.5
                    let x = X(group ? rng.range(-125, -25) : rng.range(45, 135))
                    let y = bt - rng.range(0, 1) * rng.range(0.3, 1) * (group ? h2 : h)
                    l.fill(ragged(&rng, x, y, rng.range(4, 11) * (0.6 + wisp * 0.5), 1.6), with: .color(fireRed.opacity(0.9)))
                }
            }

            // 3. embers
            for _ in 0..<Int(pose.embers * 16) {
                let x = pc.x + rng.range(-115, 115)
                let y = rng.range(top - 5, pc.y - 40)
                l.fill(ellipse(x, y, rng.range(1.5, 3.5), rng.range(2.5, 6)), with: .color(fireRed.opacity(0.9)))
            }
        }
        c.drawLayer { l in
            l.addFilter(.blur(radius: 8))
            l.blendMode = .plusLighter
            l.opacity = 0.8
            shapes(l, core: false)
        }
        c.drawLayer { l in shapes(l, core: true) }
    }
}

#Preview("Looking for eyes") {
    LookingForEyesView()
        .frame(width: 360, height: 640)
}

#Preview("Squint frame 40") {
    LookingForEyesView(fixedTime: 39.0 / 30.0)
        .frame(width: 360, height: 640)
}
