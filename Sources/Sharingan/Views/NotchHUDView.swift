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
        // Fill whatever the host proposes, pinned to the top-left, rather than
        // a fixed `l.panelSize`. The window's *height* now hugs the current
        // state (`NotchWindowManager.syncPanelFrame`), and a root view with a
        // fixed size taller than the hosting view's bounds would be *centered*
        // in them by `NSHostingView` — sliding the island, and every rect the
        // mask assumes, half the difference up the screen. Filling keeps
        // geometry (0,0) glued to the hosting view's top-left at every window
        // height; the width the manager sets is `panelSize`'s union width, so
        // the x-coordinates are unchanged. (The dev preview proposes the full
        // union `panelSize` around this view and photographs the same thing it
        // always did.)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            IslandShape(silhouette: l.silhouette)
                // The cutout span stays pure black — it is imitating the camera
                // housing. Everything the island *adds* to the hardware is
                // dressed in Blink's dark glass on top of it: the expanded
                // body below the menu bar (`bodyGlass`) and the live ears
                // either side of the cutout (`earGlass`). Idle — the cutout
                // plus its lip, nothing added — stays all black.
                .fill(.black)
                .overlay(alignment: .topLeading) { bodyGlass(l) }
                .overlay(alignment: .topLeading) { earGlass(l) }
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
                // already paints. Inside the clip, like everything else. It is
                // the theme accent, not white — hovering is interactive, not
                // phase-semantic, so it takes the app's one interactive color.
                .overlay {
                    IslandShape(silhouette: l.silhouette)
                        .stroke(timer.settings.theme.accent.opacity(
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
                .clipShape(IslandShape(silhouette: l.silhouette))
                .transition(.opacity)
        }
    }

    /// The body's surface — `ThemeWindowWash`, the exact recipe the main window
    /// and Settings fill their background with, cut to the island's silhouette.
    /// One shared definition is what makes the island 1:1 with the app's
    /// windows: the same full-strength theme gradient, the same darkening for
    /// text contrast, the same corner highlight — not a low-opacity
    /// approximation that reads grey next to the real thing.
    ///
    /// Only the wide states have a body worth glazing. The flat states (`idle`,
    /// `live`) live entirely in the menu-bar row — their `layout.body` is a few
    /// points tall — so they are left as the pure-black hardware lip they always
    /// were. Above the wash sits the one thing that is phase-semantic here — a
    /// glow behind the timer that says which phase you are in, faded out before
    /// it reaches the task rows.
    @ViewBuilder
    private func bodyGlass(_ l: NotchLayout) -> some View {
        let body = l.body
        if body.height > 8 {
            let s = l.silhouette
            let shape = UnevenRoundedRectangle(
                topLeadingRadius: s.bodyTopRadius,
                bottomLeadingRadius: s.cornerRadius,
                bottomTrailingRadius: s.cornerRadius,
                topTrailingRadius: s.bodyTopRadius,
                style: .continuous)
            let theme = timer.settings.theme
            ThemeWindowWash(theme: theme, highlightRadius: 360)
                .overlay {
                    // The one phase-semantic mark on the body: a soft glow behind
                    // the clock, gone before it reaches the tasks. Mono desaturates
                    // it to its near-white accent (`notchPhaseAccent`) so the
                    // surface stays monochrome; every other theme keeps the phase
                    // color, because that color is the message.
                    LinearGradient(
                        colors: [theme.notchPhaseAccent(model.phase).opacity(0.32), .clear],
                        startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.55))
                }
                .clipShape(shape)
                .overlay { shape.stroke(islandHairline(theme), lineWidth: 1) }
                .animation(NotchMotion.phaseFade(reduceMotion: motion.isOn),
                           value: model.phase)
                .frame(width: body.width, height: body.height)
                .offset(x: body.minX - l.island.minX, y: body.minY - l.island.minY)
        }
    }

    /// The island's edge hairline. Neutral (`Color.dsHairline`) on every theme
    /// but Neon — the flashy one — where the rim lights up with the neon gradient
    /// itself, the single loud gesture that theme earns. Applied to the body and
    /// the ears alike, so the whole silhouette reads as one neon-lit tube rather
    /// than a rim that only appears when the island opens.
    private func islandHairline(_ theme: SharinganTheme) -> AnyShapeStyle {
        guard theme == .neon else { return AnyShapeStyle(Color.dsHairline) }
        return AnyShapeStyle(LinearGradient(
            colors: theme.gradient.map { $0.opacity(0.7) },
            startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    /// The live ears' glass — the body's recipe (`.regularMaterial`, the theme
    /// wash, the same hairline), cut down to the two slabs either side of the
    /// cutout, so the live island reads as the same material family as the
    /// expanded panel instead of a flat black bar. **The cutout span
    /// itself stays pure black**: it is imitating the camera housing, exactly
    /// like the idle lip, so the glass stops at the hardware's edges and the
    /// black in the middle keeps reading as hardware rather than as a tinted
    /// window.
    ///
    /// Geometry-driven off the layout's ear rects — the same rects the labels
    /// are laid out against — so a dropped ear (`NotchEarsMode`) drops its
    /// glass with it, and no state but `.live` (the only one with ears) is
    /// touched. Visual only: nothing here changes a rect the mask is cut from.
    /// Each slab spans the island's full height (the ear row *and* the 4pt
    /// lip), keeping the seam against the black a single straight vertical at
    /// the cutout's edge; the outer bottom corner takes the silhouette's own
    /// radius, and the island's `.clipShape` trues everything up against the
    /// drawn shape regardless.
    @ViewBuilder
    private func earGlass(_ l: NotchLayout) -> some View {
        if let left = l.leftEar {
            earGlassSlab(l, x: left.minX, width: left.width,
                         bottomLeadingRadius: l.silhouette.cornerRadius,
                         bottomTrailingRadius: 0)
        }
        if let right = l.rightEar {
            earGlassSlab(l, x: right.minX, width: right.width,
                         bottomLeadingRadius: 0,
                         bottomTrailingRadius: l.silhouette.cornerRadius)
        }
    }

    private func earGlassSlab(_ l: NotchLayout, x: CGFloat, width: CGFloat,
                              bottomLeadingRadius: CGFloat,
                              bottomTrailingRadius: CGFloat) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: bottomLeadingRadius,
            bottomTrailingRadius: bottomTrailingRadius,
            topTrailingRadius: 0,
            style: .continuous)
        let theme = timer.settings.theme
        // The body's surface cut down to the ears — the same `ThemeWindowWash`
        // the app's windows wear, with the highlight reach scaled to a 41pt
        // strip, so the live island and the expanded panel are one surface.
        return ThemeWindowWash(theme: theme, highlightRadius: 140)
            .clipShape(shape)
            .overlay { shape.stroke(islandHairline(theme), lineWidth: 1) }
            .animation(NotchMotion.phaseFade(reduceMotion: motion.isOn),
                       value: model.phase)
            .frame(width: width, height: l.island.height)
            .offset(x: x - l.island.minX, y: 0)
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
                                  theme: timer.settings.theme, reduceMotion: reduce)
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
/// Sized to `layout.island` like every other content view, and laid out inside
/// `layout.body` — the part of the T below the menu bar. It used to be *pushed*
/// clear of the camera housing with a top padding; the body already starts below
/// the housing, so the line simply centers in it.
///
/// It has two seconds; it uses them. The icon lands with a bounce and unwinds a
/// small tilt, the line follows it in a beat later, and the pair leaves by
/// lifting out of the island (`.notchContent(rise:)` upstairs).
struct NotchActivityView: View {
    let activity: NotchActivity
    @ObservedObject var model: NotchHUDModel
    let layout: NotchLayout
    /// The active theme, so the announcement icon's glow follows it (chiefly so
    /// Mono desaturates it, via `notchPhaseAccent`, like the rest of the island).
    let theme: SharinganTheme
    let reduceMotion: Bool

    /// Flipped in `onAppear`, which is what stages the arrival. A `.transition`
    /// on these children would never run: SwiftUI animates the transition of the
    /// outermost inserted view only, and that is this view.
    @State private var landed = false

    var body: some View {
        // Reduce Motion keeps the fade and drops the spring, the tilt and the
        // slide — an announcement that scales and rotates is exactly what the
        // setting is there to stop.
        let settled = landed || reduceMotion

        return HStack(spacing: 8) {
            Image(systemName: activity.systemImage)
                .font(.system(size: 14, weight: .semibold))
                // The phase color the body glow already carries — the icon reads
                // as the same accent instead of a bare white glyph. Routed
                // through the theme so Mono desaturates it in step with the glow.
                .foregroundStyle(theme.notchPhaseAccent(model.phase))
                .scaleEffect(settled ? 1 : NotchMotion.announceIconScale)
                .rotationEffect(.degrees(settled ? 0 : NotchMotion.announceIconTilt))
                .opacity(landed ? 1 : 0)
                .animation(NotchMotion.announceIcon(reduceMotion: reduceMotion),
                           value: landed)

            Text(activity.message)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.dsPrimary)
                .lineLimit(1)
                .opacity(landed ? 1 : 0)
                .offset(y: settled ? 0 : NotchMotion.announceTextDrift)
                .animation(NotchMotion.announceText(reduceMotion: reduceMotion),
                           value: landed)
        }
        .padding(.horizontal, 16)
        // Centered in the body — the part below the menu bar — and then the body
        // is hung off the island's top edge. Two frames rather than one padding:
        // the announcement is a single line and it belongs in the middle of the
        // black, not pressed against its top edge.
        .frame(width: layout.island.width, height: layout.body.height)
        .padding(.top, layout.body.minY - layout.island.minY)
        .frame(width: layout.island.width, height: layout.island.height,
               alignment: .top)
        .onAppear { landed = true }
    }
}

