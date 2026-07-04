import SwiftUI
import BlinkCore

struct ExerciseSequenceView: View {
    @ObservedObject var validator: ExerciseValidator
    @ObservedObject var eyeTracker: EyeTracker

    var body: some View {
        VStack(spacing: 16) {
            header
            currentStepCard
            progressSteps
            if eyeTracker.state.faceDetected == false {
                Text("Align your face with the camera")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .transition(.opacity)
            }
            if validator.needsRetry {
                Text("Try again — your gaze is off-target")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red.opacity(0.92))
                    .transition(.opacity)
            }
        }
        .onAppear {
            validator.start()
        }
        .onDisappear { validator.stop() }
        .onReceive(eyeTracker.$state) { state in
            validator.ingest(gaze: state.gaze, isBlinking: state.isBlinking)
        }
        .animation(.easeInOut(duration: 0.25), value: eyeTracker.state.faceDetected)
        .animation(.easeInOut(duration: 0.25), value: validator.needsRetry)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.mind.and.body")
                .foregroundStyle(.white.opacity(0.85))
            Text(validator.currentExercise?.name ?? "—")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
            Spacer()
            Text("Exercise \(validator.currentExerciseIndex + 1)/\(validator.exercises.count)")
                .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .glassCapsule(material: .regular)
    }

    private var currentStepCard: some View {
        VStack(spacing: 10) {
            if let step = validator.currentStep {
                Text(step.instruction)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                Text("Remaining: \(validator.formattedHoldRemaining())")
                    .font(.system(.title2, design: .rounded).monospacedDigit().weight(.bold))
                    .foregroundStyle(stepAccent)
                gauge(for: step)
            } else {
                Text("Done ✓")
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .glassRounded(22, material: .regular)
        .liquidShadow(radius: 16, y: 8)
    }

    private func gauge(for step: BreakExerciseStep) -> some View {
        let total = step.holdSeconds
        let held = min(total, validator.heldSeconds)
        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 6)
            Circle()
                .trim(from: 0, to: max(0.001, held / max(0.001, total)))
                .stroke(
                    AngularGradient(colors: [.green, .mint, .green], center: .center),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 76, height: 76)
    }

    @ViewBuilder
    private var progressSteps: some View {
        if let ex = validator.currentExercise {
            HStack(spacing: 6) {
                ForEach(Array(ex.steps.enumerated()), id: \.offset) { idx, _ in
                    Capsule()
                        .fill(idx < validator.currentStepIndex
                              ? Color.green.opacity(0.9)
                              : (idx == validator.currentStepIndex
                                 ? Color.white.opacity(0.7)
                                 : Color.white.opacity(0.2)))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 18)
        }
    }

    private var stepAccent: Color {
        validator.needsRetry ? .red.opacity(0.92) : .white.opacity(0.92)
    }
}