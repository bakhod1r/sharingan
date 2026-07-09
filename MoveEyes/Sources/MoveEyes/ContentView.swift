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

    var body: some View {
        GeometryReader { geo in
            let k = min(geo.size.width / designW, geo.size.height / designH)
            let ox = (geo.size.width - designW * k) / 2
            let oy = (geo.size.height - designH * k) / 2

            ZStack {
                Color(red: 0.035, green: 0.035, blue: 0.043)

                scene(k: k, ox: ox, oy: oy)

                if trackingEnabled {
                    MouseTrackerView(state: mouse)
                        .allowsHitTesting(false)
                }
            }
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func scene(k: CGFloat, ox: CGFloat, oy: CGFloat) -> some View {
        // dizayn-koordinatani real koordinataga o'tkazish
        let P: (CGFloat, CGFloat) -> CGPoint = { x, y in
            CGPoint(x: ox + x * k, y: oy + y * k)
        }

        ZStack {
            // karta
            RoundedRectangle(cornerRadius: 28 * k, style: .continuous)
                .fill(Color(red: 0.075, green: 0.082, blue: 0.088))
                .frame(width: 524 * k, height: 240 * k)
                .position(P(396, 305))

            // karta ichidagi qora "yuz" soyasi (o'rta-past qismi qoraroq,
            // chekkalarda kartaning kulrangi ko'rinib turadi)
            ZStack {
                Ellipse()
                    .fill(Color.black.opacity(0.68))
                    .frame(width: 440 * k, height: 210 * k)
                    .blur(radius: 26 * k)
                    .position(P(396, 362))
                // ko'zlar ostidagi qiya soya-ponalar
                Capsule()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: 150 * k, height: 46 * k)
                    .rotationEffect(.degrees(24))
                    .blur(radius: 14 * k)
                    .position(P(300, 392))
                Capsule()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: 150 * k, height: 46 * k)
                    .rotationEffect(.degrees(-24))
                    .blur(radius: 14 * k)
                    .position(P(486, 392))
            }
            .mask(
                RoundedRectangle(cornerRadius: 28 * k, style: .continuous)
                    .frame(width: 524 * k, height: 240 * k)
                    .position(P(396, 305))
            )

            // sarlavha
            Text("Sharingan exercises")
                .font(.system(size: 17 * k, weight: .regular))
                .foregroundStyle(Color(red: 0.56, green: 0.56, blue: 0.58))
                .position(P(238, 220))

            // taymer pill
            HStack(spacing: 6 * k) {
                Text("Time Left:")
                    .foregroundStyle(Color(red: 0.52, green: 0.52, blue: 0.55))
                Text("04:50")
                    .foregroundStyle(Color.white)
            }
            .font(.system(size: 15 * k, weight: .medium))
            .padding(.horizontal, 14 * k)
            .padding(.vertical, 7 * k)
            .background(
                Capsule().fill(Color(red: 0.10, green: 0.11, blue: 0.125))
            )
            .position(P(586, 219))

            // ko'zlar (video nisbati ~2.1:1 — yassi badam shakl)
            EyeView(
                size: CGSize(width: 200 * k, height: 95 * k),
                mirrored: false,
                eyeCenter: P(252, 312),
                mouse: mouse
            )
            .position(P(252, 312))

            EyeView(
                size: CGSize(width: 200 * k, height: 95 * k),
                mirrored: true,
                eyeCenter: P(534, 312),
                mouse: mouse
            )
            .position(P(534, 312))
        }
    }
}