/// The island's silhouette — the **T** in the wide states, a rounded-bottom
/// rectangle in the short ones. The path itself lives in `NotchGeometry` (Core),
/// which is also what the hit-test mask is cut from: one definition, so what is
/// drawn and what is clickable are the same shape by construction.
///
/// **Only the corner radius animates, and that is a safety property, not an
/// oversight.** SwiftUI interpolates `animatableData` and takes every other
/// stored property at its new value immediately — so when the state flips, the
/// stem's width and the body's top edge land on the new state's *at the same
/// instant the hit-test mask does*, while the island's frame springs into place
/// underneath them. That is what keeps the drawn shape inside the mask through
/// the whole morph, in both directions:
///
/// - **Opening** (`live` → `expanded`), the mask is already the T. The stem is
///   already the cutout's width, so the growing frame can only ever fill the
///   T's body — which is below the menu bar. Not one frame of the open paints
///   black over a menu-bar title. (The cost: the ears' black does not retract,
///   it is simply gone on the first frame. Everything the eye is following —
///   the body dropping out of the notch — is the part that moves.)
/// - **Closing**, the mask has already shrunk to the live island, and the frame
///   is still expanded-wide for a few frames. Those frames are drawn as a T
///   whose stem is the *live* island's width (see `NotchGeometry.flat`), so the
///   overhang hangs below the menu bar, over the desktop, where it is
///   click-through and invisible against the wallpaper for 260ms.
///
/// Interpolating the stem would look smoother and would be wrong: a stem
/// halfway between 278pt and 200pt is 39pt of black over `Window` and `Help`
/// that the mask has already given back to the menu bar — drawn, unclickable,
/// and precisely the thing this shape exists to stop.
struct IslandShape: Shape {
    var silhouette: NotchSilhouette

    /// The radius grows with the island's height, so it has to *interpolate*
    /// with the morph rather than jump to the new state's value on frame one —
    /// a 14pt corner snapping to 22pt at the start of the open is exactly the
    /// snap this pass exists to remove.
    var animatableData: CGFloat {
        get { silhouette.cornerRadius }
        set { silhouette.cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        Path(NotchGeometry.islandPath(in: rect, silhouette: silhouette))
    }
}

extension SharinganTheme {
    /// A phase-semantic accent — the glow behind the clock, the active-row tint,
    /// the running row's control, the announcement icon — resolved for this
    /// theme. It is the phase's own color everywhere, because that color *is* the
    /// information (blue = focus, green = break). The sole exception is Mono,
    /// whose one rule is "nothing saturated but the near-white accent": there a
    /// blue focus glow would be the single loud thing on an otherwise grey
    /// island, so it yields to `accent`. The phase stays readable on Mono
    /// regardless — the progress line and the dot beside the task name keep the
    /// raw phase color, the two marks the notch pins as phase-always.
    func notchPhaseAccent(_ phase: PomodoroPhase) -> Color {
        self == .mono ? accent : phase.glow
    }
}
