import SwiftUI

/// Badam (leaf) shaklidagi ko'z konturi. Birlik kvadratda chiziladi,
/// `mirrored` o'ng ko'z uchun gorizontal aks ettiradi.
struct EyeShape: Shape {
    var mirrored = false

    // Chap ko'z uchun birlik-koordinatalar (videodan o'lchab olingan):
    // tashqi uch — chap tepada, ichki uch — o'ngda pastroq.
    static let outerTip = CGPoint(x: 0.00, y: 0.06)
    static let innerTip = CGPoint(x: 1.00, y: 0.94)

    func path(in rect: CGRect) -> Path {
        var p = upperLidPath(in: rect)
        let b = Self.innerTip
        let a = Self.outerTip
        // pastki qovoq: ichki uch yaqinida deyarli tekis, o'rtada eng chuqur
        p.addCurve(
            to: pt(a, rect),
            control1: pt(CGPoint(x: 0.52, y: 1.08), rect),
            control2: pt(CGPoint(x: 0.07, y: 0.86), rect)
        )
        _ = b
        p.closeSubpath()
        return p
    }

    /// Faqat ustki qovoq egri chizig'i — qalin qora chiziq va highlight uchun.
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

    /// Pastki qovoq egri chizig'i (ichki uchdan tashqi uchga).
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

    var body: some View {
        let w = size.width
        let h = size.height
        // oq maydon (sklera) tashqi qora uch hisobiga torroq va sal tepada
        let sw = 0.90 * w
        let sh = 0.96 * h
        let scleraDX = (mirrored ? -1 : 1) * (w - sw) / 2
        let irisD = 0.52 * sh
        let offset = irisOffset(w: w, h: h)
        let shape = EyeShape(mirrored: mirrored)

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
                // tinch holatda iris sklera markazidan sal pastda, burun tomonda turadi
                .offset(
                    x: (mirrored ? -1 : 1) * 0.025 * sw + offset.x,
                    y: 0.08 * sh + offset.y
                )
                .animation(.interpolatingSpring(stiffness: 140, damping: 18), value: offset)
            }
            .frame(width: sw, height: sh)
            .clipShape(shape)
            .offset(x: scleraDX, y: -0.047 * h)

        }
        .frame(width: w, height: h)
    }

    private func irisOffset(w: CGFloat, h: CGFloat) -> CGPoint {
        guard let m = mouse.location else { return .zero }
        let dx = m.x - eyeCenter.x
        let dy = m.y - eyeCenter.y
        // to'liq burilish uchun kerak bo'ladigan masofa
        let reach: CGFloat = 420
        var nx = dx / reach
        var ny = dy / reach
        let mag = sqrt(nx * nx + ny * ny)
        if mag > 1 {
            nx /= mag
            ny /= mag
        }
        return CGPoint(x: nx * 0.30 * w, y: ny * 0.34 * h)
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
