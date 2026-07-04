import SwiftUI
import BlinkCore

struct EyeExerciseAnimation: View {
    @State private var orbitAngle: Double = 0
    @State private var gazeAngle: Double = 0
    @State private var eyelidOpen: CGFloat = 1.0
    @State private var phase: Phase = .gaze
    @State private var gazeStep = 0

    enum Phase { case gaze, blink, rest }

    private let gazeDirections: [Double] = [
        0,            // center
        -90,          // up
        0,            // center
        90,           // right
        0,            // center
        90,           // down
        0,            // center
        -90,          // left
        0,            // center
        -45,          // up-right
        135,          // down-left
        -135,         // up-left
        45,           // down-right
    ]

    var body: some View {
        ZStack {
            LiquidMeshBackground(colors: [.paletteBreakStart.opacity(0.3),
                                           .paletteBreakEnd.opacity(0.2)])
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            VStack(spacing: 24) {
                almondEye
                instructionLabel
            }
        }
        .frame(width: 280, height: 280)
        .onAppear { startAnimation() }
        .onDisappear { stopAnimation() }
    }

    // MARK: - Almond eye

    private var almondEye: some View {
        ZStack {
            // Eye outline (almond shape)
            AlmondEyeShape()
                .stroke(Color.white.opacity(0.25), lineWidth: 3)
                .frame(width: 200, height: 120)

            AlmondEyeShape()
                .fill(Color.black.opacity(0.15))
                .frame(width: 200, height: 120)

            // Iris — fixed size, never touched
            iris
                .frame(width: 56, height: 56)
                .offset(x: gazeOffset.width,
                        y: gazeOffset.height)
                .animation(.easeInOut(duration: 0.8), value: gazeStep)

            // Orbiting ring around iris — doesn't touch iris
            orbitRing
                .frame(width: 90, height: 90)
                .offset(x: gazeOffset.width,
                        y: gazeOffset.height)
                .rotationEffect(.degrees(orbitAngle))
                .animation(.linear(duration: 2.5).repeatForever(autoreverses: false),
                           value: orbitAngle)

            // Eyelid overlay for blink
            Rectangle()
                .fill(Color.black.opacity(0.95))
                .frame(width: 210, height: 130)
                .clipShape(AlmondEyeShape())
                .scaleEffect(y: 1.0 - eyelidOpen, anchor: .center)
                .animation(.easeInOut(duration: 0.15), value: eyelidOpen)
                .allowsHitTesting(false)
        }
    }

    private var iris: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(colors: [
                        Color(red: 0.15, green: 0.45, blue: 0.85),
                        Color(red: 0.08, green: 0.25, blue: 0.55),
                        Color(red: 0.03, green: 0.12, blue: 0.35),
                    ], center: .center, startRadius: 0, endRadius: 28)
                )
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
            // Pupil
            Circle()
                .fill(Color.black)
                .frame(width: 22, height: 22)
            // Glint
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 8, height: 8)
                .offset(x: -6, y: -6)
        }
        .clipShape(Circle())
        .shadow(color: .blue.opacity(0.5), radius: 6)
    }

    private var orbitRing: some View {
        ZStack {
            // Faint orbit path
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
            // Orbiting dot
            Circle()
                .fill(Color.paletteBreakStart)
                .frame(width: 10, height: 10)
                .shadow(color: .paletteBreakStart.opacity(0.8), radius: 4)
                .offset(x: 45, y: 0)
        }
    }

    private var gazeOffset: CGSize {
        guard phase == .gaze else { return .zero }
        let angle = gazeDirections[gazeStep] * .pi / 180
        let radius: CGFloat = 28
        return CGSize(width: cos(angle) * radius,
                      height: sin(angle) * radius)
    }

    private var instructionLabel: some View {
        VStack(spacing: 4) {
            Text(phaseTitle)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
            Text(phaseSubtitle)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var phaseTitle: String {
        switch phase {
        case .gaze:  return "Follow the dot"
        case .blink: return "Blink"
        case .rest:  return "Rest"
        }
    }

    private var phaseSubtitle: String {
        switch phase {
        case .gaze:  return "Watch the orbiting light"
        case .blink: return "Blink with the eyelid"
        case .rest:  return "Close your eyes and breathe"
        }
    }

    // MARK: - Animation cycle

    private func startAnimation() {
        orbitAngle = 360
        advanceGaze()
    }

    private func advanceGaze() {
        guard phase == .gaze else { return }
        if gazeStep < gazeDirections.count - 1 {
            gazeStep += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                self.advanceGaze()
            }
        } else {
            phase = .blink
            gazeStep = 0
            runBlinkCycle()
        }
    }

    private func runBlinkCycle() {
        eyelidOpen = 0.0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.eyelidOpen = 1.0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.eyelidOpen = 0.0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.eyelidOpen = 1.0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.eyelidOpen = 0.0
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            self.eyelidOpen = 1.0
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                self.phase = .rest
                                self.runRest()
                            }
                        }
                    }
                }
            }
        }
    }

    private func runRest() {
        eyelidOpen = 0.0
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.eyelidOpen = 1.0
            self.phase = .gaze
            self.gazeStep = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.advanceGaze()
            }
        }
    }

    private func stopAnimation() {
        phase = .gaze
        gazeStep = 0
        eyelidOpen = 1.0
    }
}