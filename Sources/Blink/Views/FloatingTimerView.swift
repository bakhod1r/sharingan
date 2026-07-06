import SwiftUI
import BlinkCore

/// Physics for the floating timer's liquid: a damped spring that tilts the water
/// surface when the window is dragged, so the "water" sloshes and settles.
@MainActor
final class FloatingMotion: ObservableObject {
    static let shared = FloatingMotion()

    /// Current surface tilt, roughly -1…1 (left-high … right-high).
    @Published private(set) var tilt: CGFloat = 0

    private var velocity: CGFloat = 0
    private var lastX: CGFloat?
    private var loop: Task<Void, Never>?

    /// Feed the window's latest x-origin; the change kicks the liquid.
    func moved(to x: CGFloat) {
        defer { lastX = x }
        guard let last = lastX else { return }
        let dx = x - last
        // The liquid lags behind the motion, so kick it the opposite way.
        velocity += -dx * 0.05
        velocity = max(-6, min(6, velocity))
        startLoop()
    }

    private func startLoop() {
        guard loop == nil else { return }
        loop = Task { @MainActor [weak self] in
            while !Task.isCancelled, let self {
                // Spring toward level with damping → oscillate then settle.
                let stiffness: CGFloat = 0.16
                let damping: CGFloat = 0.90
                self.velocity += -stiffness * self.tilt
                self.velocity *= damping
                self.tilt = max(-1, min(1, self.tilt + self.velocity * 0.12))
                if abs(self.tilt) < 0.001 && abs(self.velocity) < 0.001 {
                    self.tilt = 0
                    self.velocity = 0
                    break
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
            self?.loop = nil
        }
    }
}

/// A body of water filling `rect` from the bottom up to `progress`, with a sine
/// surface (animated via `phase`) that can tilt to one side (`tilt`).
struct WaterShape: Shape {
    var progress: Double
    var phase: Double
    var amplitude: CGFloat
    var tilt: CGFloat

    // Interpolate the water level and tilt so changes glide rather than jump.
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(progress, Double(tilt)) }
        set { progress = newValue.first; tilt = CGFloat(newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let clamped = max(0, min(1, progress))
        // A little headroom so even a full timer shows a moving surface.
        let level = rect.height * (1 - CGFloat(clamped) * 0.94) - 2
        let steps = 48
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: level))
        for i in 0...steps {
            let rel = CGFloat(i) / CGFloat(steps)
            let x = rect.minX + rect.width * rel
            let wave = sin(Double(rel) * .pi * 2 + phase) * Double(amplitude)
            let tiltOffset = (rel - 0.5) * tilt * rect.height * 0.35
            let y = level + CGFloat(wave) + tiltOffset
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Two offset waves stacked for depth, tinted by the phase color.
private struct LiquidFill: View {
    var progress: Double
    var tilt: CGFloat
    var colors: [Color]

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                WaterShape(progress: progress, phase: t * 1.5,
                           amplitude: 3.5, tilt: tilt)
                    .fill(
                        LinearGradient(colors: colors,
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .opacity(0.75)
                WaterShape(progress: progress, phase: t * 2.1 + .pi,
                           amplitude: 2.5, tilt: tilt * 0.7)
                    .fill(
                        LinearGradient(colors: [(colors.last ?? .blue).opacity(0.9),
                                                (colors.first ?? .blue).opacity(0.5)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .opacity(0.45)
                // Bright meniscus line on the surface.
                WaterShape(progress: progress, phase: t * 1.5,
                           amplitude: 3.5, tilt: tilt)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1.2)
                    .blur(radius: 0.4)
            }
        }
    }
}

struct FloatingTimerView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var motion = FloatingMotion.shared
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
                .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(timer.phase.label.uppercased())
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .frame(minWidth: 132)
        .background {
            // Water fills the card as the session progresses; the surface waves
            // continuously and tilts/sloshes when the window is dragged.
            ZStack {
                LinearGradient(colors: themeColors,
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .opacity(0.28)
                LiquidFill(progress: timer.progress,
                           tilt: motion.tilt,
                           colors: phaseColors)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
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
