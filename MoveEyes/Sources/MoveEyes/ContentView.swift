import SwiftUI

/// Dizayn 800×600 koordinatalarda chizilgan; oyna o'lchamiga
/// proporsional masshtablanadi (letterbox bilan markazda).
struct ContentView: View {
    @StateObject private var mouse: MouseState
    private let trackingEnabled: Bool

    init(mouse: MouseState = MouseState(), trackingEnabled: Bool = true) {
        _mouse = StateObject(wrappedValue: mouse)
        self.trackingEnabled = trackingEnabled
    }

    private let designW: CGFloat = 800
    private let designH: CGFloat = 600

    /// Qovoqlar: mouse harakatda — vaqti-vaqti bilan blink, jim tursa —
    /// sekin yumilib "mudraydi", qimirlashi bilan ochiladi.
    @State private var eyelid: CGFloat = 1
    @State private var dozing = false
    @State private var nextBlink = Date().addingTimeInterval(.random(in: 2...5))
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let dozeDelay: TimeInterval = 6
    private let ticker = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let k = min(geo.size.width / designW, geo.size.height / designH)
            let ox = (geo.size.width - designW * k) / 2
            let oy = (geo.size.height - designH * k) / 2

            ZStack {
                // kulrang fon butun oyna bo'ylab
                Color(red: 0.075, green: 0.082, blue: 0.088)

                scene(k: k, ox: ox, oy: oy)

                if trackingEnabled {
                    MouseTrackerView(state: mouse)
                        .allowsHitTesting(false)
                }
            }
            .ignoresSafeArea()
        }
        .onReceive(ticker) { _ in updateEyelids() }
    }

    /// Mudrash/uyg'onish/blink sikli — Blink ilovasidagi wallpaper bilan
    /// bir xil xatti-harakat.
    private func updateEyelids() {
        let stillFor = Date().timeIntervalSince(mouse.lastMoved)
        if stillFor > dozeDelay, !dozing {
            dozing = true
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.9)) { eyelid = 0 }
        } else if stillFor <= dozeDelay, dozing {
            dozing = false
            nextBlink = Date().addingTimeInterval(.random(in: 2...5))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { eyelid = 1 }
        }
        if !reduceMotion, !dozing, Date() >= nextBlink {
            nextBlink = Date().addingTimeInterval(.random(in: 3.5...8))
            withAnimation(.easeIn(duration: 0.09)) { eyelid = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
                withAnimation(.easeOut(duration: 0.16)) {
                    if !dozing { eyelid = 1 }
                }
            }
        }
    }

    @ViewBuilder
    private func scene(k: CGFloat, ox: CGFloat, oy: CGFloat) -> some View {
        // dizayn-koordinatani real koordinataga o'tkazish
        let P: (CGFloat, CGFloat) -> CGPoint = { x, y in
            CGPoint(x: ox + x * k, y: oy + y * k)
        }

        ZStack {
            // qora "yuz" soyasi (o'rta-past qismi qoraroq,
            // chekkalarda kulrang fon ko'rinib turadi)
            Ellipse()
                .fill(Color.black.opacity(0.68))
                .frame(width: 670 * k, height: 330 * k)
                .blur(radius: 40 * k)
                .position(P(400, 420))
            // ko'zlar ostidagi qiya soya-ponalar
            Capsule()
                .fill(Color.black.opacity(0.45))
                .frame(width: 230 * k, height: 70 * k)
                .rotationEffect(.degrees(24))
                .blur(radius: 22 * k)
                .position(P(255, 455))
            Capsule()
                .fill(Color.black.opacity(0.45))
                .frame(width: 230 * k, height: 70 * k)
                .rotationEffect(.degrees(-24))
                .blur(radius: 22 * k)
                .position(P(545, 455))

            // sarlavha
            Text("Sharingan exercises")
                .font(.system(size: 26 * k, weight: .regular))
                .foregroundStyle(Color(red: 0.56, green: 0.56, blue: 0.58))
                .position(P(190, 66))

            // taymer pill
            HStack(spacing: 9 * k) {
                Text("Time Left:")
                    .foregroundStyle(Color(red: 0.52, green: 0.52, blue: 0.55))
                Text("04:50")
                    .foregroundStyle(Color.white)
            }
            .font(.system(size: 23 * k, weight: .medium))
            .padding(.horizontal, 21 * k)
            .padding(.vertical, 11 * k)
            .background(
                Capsule().fill(Color(red: 0.10, green: 0.11, blue: 0.125))
            )
            .position(P(660, 64))

            // ko'zlar (video nisbati ~2.1:1 — yassi badam shakl)
            EyeView(
                size: CGSize(width: 306 * k, height: 145 * k),
                mirrored: false,
                eyeCenter: P(180, 330),
                mouse: mouse,
                openness: eyelid
            )
            .position(P(180, 330))

            EyeView(
                size: CGSize(width: 306 * k, height: 145 * k),
                mirrored: true,
                eyeCenter: P(620, 330),
                mouse: mouse,
                openness: eyelid
            )
            .position(P(620, 330))
        }
    }
}
