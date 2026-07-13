import SwiftUI
import SharinganCore

/// The observable the panel and the SwiftUI island share. The manager writes,
/// the view reads.
@MainActor
final class NotchHUDModel: ObservableObject {
    /// Stamps `previousSize` on every shape change, so the view can tell an
    /// opening morph from a closing one without racing SwiftUI's `onChange`
    /// ordering. The manager is the only writer of `state`, and it writes here.
    @Published var state = NotchHUDState() {
        didSet {
            guard oldValue.size != state.size else { return }
            previousSize = oldValue.size
        }
    }
    /// The shape the island is morphing *from*.
    @Published private(set) var previousSize: NotchHUDSize = .hidden
    /// **No notch until something proves otherwise.** The whole safety argument
    /// of the HUD is "no cutout ⇒ nothing drawn and nothing hittable", so the
    /// unwritten default has to be the safe answer, not a plausible one. A
    /// 14"-MacBook-Pro fixture here would mean any path that built the view
    /// before `NotchWindowManager.refresh()` stamped the real metrics claimed a
    /// 200×37 cutout that may not exist — and the hit-test mask is cut from these
    /// numbers. `refresh()` writes the truth on install; the dev-preview block in
    /// `main.swift` sets the 14" fixture explicitly, which is the only caller
    /// that ever wanted it.
    @Published var metrics = NotchScreenMetrics.none
    /// What the island is configured to show — the ears it grows and the
    /// sections the expanded panel renders. The manager writes it from the
    /// settings, and *everything* geometric reads it from here: the view's
    /// layout, the panel's sections, and the hosting view's hit-test mask. One
    /// source, so the drawn shape and the clickable shape cannot drift apart.
    @Published var config: NotchContentConfig = .default
    @Published var progress: Double = 0
    @Published var remaining: TimeInterval = 0
    @Published var phase: PomodoroPhase = .focus
    /// The pointer is over the island *right now* — undebounced, unlike
    /// `state.hovering`, which waits out `NotchGeometry.hoverOpenDelay` before it
    /// commits. This is what the hover hairline reads: the island answers the
    /// pointer on contact instead of sitting dead for a quarter second and then
    /// exploding.
    @Published var pointerInside = false
}

/// The island: one black shape that morphs between states. It draws the notch's
/// own bottom corner radius so it reads as an extension of the hardware rather
/// than a window that appeared.
///
/// All of the motion is in `NotchMotion` — including the reason none of it can
/// paint outside `NotchGeometry.hitTest`'s mask.
struct NotchHUDView: View {
    @ObservedObject var model: NotchHUDModel
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var motion = ReduceMotionMonitor.shared

    private var layout: NotchLayout {
        NotchGeometry.layout(model.metrics, size: model.state.size, config: model.config)
    }

    /// Growing or shrinking — the whole input to the asymmetric morph.
    private var expanding: Bool {
        model.state.size.growthRank > model.previousSize.growthRank
    }

