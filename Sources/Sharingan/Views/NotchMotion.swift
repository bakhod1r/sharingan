import AppKit
import SwiftUI
import SharinganCore

/// Reduce Motion, read once and kept current.
///
/// `NSWorkspace` is the source of truth. SwiftUI's `\.accessibilityReduceMotion`
/// is the same bit and is what the rest of the app reads, but the HUD lives in a
/// borderless, non-activating `NSPanel` that never becomes key and is hosted
/// outside the app's window hierarchy — so the island reads the workspace flag
/// directly rather than trusting the environment to reach it, and observes
/// `accessibilityDisplayOptionsDidChangeNotification` so flipping the switch in
/// System Settings takes effect without a relaunch.
@MainActor
final class ReduceMotionMonitor: ObservableObject {
    static let shared = ReduceMotionMonitor()

    @Published private(set) var isOn: Bool

    private var observer: NSObjectProtocol?

    private init() {
        isOn = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                let monitor = ReduceMotionMonitor.shared
                monitor.isOn = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            }
        }
    }
}

/// Every number the island moves by, in one place.
///
/// There is no notched display in CI and no simulate flag, so nobody can watch
/// this run on demand: this file is the spec. Each constant says what it is
/// imitating.
///
/// **Why the island does not use `DS.Motion` wholesale.** The house tokens are
/// one symmetric hand — the same spring opening and closing. The island needs an
/// asymmetric one (opening carries mass, closing gets out of the way), and it
/// works under a constraint no other surface has:
///
/// **The hit-test mask holds the union of both morph endpoints.** The whole
/// silhouette animates now (`IslandShape` — stem, body top, fillet, corner all
/// interpolate, so opening reads as the notch itself expanding and closing as
/// the exact reverse). That is safe under two conditions this file enforces:
///
/// 1. Every spring that touches the island's frame or silhouette is critically
///    damped (`dampingFraction` 1.0 → monotone, provably no overshoot) and
///    every scale on it is ≤ 1 — so in the menu-bar row, the only row where a
///    stray black pixel covers something clickable, every intermediate shape
///    is contained in the union of the two endpoint paths.
/// 2. For the morph's duration the mask honors *both* endpoints
///    (`NotchHUDModel.maskHoldSize`, cleared by the manager after
///    `windowShrinkDelay` — the same clock the window's shrink runs on).
///
/// The overshoot that sells "mass" still lives only where it cannot escape the
/// silhouette — the anticipation squash (which only ever scales *down*), and
/// the content, which is clipped. Read `IslandShape` before loosening any
/// damping here: an underdamped shape spring would overshoot the union and
/// paint black over click-through menu-bar pixels.
enum NotchMotion {

    // MARK: - The shape

    /// Opening. Long enough to have weight — the hardware stretching, not a
    /// window resizing. Critically damped: a bouncy open would push the black
    /// past `layout.island` and paint over menu-bar pixels the mask has already
    /// declared click-through.
    static let openResponse: Double = 0.38
    /// Closing. Faster and out of the way; nobody wants to wait for a HUD to
    /// leave.
    static let closeResponse: Double = 0.26
    /// 1.0 == critical damping == the shape never overshoots its rect. This is
    /// the safety constant; do not lower it. Put bounce in the content instead.
    static let shapeDamping: Double = 1.0
    /// Content leaves first, *then* the shape closes: the frame's collapse waits
    /// out the content fade. Costs a few extra ms of the (cosmetic-only) overhang
    /// the collapsing island already has — the mask has shrunk, so those pixels
    /// are click-through and nothing can be swallowed.
    static let closeLead: Double = 0.07

