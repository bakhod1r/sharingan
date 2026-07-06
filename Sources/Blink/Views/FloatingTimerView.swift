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

/// A body of water filling `rect` from the bottom up to `progress`. The surface
/// is a SUM of several sine waves at incommensurate wavelengths and speeds, so it
/// never visibly repeats and reads like real water rather than a single ripple.
/// `time` drives the motion; `tilt` leans the surface when the window is dragged.
struct WaterShape: Shape {
    var progress: Double
    var time: Double
    var amplitude: CGFloat
    var tilt: CGFloat
    /// Phase offset so stacked layers don't move in lockstep.
    var seed: Double = 0

    // Interpolate the water level and tilt so changes glide rather than jump.
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(progress, Double(tilt)) }
        set { progress = newValue.first; tilt = CGFloat(newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let clamped = max(0, min(1, progress))
        // A little headroom so even a full timer shows a moving surface.
        let level = Double(rect.height) * (1 - clamped * 0.94) - 2
        let a = Double(amplitude)
        let steps = 64
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: CGFloat(level)))
        for i in 0...steps {
            let rel = Double(i) / Double(steps)
            let x = rect.minX + rect.width * CGFloat(rel)
            // Three components: a primary ripple, a shorter chop, and a slow swell.
            let s1 = sin(rel * .pi * 2.0 + time * 1.05 + seed) * a
            let s2 = sin(rel * .pi * 3.3 - time * 0.72 + seed * 1.7) * a * 0.45
            let s3 = sin(rel * .pi * 1.15 + time * 0.4) * a * 0.7
            let wave = s1 + s2 + s3
            let tiltOffset = (rel - 0.5) * Double(tilt) * Double(rect.height) * 0.35
            p.addLine(to: CGPoint(x: x, y: CGFloat(level + wave + tiltOffset)))
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Layered waves tinted by the phase color, giving the liquid depth. Waves grow
/// with the slosh so a faster drag makes bigger, more natural swells.
private struct LiquidFill: View {
    var progress: Double
    var tilt: CGFloat
    var colors: [Color]

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            // Calmer at rest, choppier while sloshing.
            let amp = 2.6 + abs(tilt) * 6.0
            let back = colors.last ?? .blue
            let front = colors.first ?? .blue
            ZStack {
                // Back layer — darker, slower, for depth.
                WaterShape(progress: progress, time: t * 0.8,
                           amplitude: amp * 0.8, tilt: tilt * 0.6, seed: 2.1)
                    .fill(
                        LinearGradient(colors: [back.opacity(0.85), front.opacity(0.45)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .opacity(0.5)
                // Front layer — the main body.
                WaterShape(progress: progress, time: t,
                           amplitude: amp, tilt: tilt, seed: 0)
                    .fill(
                        LinearGradient(colors: [front.opacity(0.9), back.opacity(0.75)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .opacity(0.75)
                // Soft meniscus highlight riding the front surface.
                WaterShape(progress: progress, time: t,
                           amplitude: amp, tilt: tilt, seed: 0)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    .blur(radius: 0.5)
            }
        }
    }
}

struct FloatingTimerView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var motion = FloatingMotion.shared
    @ObservedObject private var tasks = TaskStore.shared
    @State private var animate = false
    @State private var phasePulse = false

    private var themeColors: [Color] { timer.settings.theme.gradient }
    private var phaseColors: [Color] { timer.phase.gradient }

    var body: some View {
        // The panel is resizable; the card fills it (minus a margin for the
        // shadow) and its contents scale with the size. When tall enough, the
        // active task is shown below the clock.
        GeometryReader { geo in
            let inset: CGFloat = 14
            let cardW = max(0, geo.size.width - inset * 2)
            let cardH = max(0, geo.size.height - inset * 2)
            card(width: cardW, height: cardH)
                .frame(width: cardW, height: cardH)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .onAppear { animate = true }
        .onChange(of: timer.isFlashing) { _ in animate = timer.isFlashing }
        .onChange(of: timer.phase) { _ in
            withAnimation(.spring(response: 0.26, dampingFraction: 0.5)) { phasePulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { phasePulse = false }
            }
        }
    }

    @ViewBuilder
    private func card(width: CGFloat, height: CGFloat) -> some View {
        let remaining = max(0, timer.remainingSeconds)
        let showTodo = height >= 104
        let timeSize = min(max(height * 0.34, 20), 54)
        let corner = min(22, height * 0.22)

        VStack(spacing: 3) {
            Text(timer.settings.timeFormat.string(remaining))
                .font(.system(size: timeSize, weight: .semibold,
                              design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.3), value: remaining)
            Text(timer.phase.label.uppercased())
                .font(.system(size: max(9, timeSize * 0.3), weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)

            if showTodo { activeTaskRow.padding(.top, 3) }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(width: width, height: height)
        .background {
            ZStack {
                LinearGradient(colors: themeColors,
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .opacity(0.28)
                LiquidFill(progress: timer.progress, tilt: motion.tilt, colors: phaseColors)
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
        .glassRounded(corner, material: .regular)
        .overlay {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(
                    LinearGradient(colors: [Color.white.opacity(0.5),
                                             themeColors.last ?? Color.white.opacity(0.2)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1)
                .allowsHitTesting(false)
        }
        .liquidShadow(radius: 14, y: 8)
        .overlay {
            if timer.isFlashing {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Color.white.opacity(0.9), lineWidth: 2)
                    .blur(radius: 4)
                    .opacity(animate ? 1 : 0.2)
                    .animation(.easeInOut(duration: 0.5).repeatForever(), value: animate)
                    .allowsHitTesting(false)
            }
        }
        .scaleEffect(phasePulse ? 1.05 : 1.0)
    }

    /// The active task (or a hint), shown only when the panel is enlarged.
    @ViewBuilder
    private var activeTaskRow: some View {
        if let task = tasks.activeTask {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: tasks.color(for: task.category)))
                    .frame(width: 7, height: 7)
                Text(task.title)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if task.pomodorosDone > 0 {
                    Text("🍅\(task.pomodorosDone)")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(.white.opacity(0.14)))
        } else {
            Text("No task selected")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
        }
    }
}
