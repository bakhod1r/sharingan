import SwiftUI
import BlinkCore

struct EyeExerciseAnimation: View {
    @State private var index = 0
    @State private var blinkIndex = 0
    @State private var mode: Mode = .gaze
    @State private var ticker: Timer?

    enum Mode { case gaze, blink }

    let directions = ["center", "up", "right", "down", "left",
                      "up_right", "down_left", "up_left", "down_right"]

    var body: some View {
        ZStack {
            image(mode == .gaze
                  ? "Animations/eye_\(directions[index])"
                  : "Animations/blink_\(String(format: "%02d", blinkIndex))")
                .resizable()
                .interpolation(.medium)
                .frame(width: 256, height: 256)
                .transition(.opacity)
        }
        .onAppear { start() }
        .onDisappear { stop() }
    }

    private func image(_ name: String) -> Image {
        if let url = Bundle.module.url(forResource: name, withExtension: "png"),
           let nsImage = NSImage(contentsOf: url) {
            return Image(nsImage: nsImage)
        }
        return Image(systemName: "eye")
    }

    private func start() {
        stop()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { _ in
            if mode == .gaze {
                index = (index + 1) % directions.count
                if index == 0 { mode = .blink; blinkIndex = 0 }
            } else {
                blinkIndex = (blinkIndex + 1) % 9
                if blinkIndex == 0 { mode = .gaze }
            }
        }
    }

    private func stop() {
        ticker?.invalidate()
        ticker = nil
    }
}