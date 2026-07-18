import SwiftUI
import AppKit
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
            // Arm the union-mask hold for the morph that just started. Under
            // Reduce Motion the shape cuts instantly, so there is no morph to
            // hold a mask for. The manager clears this on the shrink clock
            // (`NotchWindowManager`, `maskJob`).
            maskHoldSize = ReduceMotionMonitor.shared.isOn ? nil : oldValue.size
        }
    }
    /// The shape the island is morphing *from*.
    @Published private(set) var previousSize: NotchHUDSize = .hidden
    /// The state whose hit-test mask is *additionally* honored while a morph is
    /// running — the union-mask hold that makes the animating silhouette safe
    /// (see `IslandShape`). Set by the manager on every size change and cleared
    /// on `NotchMotion.windowShrinkDelay`'s clock; `previousSize` cannot serve
    /// here because it persists forever and would swallow menu-bar clicks in
    /// the vacated region permanently.
    @Published var maskHoldSize: NotchHUDSize? = nil
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
            ZStack(alignment: .top) {
                IslandShape(silhouette: l.silhouette)
                    // The cutout span stays pure black — it is imitating the
                    // camera housing. Everything the island *adds* to the
                    // hardware is dressed in Sharingan's dark glass on top of it:
                    // the expanded body below the menu bar (`bodyGlass`) and
                    // the live ears either side of the cutout (`earGlass`).
                    //
                    // Idle — exactly the cutout, nothing added — paints NO
                    // black at all. On glass those pixels sit behind the
                    // housing, but the framebuffer under the housing is real:
                    // screenshots capture it (a phantom black notch on a light
                    // menu bar) and the Spaces-swipe animation slides it
                    // sideways (a black cutout gliding across the menu bar).
                    // A closed HUD must leave the framebuffer exactly as a Mac
                    // without the app would. The silhouette still exists —
                    // hover hit-testing is geometry-based — so the fill fades
                    // back in with the opening morph.
                    //
                    // In `.live` the black stops at the cutout: the 4pt lip
                    // below it belongs to the progress line alone (drawn by
                    // `NotchEars`), so a running island paints no black a
                    // light menu bar could show as a droplet under the notch.
                    // The silhouette (and with it the clip, the hover stroke
                    // and the hit mask) still spans the lip — only the black
                    // fill is held back.
                    .fill(model.state.size == .expanded
                          ? AnyShapeStyle(flatSurfaceBase(timer.settings.theme))
                          : AnyShapeStyle(Color.black))
                    .opacity(model.state.size == .idle ? 0 : 1)
                    .frame(height: blackFillHeight(l))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                // While expanded, cap the whole menu-bar row — stem strip and
                // both shoulders — with ONE full-width body-tone shape
                // (`NotchTopCapShape`). It used to be three separately-drawn
                // surfaces (stem overlay + two shoulder slabs), and three
                // surfaces means seams: hairline vertical edges flanking the
                // cutout wherever the frames met. One shape has no seams by
                // construction, and it doubles as the opening's hero move: it
                // stretches out of the cutout like the notch itself widening.
                // Added *after* the clip: the silhouette doesn't include the
                // menu-bar row beside the stem, so the clip would eat it.
                .overlay(alignment: .top) { expandedShoulders(l) }
                .transition(.opacity)
        }
    }

    /// The one body-tone cap filling the whole menu-bar row — stem strip and
    /// both shoulders — while expanded, giving the panel its seamless
    /// full-width top edge (see the call site).
    ///
    /// Extracted to its own view so each opening plays the emergence: the cap
    /// stretches out of the hardware notch (`NotchShouldersView`), which needs
    /// an `onAppear` of its own — a plain `@ViewBuilder` here would flip state
    /// in the parent and never re-fire on the next expand. Closing is the same
    /// move reversed: the removal transition sweeps the cap back *into* the
    /// cutout on the closing spring, so the notch narrows shut instead of the
    /// top row blinking away.
    @ViewBuilder
    private func expandedShoulders(_ l: NotchLayout) -> some View {
        if model.state.size == .expanded {
            let capW = l.island.width + 2 * NotchGeometry.shoulderFlare
            let stemFraction = capW > 0 ? l.silhouette.stemWidth / capW : 1
            NotchShouldersView(layout: l, theme: timer.settings.theme,
                               showIris: timer.settings.notchShowIris,
                               leftStyle: timer.settings.sharinganStyle,
                               rightStyle: timer.settings.sharinganStyleRight
                                ?? timer.settings.sharinganStyle,
                               surface: flatSurfaceBase(timer.settings.theme),
                               reduce: motion.isOn)
                .transition(.asymmetric(
                    insertion: .identity,   // the view stages its own emergence
                    removal: .modifier(
                        active: CapCollapse(progress: 0, stemFraction: stemFraction),
                        identity: CapCollapse(progress: 1, stemFraction: stemFraction))
                        .animation(NotchMotion.capRetract(reduceMotion: motion.isOn))))
        }
    }

    /// How far down the island's black fill runs. Full height everywhere but
    /// `.live`, where it stops at the hardware cutout: the lip strip below is
    /// the progress line's row, not more housing (nil = unconstrained).
    private func blackFillHeight(_ l: NotchLayout) -> CGFloat? {
        guard model.state.size == .live else { return nil }
        return max(0, l.island.height - NotchGeometry.liveLipHeight)
    }

    /// The body's surface — the app window's tone, **flattened**. The window's
    /// full recipe (`ThemeWindowWash`: darkening ramp + corner highlight) is
    /// tuned for a window-sized canvas; compressed into a 340pt island the same
    /// ramp reads as a loud "gradient effect", which the user explicitly does
    /// not want. So the island takes the window's color and drops its lighting:
    /// the theme `surface` under one uniform darkening — the tone a mid-window
    /// crop of `ThemeWindowWash` averages to. Same color as the app, flat as a
    /// panel. (`surface` is already a dark base, so this darkening is light —
    /// just enough to seat the island a touch below the window's own tone.)
    ///
    /// Only the wide states have a body worth glazing. The flat states (`idle`,
    /// `live`) live entirely in the menu-bar row — their `layout.body` is a few
    /// points tall — so they stay pure black: idle hides entirely behind the
    /// housing, and live adds only the lip the progress line runs on.
    private static let flatDarkening: Double = 0.14

    /// The panel's single flat surface tone — the theme's two surface colors
    /// blended to one, so the body, the stem strip and the two shoulders can all
    /// be painted the *same* flat color. A gradient painted piecewise (each with
    /// its own frame) never lines up across the seams; one flat color makes the
    /// expanded panel read as one uniform rectangle, which is the whole point.
    private func flatSurface(_ theme: SharinganTheme) -> Color {
        let s = theme.surface
        guard s.count >= 2 else { return s.first ?? .black }
        let a = NSColor(s[0]).usingColorSpace(.sRGB) ?? .black
        let b = NSColor(s[1]).usingColorSpace(.sRGB) ?? .black
        return Color(red: Double(a.redComponent + b.redComponent) / 2,
                     green: Double(a.greenComponent + b.greenComponent) / 2,
                     blue: Double(a.blueComponent + b.blueComponent) / 2)
    }

    /// The body's *final* visible tone — `flatSurface` after the `flatDarkening`
    /// black overlay is folded in (overlaying black at α is a plain multiply by
    /// 1−α). The expanded island's base fill uses this so the black slab behind
    /// the body is the exact body color, and no black rim can peek at the edges
    /// where an overlay stops a hair short. Idle/live keep the pure-black fill —
    /// there the black is imitating the camera housing, not a panel.
    private func flatSurfaceBase(_ theme: SharinganTheme) -> Color {
        let k = 1 - Self.flatDarkening
        let c = NSColor(flatSurface(theme)).usingColorSpace(.sRGB) ?? .black
        return Color(red: Double(c.redComponent) * k,
                     green: Double(c.greenComponent) * k,
                     blue: Double(c.blueComponent) * k)
    }

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
            flatSurface(theme)
                .overlay(Color.black.opacity(Self.flatDarkening))
                .clipShape(shape)
                .overlay { shape.stroke(islandHairline(theme), lineWidth: 1) }
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
    /// like the idle island, so the glass stops at the hardware's edges and the
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
        // The body's flat tone cut down to the ears — the theme's color under
        // the same uniform darkening, no lighting effects, so the live island
        // and the expanded panel are one plain surface with the app's color.
        return LinearGradient(colors: theme.surface,
                              startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(Color.black.opacity(Self.flatDarkening))
            .clipShape(shape)
            .overlay { shape.stroke(islandHairline(theme), lineWidth: 1) }
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
/// **The whole silhouette animates — stem, body top, fillet, corner — so the
/// open reads as the notch itself expanding, and the close as the exact
/// reverse.** That used to be forbidden (only the corner radius interpolated)
/// because the hit-test mask flips instantly; it is safe now because the mask
/// holds the **union** of both endpoint states for the morph's duration
/// (`NotchHUDModel.maskHoldSize`, honored by `NotchGeometry.hitTest`'s
/// `holdSize:` overload). The safety argument:
///
/// - Every spring that drives this shape is critically damped
///   (`NotchMotion.shapeDamping` == 1.0), so each animated parameter moves
///   monotonically between its endpoint values — no overshoot, ever.
/// - Each edge of the T therefore interpolates between its position in the old
///   state and its position in the new one, so in the **menu-bar row** — the
///   only row where a drawn-but-unmasked pixel covers something clickable —
///   every intermediate shape is contained in the union of the two endpoint
///   paths, precisely the region the union mask claims. (Below the menu bar
///   the intermediate body can transiently poke outside the union; that black
///   sits over the desktop, click-through, the same cosmetic overhang the old
///   snapped-silhouette close already had.)
/// - The hold is dropped after `NotchMotion.windowShrinkDelay`, the same clock
///   the window's own shrink runs on: for as long as the vacated body region
///   is masked, the window covering it exists anyway.
///
/// The one cost is on the close: a click where the body just was falls through
/// only after ~0.45s instead of instantly. The trade is the morph itself —
/// mid-close the stem is genuinely between widths, and without the hold those
/// frames would be black over `Window` and `Help` that the mask had already
/// given back.
/// A bare Sharingan iris for a notch ear (`MoveIrisView`, no lids), animated to
/// feel premium: it turns slowly and ceaselessly, and every `awakenCycle`
/// seconds it *awakens* — the tomoe collapse into the pupil, the iris whirls two
/// fast turns and blooms back out, with a soft scale pulse riding the burst. Its
/// own `TimelineView` clock drives all of it, so it lives whether or not a
/// session is running. `reduce` freezes it still and fully formed for Reduce
/// Motion.
private struct NotchShoulderIris: View {
    var style: SharinganStyle
    var diameter: CGFloat
    var reduce: Bool

    /// Seconds per full turn of the ceaseless base rotation.
    private let secondsPerTurn: Double = 16
    /// Seconds between awakenings, and how long each awakening runs.
    private let awakenCycle: Double = 9
    private let awakenDur: Double = 1.7

    var body: some View {
        if reduce {
            MoveIrisView(diameter: diameter, style: style)
        } else {
            TimelineView(.animation) { ctx in
                let f = frame(at: ctx.date.timeIntervalSinceReferenceDate)
                MoveIrisView(diameter: diameter, spin: f.spin, style: style,
                             emergence: f.emergence)
                    .scaleEffect(f.scale)
                    // A faint bloom of the iris's own light on each awakening —
                    // the premium glow, strongest as the tomoe whirl back out.
                    .shadow(color: (style == .rinnegan ? Color.purple : Color.red)
                        .opacity(f.glow), radius: 0.28 * diameter)
            }
        }
    }

    /// The whole animation as pure math for time `t`: a continuous base spin,
    /// plus a periodic eased awakening burst (collapse → whirl → bloom).
    private func frame(at t: TimeInterval) -> (spin: Double, emergence: CGFloat,
                                               scale: CGFloat, glow: Double) {
        let base = t * 360 / secondsPerTurn
        let ph = t.truncatingRemainder(dividingBy: awakenCycle)
        guard ph < awakenDur else {
            // Resting: gentle breathing only.
            return (base, 1, 1 + CGFloat(sin(t * 0.7)) * 0.015, 0)
        }
        let u = ph / awakenDur                      // 0…1 through the burst
        // Collapse to a near-bare iris in the first third, bloom back over the
        // rest — the tomoe suck into the pupil and spiral out (MoveIrisView's
        // `emergence` carries the whirl-out for free).
        let e: CGFloat = u < 0.33
            ? 1 - CGFloat(u / 0.33) * 0.82
            : 0.18 + CGFloat((u - 0.33) / 0.67) * 0.82
        // Two full extra turns, eased out — a multiple of 360° so it rejoins the
        // base spin with no visible snap when the burst ends.
        let eased = 1 - pow(1 - u, 3)
        let burstSpin = eased * 720
        let pulse = sin(u * .pi)                    // 0→1→0 across the burst
        return (base + burstSpin, e,
                1 + CGFloat(pulse) * 0.09, pulse * 0.5)
    }
}

/// The expanded panel's top cap — ONE full-width body-tone shape spanning the
/// whole menu-bar row (both shoulders *and* the strip under the cutout), so
/// there is no seam anywhere: the old stem-overlay/shoulder-slab junctions were
/// three separately-framed surfaces and showed hairline vertical edges flanking
/// the notch.
///
/// It is also the opening's hero move: on appear the cap starts squeezed to
/// exactly the cutout's width — invisible behind the hardware notch — and
/// stretches out to full width on a spring, so the panel reads as *the notch
/// itself widening*. The irises ride their own slide out from behind the
/// cutout. Driven by an `onAppear` `@State` so it replays on every open (a
/// `.transition` inserts this subtree each time the island expands); the
/// reverse sweep on close is the removal transition at the call site.
private struct NotchShouldersView: View {
    let layout: NotchLayout
    let theme: SharinganTheme
    let showIris: Bool
    let leftStyle: SharinganStyle
    let rightStyle: SharinganStyle
    /// The flat body tone the cap is painted in — passed in so it matches the
    /// body without re-deriving it here.
    let surface: Color
    let reduce: Bool

    /// Flipped in `onAppear`. Reduce Motion pins it settled from the start, so
    /// the cap is simply there — no stretch, no fade.
    @State private var out = false

    var body: some View {
        let l = layout
        let stemW = l.silhouette.stemWidth
        let sideW = max(0, (l.island.width - stemW) / 2)
        // Lap a hair past the menu-bar row so the cap meets the body's top edge
        // with no seam between the two body-tone surfaces.
        let capH = l.silhouette.bodyTop + 2
        let flare = NotchGeometry.shoulderFlare
        let capW = l.island.width + 2 * flare
        let irisD = max(12, min(capH - 12, sideW - 14))
        let irisInset = max(0, (sideW - irisD) / 2)
        let settled = out || reduce
        // How far each iris starts tucked toward the cutout: its own width plus
        // its insets, so it begins fully under the hardware notch and slides
        // out into place with the cap's stretch.
        let irisSlide = irisD + irisInset + flare

        NotchTopCapShape(flare: flare)
            .fill(surface)
            .frame(width: capW, height: capH)
            // The widening itself: from the cutout's width out to full, pinned
            // to the center so both sides emerge symmetrically — the notch
            // stretching, not a slab arriving. Scale is ≤ 1 throughout, and the
            // cap lives in the ear-reserve margin: it touches no rect the
            // hit-test mask is cut from.
            .scaleEffect(x: settled ? 1 : min(1, stemW / max(capW, 1)),
                         anchor: .center)
            .overlay(alignment: .leading) {
                if showIris {
                    NotchShoulderIris(style: leftStyle, diameter: irisD,
                                      reduce: reduce)
                        .padding(.leading, flare + irisInset)
                        // Starts under the cutout (right, +x), slides out left.
                        .offset(x: settled ? 0 : irisSlide)
                        .opacity(settled ? 1 : 0)
                }
            }
            .overlay(alignment: .trailing) {
                if showIris {
                    NotchShoulderIris(style: rightStyle, diameter: irisD,
                                      reduce: reduce)
                        .padding(.trailing, flare + irisInset)
                        // Mirror: tucked toward the cutout (left, −x).
                        .offset(x: settled ? 0 : -irisSlide)
                        .opacity(settled ? 1 : 0)
                }
            }
            .frame(width: capW, height: l.island.height, alignment: .top)
            .allowsHitTesting(false)
            .animation(NotchMotion.shoulderEmerge(reduceMotion: reduce), value: out)
            .onAppear { out = true }
    }
}

/// The closing half of the cap's story: sweeps it back down to the cutout's
/// width (and fades it) as the island collapses, so the notch visibly narrows
/// shut. `progress` 1 = at rest, 0 = swallowed by the notch.
struct CapCollapse: ViewModifier {
    var progress: Double
    var stemFraction: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: stemFraction + (1 - stemFraction) * progress,
                         anchor: .center)
            .opacity(progress)
    }
}

