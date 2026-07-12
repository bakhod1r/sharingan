import SwiftUI
import SharinganCore

struct CameraIndicatorBadge: View {
    @ObservedObject var camera: CameraService
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.7), radius: 4)
                .scaleEffect(pulse ? 1.15 : 0.92)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(),
                           value: pulse)
            Text(label)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .glassCapsule(material: .regular)
        .onAppear {
            pulse = camera.isRunning
        }
        .onChange(of: camera.isRunning) { _, running in
            pulse = running
        }
    }

    private var color: Color {
        if !camera.isAuthorized { return .gray }
        if camera.isRunning { return .green }
        return .gray.opacity(0.6)
    }

    private var label: String {
        if !camera.isAuthorized { return "Camera denied" }
        if camera.isRunning { return "Camera on" }
        return "Camera off"
    }
}