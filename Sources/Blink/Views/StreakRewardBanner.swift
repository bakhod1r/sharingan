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
                .glassRounded(24, material: .regular)
                .liquidShadow(color: .orange.opacity(0.6), radius: 22, y: 10)

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
                .buttonStyle(.plain)
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