/// One notch shoulder — the body-tone slab filling the menu-bar row beside the
/// cutout, in the **real-macOS-notch** silhouette the user picked: a flat top
/// (a softly rounded outer-top corner, then straight across to the cutout), a
/// straight outer edge down to the panel's side, and a concave fillet on the
/// inner-bottom corner where the black notch melts outward into the menu bar.
/// `outerLeading` picks which side the outer edge is on.
struct NotchTopCapShape: Shape {
    /// The concave outer-top flare: the radius of the quarter-fillet that
    /// sweeps each vertical outer edge outward into the flat top edge — the
    /// exact inverse of a desktop corner (the snap-zones reference look). The
    /// rect handed to this shape already includes the flare on both sides.
    var flare: CGFloat = NotchGeometry.shoulderFlare

    func path(in rect: CGRect) -> Path {
        // One continuous slab across the whole menu-bar row: flat top edge from
        // flared tip to flared tip, a concave quarter-fillet down to each
        // vertical body edge, and a straight bottom that laps the body below.
        // No inner geometry at all — the hardware cutout covers its own span,
        // so there is nothing to cut out and no seam to show.
        let fl = max(0, min(flare, rect.height, rect.width / 2))
        let leftBody = rect.minX + fl, rightBody = rect.maxX - fl
        let top = rect.minY, bot = rect.maxY
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: top))                 // left flared tip
        p.addLine(to: CGPoint(x: rect.maxX, y: top))              // flat top, full width
        // Concave quarter-fillet: the top edge bends down-and-inward, landing
        // tangent on the right vertical body edge.
        p.addQuadCurve(to: CGPoint(x: rightBody, y: top + fl),
                       control: CGPoint(x: rightBody, y: top))
        p.addLine(to: CGPoint(x: rightBody, y: bot))              // right edge, dead vertical
        p.addLine(to: CGPoint(x: leftBody, y: bot))               // bottom, laps the body
        p.addLine(to: CGPoint(x: leftBody, y: top + fl))          // left edge, dead vertical
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: top),         // mirror fillet
                       control: CGPoint(x: leftBody, y: top))
        p.closeSubpath()
        return p
    }
}

struct IslandShape: Shape {
    var silhouette: NotchSilhouette

    /// The full silhouette vector: stem width and body top in the first pair,
    /// corner radius and fillet in the second. `bodyTopRadius` is a constant
    /// across states and stays stored. These interpolate on the same spring the
    /// frame does (the `.animation(value: state.size)` on the island), so the
    /// waist widens exactly as the body grows — the notch stretching, not a
    /// panel appearing under a snapped shape.
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>,
                                       AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(AnimatablePair(silhouette.stemWidth, silhouette.bodyTop),
                           AnimatablePair(silhouette.cornerRadius, silhouette.filletRadius))
        }
        set {
            silhouette.stemWidth = newValue.first.first
            silhouette.bodyTop = newValue.first.second
            silhouette.cornerRadius = newValue.second.first
            silhouette.filletRadius = newValue.second.second
        }
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
