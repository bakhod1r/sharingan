import SwiftUI

struct CountdownRing: View {
    var progress: Double
    var colors: [Color]
    var lineWidth: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: max(0.001, progress))
                    .stroke(
                        AngularGradient(colors: colors + [colors.first ?? .white],
                                        center: .center),
                        style: StrokeStyle(lineWidth: lineWidth,
                                           lineCap: .round, lineJoin: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: colors.first?.opacity(0.55) ?? .clear,
                            radius: 16, x: 0, y: 0)
                    // No per-tick glide: a 1 s linear animation restarted every
                    // second kept SwiftUI rendering frames for the whole session
                    // (~15% CPU). One step is 1/1500 of the ring — invisible.
            }
            .frame(width: size, height: size)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}