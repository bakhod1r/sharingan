import SwiftUI
import SharinganCore

/// Forced-break status on the break screen: the "+mm:ss" overtime counter, the
/// "N exercises left" pill, the camera-suspended notice and the emergency hint.
struct ForcedBreakStatusView: View {
    @ObservedObject var gate: ForcedBreakGate
    @ObservedObject var validator: ExerciseValidator
    @ObservedObject var clock: TimerClock

    private static let amber = Color(red: 1.0, green: 0.71, blue: 0.28)       // #ffb547
    private static let amberText = Color(red: 1.0, green: 0.85, blue: 0.60)   // #ffd99a

    var body: some View {
        // Face-loss is time-based (no published change), so re-evaluate once a
        // second — only while this view is on screen.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(spacing: 8) {
                if gate.showsSuspendedNotice {
                    chip("Camera can't see you — forced break paused",
                         fill: .white.opacity(0.10), stroke: .white.opacity(0.25),
                         text: .white.opacity(0.85))
                } else if gate.isEngaged, !validator.isSequenceComplete {
                    if clock.isOvertime {
                        Text("+" + Self.format(clock.overtimeSeconds))
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Self.amber)
                    }
                    chip(Self.pillText(overtime: clock.isOvertime,
                                       remaining: validator.remainingExercises),
                         fill: Self.amber.opacity(0.15), stroke: Self.amber.opacity(0.5),
                         text: Self.amberText)
                }
                if gate.isEngaged || gate.showsSuspendedNotice {
                    Text("Emergency: hold Esc for 3 s")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
        }
    }

    private func chip(_ s: String, fill: Color, stroke: Color, text: Color) -> some View {
        Text(s)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(text)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(fill))
            .overlay(Capsule().stroke(stroke, lineWidth: 1))
    }

    static func pillText(overtime: Bool, remaining: Int) -> String {
        let n = "\(remaining) exercise\(remaining == 1 ? "" : "s") left to finish the break"
        return overtime ? "Time is up — " + n : n
    }

    static func format(_ seconds: TimeInterval) -> String {
        let t = max(0, Int(seconds))
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
