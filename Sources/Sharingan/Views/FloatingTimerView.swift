import SwiftUI
import SharinganCore

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Pausing the schedule freezes the ambient waves at a static level while
        // still showing the fill; drag-driven slosh remains as direct feedback.
        TimelineView(.animation(paused: reduceMotion)) { ctx in
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
    @State private var animateDot = false
    @State private var phasePulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var themeColors: [Color] { timer.settings.theme.gradient }
    private var phaseColors: [Color] { timer.phase.gradient }

    var body: some View {
        // The panel is resizable; the card fills it (minus a small margin so
        // the flash glow isn't clipped) and its contents scale with the size.
        // When tall enough, the active task is shown below the clock.
        GeometryReader { geo in
            let inset: CGFloat = 6
            let cardW = max(0, geo.size.width - inset * 2)
            let cardH = max(0, geo.size.height - inset * 2)
            card(width: cardW, height: cardH)
                .frame(width: cardW, height: cardH)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .onAppear { animate = true }
        .onChange(of: timer.isFlashing) { animate = timer.isFlashing }
        .onChange(of: timer.phase) {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.5)) { phasePulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { phasePulse = false }
            }
        }
    }

    @ViewBuilder
    private func card(width: CGFloat, height: CGFloat) -> some View {
        // Everything scales off the panel, not fixed points: the clock tracks
        // both axes (so a wide-but-short pill doesn't strand a tiny clock in
        // empty glass), and a wide aspect flips to a side-by-side layout.
        let wide = width > height * 2.3
        let timeSize = wide
            ? min(max(height * 0.52, 20), 110)
            : min(max(min(height * 0.38, width * 0.24), 20), 110)
        // Content is user-configurable: the time is always shown; dots, the
        // task pill and the transport buttons follow their Settings toggles
        // (task also needs the room).
        let showDots = timer.settings.floatingShowDots
        let showTodo = timer.settings.floatingShowTask
            && (wide ? height >= 64 : height >= 104)
        let showControls = timer.settings.floatingShowControls
        let corner = min(DS.Radius.xl, height * 0.22)

        Group {
            if wide {
                HStack(spacing: max(14, width * 0.05)) {
                    // The clock wins the width fight: with the transport strip
                    // on, a narrow pill would otherwise crush it to "…" while
                    // the task pill kept its full title.
                    clock(timeSize)
                        .layoutPriority(2)
                    if showDots || showTodo {
                        VStack(alignment: .leading, spacing: max(6, height * 0.08)) {
                            if showDots { cycleDots(size: max(5, timeSize * 0.16)) }
                            if showTodo { activeTaskRow(scale: timeSize / 54) }
                        }
                    }
                    if showControls {
                        Spacer(minLength: 8)
                        controls(scale: timeSize / 54)
                    }
                }
            } else {
                VStack(spacing: max(3, height * 0.03)) {
                    clock(timeSize)
                    if showDots { cycleDots(size: max(5, timeSize * 0.14)) }
                    if showTodo { activeTaskRow(scale: timeSize / 54).padding(.top, 3) }
                    if showControls { controls(scale: timeSize / 54).padding(.top, 4) }
                }
            }
        }
        .padding(.horizontal, max(16, width * 0.05))
        .padding(.vertical, max(10, height * 0.06))
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
        // Borderless glass: material backdrop only — no hairline ring (the
        // glassRounded stroke read as a gray border around the pill).
        // No drop shadow: on a transparent panel it rendered as a muddy gray
        // halo around the pill (the OS window shadow is off for the same
        // reason in FloatingWindowManager).
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay {
            if timer.isFlashing {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Color.white.opacity(0.9), lineWidth: 2)
                    .blur(radius: 4)
                    .opacity(animate ? 1 : 0.2)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.5).repeatForever(), value: animate)
                    .allowsHitTesting(false)
            }
        }
        .scaleEffect(phasePulse ? 1.05 : 1.0)
        // Right-click: size presets + a way home. Presets both update the
        // setting (so Settings stays in sync) and snap the panel immediately —
        // re-picking the current preset still snaps back after a manual resize.
        .contextMenu {
            ForEach(FloatingTimerSize.allCases, id: \.self) { size in
                Toggle(size.label, isOn: Binding(
                    get: { timer.settings.floatingSize == size },
                    set: { _ in
                        timer.settings.floatingSize = size
                        FloatingWindowManager.shared.apply(size: size)
                    }))
            }
            Divider()
            Button("Reset position") { FloatingWindowManager.shared.resetPosition() }
        }
    }

    private func clock(_ size: CGFloat) -> some View {
        Text(timer.settings.timeFormat.string(max(0, timer.remainingSeconds)))
            .font(.dsTimer(size))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.3), value: timer.remainingSeconds)
    }

    /// Wordless phase strip: one dot per pomodoro in the long-break round.
    /// Filled = done, breathing ring = the one in progress, hollow = ahead.
    /// During breaks the current dot rests as a half-filled pause chip, so the
    /// liquid color plus the dots tell the whole story without a label.
    @ViewBuilder
    private func cycleDots(size: CGFloat) -> some View {
        let every = max(1, timer.settings.longBreakEvery)
        let done = timer.cyclesCompletedInRound % every
        // While focusing, the active dot is the one after the finished count;
        // on a break the same dot stays highlighted (its focus just ended or
        // is about to start).
        let activeIndex = timer.phase == .focus ? done : done - 1
        let accent = phaseColors.first ?? .white

        HStack(spacing: size * 0.9) {
            ForEach(0..<every, id: \.self) { i in
                ZStack {
                    Circle().stroke(.white.opacity(i <= activeIndex || i < done ? 0.9 : 0.45),
                                    lineWidth: 1)
                    if i < done {
                        Circle().fill(.white.opacity(0.95))
                    } else if i == activeIndex {
                        Circle()
                            .fill(accent.opacity(0.95))
                            .padding(size * 0.18)
                            .opacity(animateDot && timer.isRunning && !reduceMotion ? 0.35 : 1)
                            .animation(timer.isRunning && !reduceMotion
                                       ? .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
                                       : .default, value: animateDot)
                    }
                }
                .frame(width: size, height: size)
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        .onAppear { animateDot = true }
    }

    /// Dock-widget-style transport strip: ▶︎ start (resumes a paused session),
    /// ⏸ stop (pause), ⟲ reset (the engine's stop()). Buttons disable rather
    /// than hide so the card never changes shape under the pointer; the styling
    /// mirrors DockWidgetView so the two surfaces read as one family.
    private func controls(scale: CGFloat) -> some View {
        let s = max(0.8, min(scale, 1.8))
        return HStack(spacing: 8 * s) {
            control("play.fill", scale: s, enabled: !timer.isRunning, help: "Start") {
                timer.start()
            }
            control("pause.fill", scale: s, enabled: timer.isRunning, help: "Stop") {
                timer.pause()
            }
            control("arrow.counterclockwise", scale: s, enabled: true, help: "Reset") {
                timer.stop()
            }
        }
    }

    private func control(_ symbol: String, scale s: CGFloat, enabled: Bool, help: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12 * s, weight: .bold))
                .foregroundStyle(.white.opacity(enabled ? 0.9 : 0.3))
                .frame(width: 26 * s, height: 26 * s)
                .background(Circle().fill(.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
    }

    /// The active task (or a hint), shown only when the panel is enlarged.
    /// `scale` tracks the clock size so the pill grows with the panel.
    @ViewBuilder
    private func activeTaskRow(scale: CGFloat) -> some View {
        let s = max(0.8, min(scale, 1.8))
        if let task = tasks.activeTask {
            HStack(spacing: 6 * s) {
                Circle().fill(Color(hex: tasks.color(for: task.category)))
                    .frame(width: 7 * s, height: 7 * s)
                Text(task.title)
                    .font(.system(size: 13 * s, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if timer.settings.showPomodoroBadges, task.pomodorosDone > 0 {
                    Text("🍅\(task.pomodorosDone)")
                        .font(.system(size: 10 * s, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .padding(.horizontal, 10 * s).padding(.vertical, 4 * s)
            .background(Capsule().fill(.white.opacity(0.14)))
        } else {
            Text("No task selected")
                .font(.system(size: 11 * s, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
        }
    }
}
