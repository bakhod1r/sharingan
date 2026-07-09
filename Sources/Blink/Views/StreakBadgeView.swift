import SwiftUI
import BlinkCore

struct StreakBadgeView: View {
    let streak: StreakStore

    private var earned: [StreakBadge] { StreakBadge.earned(forStreak: streak.currentStreak) }
    private var next: StreakBadge? { StreakBadge.next(forStreak: streak.currentStreak) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 18, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .orange)
                Text("\(streak.currentStreak) day streak")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("Best: \(streak.longestStreak)")
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
            }

            if let nm = next {
                progressCard(next: nm)
            }

            if !earned.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(earned, id: \.id) { badge in
                            badgeChip(badge)
                        }
                    }
                }
            }
        }
        .padding(14)
        .glassRounded(22, material: .regular)
        .liquidShadow(radius: 12, y: 6)
    }

    private func progressCard(next: StreakBadge) -> some View {
        let pct = min(1, Double(streak.currentStreak) / Double(next.days))
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(next.emoji).font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(next.title) — \(next.subtitle)")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                    Text("\(max(0, next.days - streak.currentStreak)) days to go")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.68))
                }
            }
            // Fill width is a fraction of the *actual* track width — a hardcoded
            // 240pt only lined up at one specific card size.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(LinearGradient(colors: [.orange, .yellow],
                                                  startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(3, geo.size.width * pct))
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .glassRounded(16, material: .thin)
    }

    private func badgeChip(_ b: StreakBadge) -> some View {
        HStack(spacing: 6) {
            Text(b.emoji)
            Text(b.title)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .glassCapsule(material: .regular)
    }
}