    var body: some View {
        let l = layout
        let reduce = motion.isOn
        // Placement is driven entirely by the layout rect — the same rect
        // `NotchGeometry.hitTest` masks against. Centering the island here by
        // any other means (a `.top` ZStack, say) would let the drawn shape and
        // the clickable shape drift apart the moment a state stops being
        // horizontally centered.
        ZStack(alignment: .topLeading) {
            Color.clear
            island(l, reduce: reduce)
                .frame(width: l.island.width, height: l.island.height)
                // Anticipation: a dip before the growth. Anchored to the top,
                // and never above 1.0 (see `NotchMotion.squashSpring`) — a scale
                // over 1 would push the black outside `layout.island`, over
                // menu-bar pixels the mask has already declared click-through.
                .keyframeAnimator(initialValue: 1.0,
                                  trigger: model.state.size) { view, scale in
                    view.scaleEffect(reduce ? 1 : scale, anchor: .top)
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(NotchMotion.squashScale,
                                      duration: NotchMotion.squashDown)
                        SpringKeyframe(1.0, duration: NotchMotion.squashUp,
                                       spring: NotchMotion.squashSpring)
                    }
                }
                .offset(x: l.island.minX, y: l.island.minY)
        }
        .frame(width: l.panelSize.width, height: l.panelSize.height,
               alignment: .topLeading)
        // The panel deliberately overlaps the menu bar and the notch; SwiftUI
        // would otherwise inset the content by the screen's top safe area and
        // push the island ~37pt below the rect the mask assumes it occupies.
        .ignoresSafeArea()
        // The shape's own spring: frame, corner radius and the island's
        // appearance/disappearance. Critically damped in both directions — the
        // mask does not animate, so the drawn silhouette must approach
        // `layout.island` from the inside and never overshoot it.
        .animation(NotchMotion.shape(expanding: expanding, reduceMotion: reduce),
                   value: model.state.size)
        // …and the island's height also moves *without* the shape changing: tick
        // a task off the open panel and the list — and the island sized from it —
        // is one row shorter. `state.size` is `.expanded` on both sides of that,
        // so the morph spring above never sees it; this is the spring that
        // carries it, and without it the island would snap.
        .animation(NotchMotion.resize(reduceMotion: reduce), value: model.config)
    }

    @ViewBuilder
    private func island(_ l: NotchLayout, reduce: Bool) -> some View {
        if model.state.size == .hidden {
            EmptyView()
        } else {
            IslandShape(cornerRadius: l.cornerRadius)
                .fill(.black)
                .overlay(alignment: .top) {
                    content(l, reduce: reduce)
                        // Content runs on its own clock, deliberately behind the
                        // shape's: the container grows first, then the content
                        // arrives (`NotchMotion.contentLead`). This inner
                        // animation wins over the outer one for the content
                        // subtree, which is the entire point.
                        .animation(NotchMotion.arrival(reduceMotion: reduce),
                                   value: model.state.size)
                        // One announcement replacing another leaves `size` on
                        // `.activity` throughout, so it needs its own trigger or
                        // the swap above (`.id(activity)`) would be a hard cut.
                        .animation(NotchMotion.arrival(reduceMotion: reduce),
                                   value: model.state.activity)
                }
                // Hover acknowledgement: a hairline traced on the island's own
                // silhouette, so it can only ever light pixels the island
                // already paints. Inside the clip, like everything else.
                .overlay {
                    IslandShape(cornerRadius: l.cornerRadius)
                        .stroke(Color.white.opacity(
                            model.pointerInside ? NotchMotion.hoverHairline : 0),
                                lineWidth: 1)
                        .animation(NotchMotion.hover(reduceMotion: reduce),
                                   value: model.pointerInside)
                }
                // The island's rects snap to the new state while the shape
                // springs into it, so mid-morph the content is laid out for a
                // box the shape hasn't grown into yet. Clip it to the silhouette
                // or the expanded panel's rows briefly paint over the menu bar
                // on the way open. This clip is also what makes the content's
                // overshoot safe: anything a content spring throws outside the
                // silhouette is eaten here.
                .clipShape(IslandShape(cornerRadius: l.cornerRadius))
                .transition(.opacity)
        }
    }

    /// Idle draws nothing but the shape itself.
    @ViewBuilder
    private func content(_ l: NotchLayout, reduce: Bool) -> some View {
        switch model.state.size {
        case .hidden, .idle:
            EmptyView()
        case .live:
            NotchEars(model: model, timer: timer, layout: l, reduceMotion: reduce)
                .transition(.notchContent(
                    animation: NotchMotion.departure(reduceMotion: reduce)))
        case .expanded:
            NotchExpandedPanel(model: model, timer: timer, layout: l, reduceMotion: reduce)
                .transition(.notchContent(
                    animation: NotchMotion.departure(reduceMotion: reduce)))
        case .activity:
            if let activity = model.state.activity {
                NotchActivityView(activity: activity, model: model, layout: l,
                                  reduceMotion: reduce)
                    // A second announcement arriving while the first is still up
                    // (a focus phase completing rolls straight into "Break time")
                    // never changes `state.size`, so without an identity tied to
                    // the announcement itself the icon would not re-land — the
                    // words would just swap under a static checkmark.
                    .id(activity)
                    // The announcement is *done*, not dismissed: it lifts away
                    // rather than collapsing back into the notch. (Under Reduce
                    // Motion it does not lift — it just goes.)
                    .transition(.notchContent(
                        rise: reduce ? 0 : NotchMotion.announceRise,
                        animation: NotchMotion.announceDeparture(reduceMotion: reduce)))
            }
        }
    }
}

/// The island's 2-second announcement: an icon and a line, then it collapses.
/// Sized to `layout.island` like every other content view, and pushed below the
/// hardware cutout so the camera housing never hides the line.
///
/// It has two seconds; it uses them. The icon lands with a bounce and unwinds a
/// small tilt, the line follows it in a beat later, and the pair leaves by
/// lifting out of the island (`.notchContent(rise:)` upstairs).
struct NotchActivityView: View {
    let activity: NotchActivity
    @ObservedObject var model: NotchHUDModel
    let layout: NotchLayout
    let reduceMotion: Bool

    /// Flipped in `onAppear`, which is what stages the arrival. A `.transition`
    /// on these children would never run: SwiftUI animates the transition of the
    /// outermost inserted view only, and that is this view.
    @State private var landed = false

    /// See `NotchExpandedPanel.contentTop`: `cutout` is nil only on a display
    /// with no notch, where this view is never built.
    private var contentTop: CGFloat { (model.metrics.cutout?.height ?? 0) + 4 }

    var body: some View {
        // Reduce Motion keeps the fade and drops the spring, the tilt and the
        // slide — an announcement that scales and rotates is exactly what the
        // setting is there to stop.
        let settled = landed || reduceMotion

        return HStack(spacing: 8) {
            Image(systemName: activity.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .scaleEffect(settled ? 1 : NotchMotion.announceIconScale)
                .rotationEffect(.degrees(settled ? 0 : NotchMotion.announceIconTilt))
                .opacity(landed ? 1 : 0)
                .animation(NotchMotion.announceIcon(reduceMotion: reduceMotion),
                           value: landed)

            Text(activity.message)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .opacity(landed ? 1 : 0)
                .offset(y: settled ? 0 : NotchMotion.announceTextDrift)
                .animation(NotchMotion.announceText(reduceMotion: reduceMotion),
                           value: landed)
        }
        .padding(.top, contentTop)
        .padding(.horizontal, 16)
        .frame(width: layout.island.width, height: layout.island.height,
               alignment: .top)
        .onAppear { landed = true }
    }
}

/// A rectangle whose *bottom* corners are rounded — the notch's silhouette.
/// The path itself lives in `NotchGeometry` (Core), which is also what the
/// hit-test mask is cut from: one definition, so what is drawn and what is
/// clickable are the same shape by construction.
struct IslandShape: Shape {
    var cornerRadius: CGFloat

    /// The radius grows with the island's height, so it has to *interpolate*
    /// with the morph rather than jump to the new state's value on frame one —
    /// a 14pt corner snapping to 22pt at the start of the open is exactly the
    /// snap this pass exists to remove.
    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        Path(NotchGeometry.islandPath(in: rect, cornerRadius: cornerRadius))
    }
}
