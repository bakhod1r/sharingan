import SwiftUI

/// Badam (leaf) shaklidagi ko'z konturi. Birlik kvadratda chiziladi,
/// `mirrored` o'ng ko'z uchun gorizontal aks ettiradi. `openness` ustki
/// qovoqni pastki kiprik chizig'iga morph qiladi (1 = ochiq, 0 = yumuq) —
/// burchak uchlari joyida qoladi, ko'z o'z o'rnida yumiladi.
struct EyeShape: Shape {
    var mirrored = false
    var openness: CGFloat = 1

    // Chap ko'z uchun birlik-koordinatalar (videodan o'lchab olingan):
    // tashqi uch — chap tepada, ichki uch — o'ngda pastroq.
    static let outerTip = CGPoint(x: 0.00, y: 0.06)
    static let innerTip = CGPoint(x: 1.00, y: 0.94)
    /// Ochiq ustki qovoq kubik nazorat nuqtalari (tashqi→ichki).
    static let upperC1 = CGPoint(x: 0.32, y: -0.10)
    static let upperC2 = CGPoint(x: 0.76, y: 0.20)
    /// Pastki qovoq nazorat nuqtalari tashqi→ichki tartibda — ayni paytda
    /// yumuq ustki qovoqning holati (openness 0 da qovoqlar ustma-ust tushadi).
    static let lowerC1 = CGPoint(x: 0.07, y: 0.86)
    static let lowerC2 = CGPoint(x: 0.52, y: 1.08)

    var animatableData: CGFloat {
        get { openness }
        set { openness = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = upperLidPath(in: rect)
        // pastki qovoq: ichki uch yaqinida deyarli tekis, o'rtada eng chuqur
        p.addCurve(
            to: pt(Self.outerTip, rect),
            control1: pt(Self.lowerC2, rect),
            control2: pt(Self.lowerC1, rect)
        )
        p.closeSubpath()
        return p
    }

    /// Faqat ustki qovoq egri chizig'i — qalin qora chiziq va highlight uchun.
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

    /// Pastki qovoq egri chizig'i (ichki uchdan tashqi uchga).
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

    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ k: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
    }

    private func pt(_ u: CGPoint, _ rect: CGRect) -> CGPoint {
        let x = mirrored ? 1 - u.x : u.x
        return CGPoint(x: rect.minX + x * rect.width, y: rect.minY + u.y * rect.height)
    }
}

