import SwiftUI
import BlinkCore

struct StreakRewardBanner: View {
    @ObservedObject var center: StreakRewardCenter
    @State private var show = false

    var body: some View {
        if let reward = center.pendingReward {
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    Text(reward.badge.emoji)
                        .font(.system(size: 48))
                        .scaleEffect(show ? 1.0 : 0.4)
                        .opacity(show ? 1 : 0)
                        .rotationEffect(.degrees(show ? 0 : -25))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(reward.badge.title)
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundStyle(.white)
                        Text(reward.badge.subtitle)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
                .background(
                    LinearGradient(colors: [.orange, .yellow],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .opacity(0.85)
                )
                .glassRounded(DS.Radius.xl, material: .regular)
                .liquidShadow(color: .orange.opacity(0.6), radius: 22, y: 10)
                .overlay { if show { ConfettiBurst() } }

                Button {
                    withAnimation(.spring(response: 0.4)) { show = false }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        center.dismiss()
                    }
                } label: {
                    Text("Awesome!")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28).padding(.vertical, 10)
                        .glassCapsule(material: .regular)
                }
                .buttonStyle(.pressableSubtle)
                .scaleEffect(show ? 1 : 0.8)
                .opacity(show ? 1 : 0)
            }
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    show = true
                }
            }
        }
    }
}

/// A one-shot radial confetti pop for the milestone banner.
private struct ConfettiBurst: View {
    @State private var go = false
    private let pieces = 22
    private let palette: [Color] = [.orange, .yellow, .pink, .white, .green, .cyan]

    var body: some View {
        ZStack {
            ForEach(0..<pieces, id: \.self) { i in
                let angle = Double(i) / Double(pieces) * 2 * .pi
                let dist: CGFloat = go ? CGFloat(80 + (i % 5) * 14) : 0
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(palette[i % palette.count])
                    .frame(width: 6, height: 9)
                    .rotationEffect(.degrees(go ? Double(i) * 47 : 0))
                    .offset(x: cos(angle) * dist,
                            y: sin(angle) * dist + (go ? 40 : 0))
                    .opacity(go ? 0 : 1)
                    .scaleEffect(go ? 0.5 : 1)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.95)) { go = true }
        }
        .allowsHitTesting(false)
    }
}