import SwiftUI
import SharinganCore

/// The observable the panel and the SwiftUI island share. The manager writes,
/// the view reads.
@MainActor
final class NotchHUDModel: ObservableObject {
    @Published var state = NotchHUDState()
    @Published var metrics = NotchScreenMetrics(screenWidth: 1512, menuBarHeight: 37,
                                                notchWidth: 200, notchHeight: 37)
    @Published var earsMode: NotchEarsMode = .both
    @Published var progress: Double = 0
    @Published var remaining: TimeInterval = 0
    @Published var phase: PomodoroPhase = .focus
}

/// The island: one black shape that morphs between states. It draws the notch's
/// own bottom corner radius so it reads as an extension of the hardware rather
/// than a window that appeared.
struct NotchHUDView: View {
    @ObservedObject var model: NotchHUDModel
    @ObservedObject var timer: PomodoroTimer

    private var layout: NotchLayout {
        NotchGeometry.layout(model.metrics, size: model.state.size)
    }

    var body: some View {
        let l = layout
        // Placement is driven entirely by the layout rect — the same rect
        // `NotchGeometry.hitTest` masks against. Centering the island here by
        // any other means (a `.top` ZStack, say) would let the drawn shape and
        // the clickable shape drift apart the moment a state stops being
        // horizontally centered.
        ZStack(alignment: .topLeading) {
            Color.clear
            island(l)
                .frame(width: l.island.width, height: l.island.height)
                .offset(x: l.island.minX, y: l.island.minY)
        }
        .frame(width: l.panelSize.width, height: l.panelSize.height,
               alignment: .topLeading)
        // The panel deliberately overlaps the menu bar and the notch; SwiftUI
        // would otherwise inset the content by the screen's top safe area and
        // push the island ~37pt below the rect the mask assumes it occupies.
        .ignoresSafeArea()
        .animation(.spring(response: 0.32, dampingFraction: 0.82),
                   value: model.state.size)
    }

    @ViewBuilder
    private func island(_ l: NotchLayout) -> some View {
        if model.state.size == .hidden {
            EmptyView()
        } else {
            IslandShape(cornerRadius: l.cornerRadius)
                .fill(.black)
                .overlay(alignment: .top) { content(l) }
                // The island's rects snap to the new state while the shape
                // springs into it over ~320ms, so mid-morph the content is
                // laid out for a box the shape hasn't grown into yet. Clip it
                // to the silhouette or the expanded panel's rows briefly paint
                // over the menu bar on the way open.
                .clipShape(IslandShape(cornerRadius: l.cornerRadius))
        }
    }

    /// Idle draws nothing but the shape itself.
    @ViewBuilder
    private func content(_ l: NotchLayout) -> some View {
        switch model.state.size {
        case .hidden, .idle:
            EmptyView()
        case .live:
            NotchEars(model: model, timer: timer, layout: l)
        case .expanded:
            NotchExpandedPanel(model: model, timer: timer, layout: l)
        case .activity:
            if let activity = model.state.activity {
                NotchActivityView(activity: activity, model: model, layout: l)
            }
        }
    }
}

/// The island's 2-second announcement: an icon and a line, then it collapses.
/// Sized to `layout.island` like every other content view, and pushed below the
/// hardware cutout so the camera housing never hides the line.
struct NotchActivityView: View {
    let activity: NotchActivity
    @ObservedObject var model: NotchHUDModel
    let layout: NotchLayout

    /// See `NotchExpandedPanel.contentTop`: `cutout` is nil only on a display
    /// with no notch, where this view is never built.
    private var contentTop: CGFloat { (model.metrics.cutout?.height ?? 0) + 4 }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: activity.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Text(activity.message)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
        }
        .padding(.top, contentTop)
        .padding(.horizontal, 16)
        .frame(width: layout.island.width, height: layout.island.height,
               alignment: .top)
        .transition(.opacity)
    }
}

/// A rectangle whose *bottom* corners are rounded — the notch's silhouette.
/// The path itself lives in `NotchGeometry` (Core), which is also what the
/// hit-test mask is cut from: one definition, so what is drawn and what is
/// clickable are the same shape by construction.
struct IslandShape: Shape {
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(NotchGeometry.islandPath(in: rect, cornerRadius: cornerRadius))
    }
}