    /// The morph. `expanding` comes from `NotchHUDSize.growthRank`.
    static func shape(expanding: Bool, reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }   // instant cut
        return expanding
            ? .spring(response: openResponse, dampingFraction: shapeDamping)
            : .spring(response: closeResponse, dampingFraction: shapeDamping)
                .delay(closeLead)
    }

    // MARK: - The window

    /// How long `NotchWindowManager.syncPanelFrame` waits, after a state change
    /// that *shrinks* the island, before pulling the panel window down to the
    /// new silhouette. The window must outlive the collapse — a window that
    /// shrinks the instant the state flips would clip the island mid-spring:
    /// the content's departure head start (`closeLead`, 0.07) plus the closing
    /// spring (`closeResponse`, 0.26 — critically damped, so visually settled
    /// around its response) is ~0.33s, and the margin covers the spring's tail.
    /// Growth is the other way round and needs no constant: the window is
    /// resized *before* the opening spring, so the island always grows inside
    /// it.
    static let windowShrinkDelay: Double = 0.45

    /// The island **re-sizing in place**: a task ticked off the panel's own list
    /// leaves the island one row taller than it needs to be, so the black closes
    /// up behind it.
    ///
    /// This is not a morph and cannot use `shape(expanding:)`. The shape stays
    /// `.expanded` throughout — `NotchHUDSize` does not change, and neither does
    /// `growthRank`, which is the only thing `expanding` is computed from. What
    /// changes is `NotchContentConfig.taskCount`, and with it the island's
    /// height. Without its own spring keyed on the config, that height would
    /// *snap*.
    ///
    /// Between the two responses, and critically damped like every other spring
    /// that touches the frame: the hit-test mask does not animate — it flips to
    /// the new island rect the instant the row count does — so the drawn shape
    /// has to approach that rect from the inside and never overshoot it.
    static let resizeResponse: Double = 0.32
    static func resize(reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }   // instant cut
        return .spring(response: resizeResponse, dampingFraction: shapeDamping)
    }

    // MARK: - Anticipation squash

    /// The island dips a hair before it grows — the classic anticipation beat,
    /// and the one way to read "mass" without ever leaving the rect: a scale
    /// *down* is by definition inside the silhouette. 2.8% on the 37pt idle
    /// island is about a point: felt, not seen.
    static let squashScale: Double = 0.972
    /// Down fast …
    static let squashDown: Double = 0.07
    /// … back on a critically damped spring, so the return lands on 1.0 and does
    /// not pass it. `bounce: 0` is the same promise as `shapeDamping`.
    static let squashUp: Double = 0.30
    static var squashSpring: Spring { Spring(duration: squashUp, bounce: 0) }

    // MARK: - Content

    /// The shape's head start. Content must never appear before there is room
    /// for it — this is the difference between an island that opens and a box
    /// that fills.
    static let contentLead: Double = 0.10
    /// Sections of the expanded panel arrive this far apart, in reading order,
    /// so the panel assembles instead of blinking. 4 sections × 35ms = 105ms of
    /// stagger; the last one lands ~400ms in, inside the 450ms budget.
    static let stagger: Double = 0.035
    /// Arriving content starts a touch small and a touch *high* — it pours down
    /// out of the notch with the widening cap, not up from below — then
    /// settles: the slight overshoot (damping 0.78) is safe because content is
    /// clipped to the silhouette.
    static let arriveScale: Double = 0.96
    static let arriveDrift: CGFloat = 6
    /// Leaving content just fades, fast — it has to be gone before the shape is.
    static let departDuration: Double = 0.10
    /// Under Reduce Motion every arrival and departure collapses to this
    /// cross-fade: no drift, no scale, no stagger.
    static let reducedCrossfade: Double = 0.12

    /// Section `index` of a staggered reveal (0 = first). Also used un-staggered
    /// (index 0) by the ears and the announcement.
    static func arrival(section index: Int = 0, reduceMotion: Bool) -> Animation {
        guard !reduceMotion else { return .easeInOut(duration: reducedCrossfade) }
        return .spring(response: 0.30, dampingFraction: 0.78)
            .delay(contentLead + stagger * Double(index))
    }

    static func departure(reduceMotion: Bool) -> Animation {
        .easeIn(duration: reduceMotion ? reducedCrossfade : departDuration)
    }

    // MARK: - The ears

    /// The time and the task do not appear fully formed: they slide out from
    /// behind the cutout as the island widens to make room. 8pt of travel is
    /// about a character — enough to read as emergence, short enough to finish
    /// while the shape is still moving.
    static let earDrift: CGFloat = 8

    static func earArrival(reduceMotion: Bool) -> Animation {
        guard !reduceMotion else { return .easeInOut(duration: reducedCrossfade) }
        return .spring(response: 0.32, dampingFraction: 0.82).delay(contentLead)
    }

    // MARK: - The top cap

    /// The expanded panel's top cap doesn't blink into place: it starts
    /// squeezed to the cutout's width — hidden behind the hardware notch — and
    /// *stretches out of it* on this spring. The black stem underneath now
    /// widens on the shape's own spring (`openResponse`/`shapeDamping`), so the
    /// cap rides exactly that curve — a softer or slower cap would visibly
    /// shear against the silhouette it is supposed to be the surface of. No
    /// delay — the widening IS the opening, it must move with the shape's
    /// first frame, not after it.
    static func shoulderEmerge(reduceMotion: Bool) -> Animation {
        guard !reduceMotion else { return .easeInOut(duration: reducedCrossfade) }
        return .spring(response: openResponse, dampingFraction: shapeDamping)
    }

    /// … and the reverse on close: the cap sweeps back into the cutout on the
    /// shape's own closing clock (same response, no lead — the top row must
    /// narrow *with* the body's collapse, not linger over the menu bar after
    /// it). Critically damped: this drives a removal transition, and any
    /// overshoot would flash the cap back over pixels already given back.
    static func capRetract(reduceMotion: Bool) -> Animation {
        guard !reduceMotion else { return .easeInOut(duration: reducedCrossfade) }
        return .spring(response: closeResponse, dampingFraction: shapeDamping)
    }

    // MARK: - The progress line

    /// The model's progress is written once a second, on the timer's tick. A
    /// linear tween exactly one tick long lands on the next value as it arrives:
    /// the line creeps continuously instead of stepping, and never wobbles the
    /// way a spring would at a 1pt-per-second pace.
    static let tick: Double = 1.0
    /// A phase flip changes the line's color. Cross-fade it rather than cut —
    /// and the fill's *width* is not interpolated across a flip at all (the fill
    /// carries the phase as its identity, so the new phase's bar fades in at its
    /// own width while the old one fades out at 100%, instead of sweeping
    /// backwards over a second).
    static let phaseCrossfade: Double = 0.45

    static func progressFill(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .linear(duration: tick)
    }

    static func phaseFade(reduceMotion: Bool) -> Animation {
        .easeInOut(duration: reduceMotion ? reducedCrossfade : phaseCrossfade)
    }

    // MARK: - Hover anticipation

    /// Hover has to persist 250ms before the island opens (`hoverOpenDelay`).
    /// Sitting dead for a quarter second and then exploding is what makes a HUD
    /// feel unresponsive, so the island acknowledges the pointer *immediately*
    /// with a hairline along its own silhouette.
    ///
    /// A hairline and not the 1–2% scale the alternative would be: in `.idle`
    /// the island *is* the cutout, so scaling it does nothing visible (it pulls
    /// the black in over dead notch glass), and scaling it *up* would be the one
    /// thing the mask forbids.
    static let hoverHairline: Double = 0.16
    static func hover(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.14)
    }

    // MARK: - The announcement

    /// The icon lands with a bounce — this is the one deliberately underdamped
    /// spring in the island, and it is safe because it is content: the
    /// `.clipShape` eats anything it throws outside the silhouette.
    static let announceIconScale: Double = 0.62
    static let announceIconTilt: Double = -10   // degrees, unwound as it lands
    /// The line follows the icon in, a beat behind, sliding up from below.
    static let announceTextDelay: Double = 0.06
    static let announceTextDrift: CGFloat = 5
    /// It leaves by lifting and fading — the announcement is *done*, not
    /// dismissed, so it goes up and away rather than collapsing back down.
    static let announceRise: CGFloat = 6
    static let announceExit: Double = 0.18

    static func announceIcon(reduceMotion: Bool) -> Animation {
        guard !reduceMotion else { return .easeInOut(duration: reducedCrossfade) }
        return .spring(response: 0.34, dampingFraction: 0.62).delay(contentLead)
    }

    static func announceText(reduceMotion: Bool) -> Animation {
        guard !reduceMotion else { return .easeInOut(duration: reducedCrossfade) }
        return .spring(response: 0.34, dampingFraction: 0.78)
            .delay(contentLead + announceTextDelay)
    }

    static func announceDeparture(reduceMotion: Bool) -> Animation {
        .easeIn(duration: reduceMotion ? reducedCrossfade : announceExit)
    }
}

