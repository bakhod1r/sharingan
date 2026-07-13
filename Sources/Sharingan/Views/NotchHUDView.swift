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

    /// Filled in by a later task: activity (Task 7).
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
            EmptyView()   // Task 7
        }
    }
}

/// A rectangle whose *bottom* corners are rounded — the notch's silhouette.
struct IslandShape: Shape {
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, rect.height / 2, rect.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
