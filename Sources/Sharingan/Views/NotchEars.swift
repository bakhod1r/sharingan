import SwiftUI
import SharinganCore

/// The live state: remaining time to the left of the cutout, the task (or the
/// phase) to its right, and a progress line along the island's bottom edge.
/// Ears sit in the menu bar row and overlap what's under them — hence
/// `NotchEarsMode`, which lets the user drop one or both.
struct NotchEars: View {
    @ObservedObject var model: NotchHUDModel
    @ObservedObject var tasks = TaskStore.shared
    let layout: NotchLayout

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let left = layout.leftEar, model.earsMode == .both {
                timeLabel
                    .frame(width: left.width, height: left.height)
                    .offset(x: left.minX - layout.island.minX, y: left.minY)
            }
            if let right = layout.rightEar, model.earsMode != .none {
                taskLabel
                    .frame(width: right.width, height: right.height)
                    .offset(x: right.minX - layout.island.minX, y: right.minY)
            }
            if let track = layout.progressTrack {
                NotchProgressBar(progress: model.progress, phase: model.phase,
                                 width: track.width, height: track.height)
                    .offset(x: track.minX - layout.island.minX, y: track.minY)
            }
        }
        // Pin this view's own top-left to the island's top-left explicitly.
        // The parent attaches us via `.overlay(alignment: .top)` on the island
        // shape; without a frame that matches the island exactly, an
        // auto-sized ZStack would be centered inside the island instead of
        // anchored at its origin, and every offset above (computed relative
        // to `layout.island.minX`/`.minY`) would land in the wrong place.
        .frame(width: layout.island.width, height: layout.island.height,
               alignment: .topLeading)
    }

    private var timeLabel: some View {
        Text(Self.clock(model.remaining))
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.trailing, 6)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var taskLabel: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(model.phase.gradient.first ?? .white)
                .frame(width: 6, height: 6)
            Text(tasks.activeTask?.title ?? model.phase.label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.leading, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

/// The one piece of the HUD that can never collide with anything: a hairline
/// under the island filling with the session's progress.
struct NotchProgressBar: View {
    let progress: Double
    let phase: PomodoroPhase
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let clamped = max(0, min(1, progress))
        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.12))
            Capsule()
                .fill(LinearGradient(colors: phase.gradient,
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: max(0, width * clamped))
        }
        .frame(width: width, height: height)
        .animation(.linear(duration: 0.25), value: clamped)
    }
}