// MARK: - Reveal / depart

extension View {
    /// One arriving piece of island content: fades in, drifts up into place and
    /// settles from `arriveScale`. Driven by a plain `Bool` the content flips in
    /// `onAppear` rather than by a `.transition`, because SwiftUI runs the
    /// transition of the *outermost* inserted view only — a stagger built from
    /// child transitions inside a freshly inserted subtree would not run at all.
    ///
    /// Every transform here is inward (scale ≤ 1, drift from below) and the
    /// island clips its content to the silhouette regardless, so none of this can
    /// reach a pixel the hit-test mask has not claimed.
    ///
    /// Under Reduce Motion the drift and the scale are dropped outright, not
    /// merely shortened: what is left is a cross-fade, which is the whole promise
    /// of the setting. A 6pt slide is still a slide at 120ms.
    func notchArrival(_ shown: Bool, section: Int = 0, reduceMotion: Bool) -> some View {
        let settled = shown || reduceMotion
        return self
            .opacity(shown ? 1 : 0)
            .scaleEffect(settled ? 1 : NotchMotion.arriveScale, anchor: .top)
            // From *above*: the content emerges downward out of the notch,
            // matching the cap's widening, instead of floating up from below.
            .offset(y: settled ? 0 : -NotchMotion.arriveDrift)
            .animation(NotchMotion.arrival(section: section, reduceMotion: reduceMotion),
                       value: shown)
    }
}

/// Content leaving the island: a fade, optionally lifting as it goes.
struct NotchDeparture: ViewModifier {
    /// 1 = present, 0 = gone.
    var progress: Double
    var rise: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .offset(y: -(1 - progress) * rise)
    }
}

extension AnyTransition {
    /// Insertion is `.identity` on purpose: arriving content stages itself with
    /// `notchArrival(_:section:reduceMotion:)` so it can be staggered. Only the
    /// removal is a transition — content clears out, and the shape's closing
    /// spring waits `NotchMotion.closeLead` for it.
    static func notchContent(rise: CGFloat = 0, animation: Animation) -> AnyTransition {
        .asymmetric(
            insertion: .identity,
            removal: .modifier(active: NotchDeparture(progress: 0, rise: rise),
                               identity: NotchDeparture(progress: 1, rise: rise))
                .animation(animation))
    }
}