/// Ochiq ko'z tuynugining birlik-fazodagi geometriyasi: berilgan gorizontal
/// x uchun tuynuk o'rta chizig'i va yarim balandligi. Bir marta hisoblanadi.
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
        let upper = (0...32).map {
            bez(EyeShape.outerTip, EyeShape.upperC1,
                EyeShape.upperC2, EyeShape.innerTip, CGFloat($0) / 32)
        }
        let lower = (0...32).map {
            bez(EyeShape.outerTip, EyeShape.lowerC1,
                EyeShape.lowerC2, EyeShape.innerTip, CGFloat($0) / 32)
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

/// Halqa bo'ylab ingichkalashib boradigan dumli tomoe (vergul) shakli.
/// Bosh — to'la doira, dumi halqa radiusi bo'ylab soat yo'nalishida su'nadi.
struct TomoeTailShape: Shape {
    var ringRadius: CGFloat      // rect markazidan halqagacha
    var headAngle: Angle         // bosh joylashgan burchak
    var sweep: Angle             // dum qamrovi (soat yo'nalishida)
    var startWidth: CGFloat      // dum boshlanish qalinligi

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

/// Qizil iris: radial gradient, markaziy qorachiq, ingichka halqa va 3 ta tomoe.
struct IrisView: View {
    var diameter: CGFloat

    var body: some View {
        let r = diameter / 2
        let ringR = 0.52 * r
        ZStack {
            // o'rta bandda yorqinroq, markaz va chetlarda to'qroq qizil
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
            // chetki to'q hoshiya
            Circle()
                .stroke(Color(red: 0.08, green: 0.0, blue: 0.0).opacity(0.9), lineWidth: 0.05 * r)
                .padding(0.02 * r)
            // tomoe orqali o'tuvchi xira to'q-qizil halqa
            Circle()
                .stroke(Color(red: 0.22, green: 0.0, blue: 0.01).opacity(0.85), lineWidth: 0.035 * r)
                .frame(width: ringR * 2, height: ringR * 2)
            // markaziy qorachiq
            Circle()
                .fill(Color.black)
                .frame(width: 0.26 * r, height: 0.26 * r)
            // 3 ta tomoe: bosh + soatga qarshi buriluvchi dum
            ForEach(0..<3, id: \.self) { i in
                let head = Angle(degrees: -80 + Double(i) * 120)
                TomoeTailShape(
                    ringRadius: ringR,
                    headAngle: head,
                    sweep: .degrees(-60),
                    startWidth: 0.20 * r
                )
                .fill(Color.black)
                Circle()
                    .fill(Color.black)
                    .frame(width: 0.28 * r, height: 0.28 * r)
                    .offset(
                        x: ringR * cos(head.radians),
                        y: ringR * sin(head.radians)
                    )
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Iris — sichqoncha tinch turganda silliq aylanadi, harakatda to'xtaydi.
struct SpinningIris: View {
    var diameter: CGFloat
    @ObservedObject var mouse: MouseState

    @AppStorage(Settings.spinEnabledKey) private var spinEnabled = true
    @AppStorage(Settings.spinDurationKey) private var spinDuration = 1.6
    @AppStorage(Settings.idleDelayKey) private var idleDelay = 1.2

    @State private var angle: Double = 0
    @State private var spinning = false
    private let ticker = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        IrisView(diameter: diameter)
            .rotationEffect(.degrees(angle))
            .onReceive(ticker) { _ in
                let idle = Date().timeIntervalSince(mouse.lastMoved) > idleDelay
                let shouldSpin = idle && spinEnabled
                if shouldSpin && !spinning {
                    spinning = true
                    withAnimation(.linear(duration: spinDuration).repeatForever(autoreverses: false)) {
                        angle += 360
                    }
                } else if !shouldSpin && spinning {
                    spinning = false
                    // repeatForever'ni to'xtatish: qiymatni animatsiyasiz muhrlash
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) {
                        angle = angle.truncatingRemainder(dividingBy: 360)
                    }
                }
            }
    }
}

/// Bitta ko'z: kontur, sklera, sichqonchaga qaraydigan iris (qovoqlar bilan kesiladi).
struct EyeView: View {
    var size: CGSize
    var mirrored: Bool
    var eyeCenter: CGPoint          // .global (oyna) koordinatalarida
    @ObservedObject var mouse: MouseState
    /// Qovoq holati: 1 = ochiq, 0 = yumuq.
    var openness: CGFloat = 1

    var body: some View {
        let w = size.width
        let h = size.height
        // oq maydon (sklera) tashqi qora uch hisobiga torroq va sal tepada
        let sw = 0.90 * w
        let sh = 0.96 * h
        let scleraDX = (mirrored ? -1 : 1) * (w - sw) / 2
        let irisD = 0.52 * sh
        let offset = irisOffset(sw: sw, sh: sh, irisD: irisD)
        let shape = EyeShape(mirrored: mirrored, openness: openness)

        ZStack {
            // qirralardagi nozik kulrang highlightlar (faqat qisman, qora ostidan)
            EyelidStroke(shape: shape, lineWidth: 0.14 * h, trimTo: 0.62)
                .fill(Color(red: 0.55, green: 0.57, blue: 0.59))
                .offset(y: -0.048 * h)
            EyelidStroke(shape: shape, lineWidth: 0.035 * h, lower: true, trimFrom: 0.22, trimTo: 0.78)
                .fill(Color(red: 0.26, green: 0.28, blue: 0.30))
                .offset(y: 0.018 * h)

            // qora qovoq asosi: shakl + qalin ustki qovoq chizig'i
            shape.fill(Color.black)
            EyelidStroke(shape: shape, lineWidth: 0.10 * h)
                .fill(Color.black)
                .offset(y: -0.028 * h)

            // sklera + iris (ko'z shakli bilan kesiladi)
            ZStack {
                shape.fill(
                    LinearGradient(
                        colors: [Color.white, Color(red: 0.93, green: 0.91, blue: 0.91)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                ZStack {
                    // iris atrofidagi pushti nur
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
                    SpinningIris(diameter: irisD, mouse: mouse)
                }
                // iris ko'z tuynugining o'rta chizig'i bo'ylab yuradi
                .offset(x: offset.x, y: offset.y)
                .animation(.interpolatingSpring(stiffness: 140, damping: 18), value: offset)
            }
            .frame(width: sw, height: sh)
            .clipShape(shape)
            .offset(x: scleraDX, y: -0.047 * h)

        }
        .frame(width: w, height: h)
    }

    /// Iris ko'zning haqiqiy tuynugi bo'ylab yuradi: gorizontalda qiya
    /// burchak zonalariga kirmaydi, vertikalda tuynuk bandi ichida qisiladi —
    /// iris hech qachon burchakka kirib yo'qolmaydi.
    private func irisOffset(sw: CGFloat, sh: CGFloat, irisD: CGFloat) -> CGPoint {
        guard let m = mouse.location else { return .zero }
        // to'liq burilish uchun kerak bo'ladigan masofa
        let reach: CGFloat = 420
        var nx = (m.x - eyeCenter.x) / reach
        var ny = (m.y - eyeCenter.y) / reach
        let mag = sqrt(nx * nx + ny * ny)
        if mag > 1 {
            nx /= mag
            ny /= mag
        }
        let uScreen = min(max(0.5 + nx * 0.20, 0.12), 0.88)
        let uShape = mirrored ? 1 - uScreen : uScreen
        let ap = EyeAperture.sample(at: uShape)
        let irisUnitR = irisD / 2 / sh
        let slack = max(0, ap.halfH - irisUnitR * 0.28)
        let baseY = EyeAperture.sample(at: 0.5).midY
        let y = min(max(baseY + ny * slack, ap.midY - slack), ap.midY + slack)
        return CGPoint(x: (uScreen - 0.5) * sw, y: (y - 0.5) * sh)
    }
}

/// Ustki qovoq egri chizig'ining stroke'ini Shape sifatida beradi
/// (fill bilan gradient/soya berish qulay bo'lishi uchun).
struct EyelidStroke: Shape {
    var shape: EyeShape
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
