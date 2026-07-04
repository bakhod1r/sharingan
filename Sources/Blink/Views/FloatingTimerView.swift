import SwiftUI
import BlinkCore

struct FloatingTimerView: View {
    @ObservedObject var timer: PomodoroTimer
    @State private var animate = false

    private var themeColors: [Color] { timer.settings.theme.gradient }
    private var phaseColors: [Color] { timer.phase.gradient }

    var body: some View {
        let remaining = max(0, timer.remainingSeconds)

        VStack(spacing: 2) {
            Text(timer.settings.timeFormat.string(remaining))
                .font(.system(size: 30, weight: .semibold,
                              design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .shadow(color: themeColors.first ?? .white.opacity(0.4),
                        radius: 4, y: 1)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(timer.phase.label.uppercased())
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(themeColors.first ?? .white)
                .lineLimit(1)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .frame(minWidth: 132)
        .background(
            LinearGradient(colors: themeColors,
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
                .opacity(0.55)
        )
        .glassRounded(20, material: .regular)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(colors: [Color.white.opacity(0.5),
                                             themeColors.last ?? Color.white.opacity(0.2)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing),
                    lineWidth: 1)
                .allowsHitTesting(false)
        }
        .liquidShadow(radius: 14, y: 8)
        .overlay {
            Circle()
                .trim(from: 0, to: max(0.001, timer.progress))
                .stroke(
                    AngularGradient(colors: phaseColors + [phaseColors.first ?? .white],
                                    center: .center),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(4)
                .allowsHitTesting(false)
        }
        .overlay {
            if timer.isFlashing {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.9), lineWidth: 2)
                    .blur(radius: 4)
                    .opacity(animate ? 1 : 0.2)
                    .animation(.easeInOut(duration: 0.5).repeatForever(), value: animate)
                    .allowsHitTesting(false)
            }
        }
        .onAppear { animate = true }
        .onChange(of: timer.isFlashing) { _ in animate = timer.isFlashing }
        // Transparent margin so the card's rounded shadow isn't clipped by the
        // window edge (which is what made the rectangle appear).
        .padding(16)
        .fixedSize()
    }
}