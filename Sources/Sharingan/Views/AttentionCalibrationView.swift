import SwiftUI

@MainActor
final class AttentionCalibrationModel: ObservableObject {
    enum Phase: Equatable { case intro, target(Int), done, failed(String) }
    @Published var phase: Phase = .intro

    /// Centre first, then the four corners clockwise (unit coordinates).
    static let targets: [CGPoint] = [
        CGPoint(x: 0.5, y: 0.5),
        CGPoint(x: 0.08, y: 0.08), CGPoint(x: 0.92, y: 0.08),
        CGPoint(x: 0.92, y: 0.92), CGPoint(x: 0.08, y: 0.92),
    ]
}

/// Black full-screen canvas with one red dot at a time. Esc cancels (handled
/// by the panel).
struct AttentionCalibrationView: View {
    @ObservedObject var model: AttentionCalibrationModel

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                switch model.phase {
                case .intro:
                    message("Calibration", sub: "Look at each red dot · keep your head still")
                case .target(let i):
                    Circle()
                        .fill(Color(red: 1, green: 0.18, blue: 0.23))
                        .frame(width: 28, height: 28)
                        .shadow(color: .red.opacity(0.7), radius: 14)
                        .position(x: geo.size.width * Self.point(i).x,
                                  y: geo.size.height * Self.point(i).y)
                        .animation(.easeInOut(duration: 0.35), value: i)
                    VStack {
                        Spacer()
                        Text("Look at the red dot · keep your head still")
                            .font(.dsCallout)
                            .foregroundStyle(.white.opacity(0.7))
                        Text("\(i + 1) / \(AttentionCalibrationModel.targets.count) · Esc to cancel")
                            .font(.dsMicro)
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.bottom, 40)
                    }
                case .done:
                    message("Done ✓", sub: "Your screen area is saved.")
                case .failed(let why):
                    message("Couldn't calibrate", sub: why)
                }
            }
        }
        .ignoresSafeArea()
    }

    private static func point(_ i: Int) -> CGPoint {
        AttentionCalibrationModel.targets[min(max(i, 0), AttentionCalibrationModel.targets.count - 1)]
    }

    private func message(_ title: String, sub: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.dsDisplay)
            Text(sub).font(.dsBody).opacity(0.7)
        }
        .foregroundStyle(.white)
    }
}
