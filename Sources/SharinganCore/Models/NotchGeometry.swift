import Foundation
import CoreGraphics

/// Everything the HUD needs to know about the screen it lives on. Built from
/// `NSScreen` in the app layer so the geometry itself stays pure and testable.
public struct NotchScreenMetrics: Equatable, Sendable {
    public var screenWidth: CGFloat
    public var menuBarHeight: CGFloat
    /// Width of the hardware cutout, 0 when the display has none.
    public var notchWidth: CGFloat
    /// Height of the hardware cutout (== safe-area top), 0 when there is none.
    public var notchHeight: CGFloat

    public init(screenWidth: CGFloat, menuBarHeight: CGFloat,
                notchWidth: CGFloat, notchHeight: CGFloat) {
        self.screenWidth = screenWidth
        self.menuBarHeight = menuBarHeight
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
    }

    public var hasHardwareNotch: Bool { notchWidth > 0 && notchHeight > 0 }

    /// The hardware cutout the island is modelled on, `nil` when the display has
    /// none. There is deliberately no synthetic fallback: an app-drawn pill
    /// hanging over the menu bar of a notchless Mac reads as a bug, so on such a
    /// display the HUD simply does not exist — no cutout, no layout, no panel.
    public var cutout: CGSize? {
        hasHardwareNotch ? CGSize(width: notchWidth, height: notchHeight) : nil
    }
}

/// The five shapes the island can take. `activity` is a transient announcement
/// (session done, break started) that collapses on its own.
public enum NotchHUDSize: String, CaseIterable, Sendable {
    case hidden, idle, live, activity, expanded

    /// How much room the shape takes, ordered — the one thing the motion layer
    /// needs from a morph: is the island *growing* or *shrinking*? Opening and
    /// closing are deliberately different springs (see `NotchMotion`), and one
    /// spring for both directions is what makes a morph feel cheap.
    ///
    /// Ordered by island *area*, not width, because area is what the eye reads
    /// as "bigger": `.live` is the widest state (the cutout plus two ears) but
    /// only a 41pt-tall strip, so arriving at the shorter-but-far-taller
    /// `.activity` still reads as the island opening, and is sprung as one.
    public var growthRank: Int {
        switch self {
        case .hidden:   return 0
        case .idle:     return 1
        case .live:     return 2
        case .activity: return 3
        case .expanded: return 4
        }
    }
}

/// Rects for one state, in panel coordinates: origin top-left, y grows down.
public struct NotchLayout: Equatable, Sendable {
    public var panelSize: CGSize
    public var island: CGRect
    public var leftEar: CGRect?
    public var rightEar: CGRect?
    public var progressTrack: CGRect?
    public var cornerRadius: CGFloat
}

public enum NotchGeometry {
    /// Tall enough for the panel's full content — a timer row, `NotchTaskRows`'
    /// five rows, the quick actions and the blocker/streak strip. Measured, not
    /// guessed: the same stack fits in 286pt with five rows (240pt with three),
    /// so 260 cropped the strip clean off at the `.clipShape`; 300 leaves
    /// headroom. The island is *drawn* over this whole rect, so the hit region
    /// growing with it is honest.
    public static let expandedSize = CGSize(width: 340, height: 300)
    public static let earWidth: CGFloat = 78
    /// The idle island is the cutout plus this lip, so it reads as hardware.
    public static let idleExtraHeight: CGFloat = 4
    public static let activitySize = CGSize(width: 300, height: 68)
    public static let progressHeight: CGFloat = 3
    /// The hardware cutout's own bottom corner — the radius of the short states
    /// (`idle`, `live`), which are the cutout plus a 4pt lip.
    public static let cornerRadius: CGFloat = 14
    /// … and the radius of the tall one. The expanded panel wearing the notch's
    /// 14pt corner looks pinched; 22pt reads as the same shape, grown.
    public static let maxCornerRadius: CGFloat = 22

    /// The bottom radius interpolates with the island's height: a taller island
    /// is a rounder one.
    ///
    /// This lives in Core, next to `islandPath`, for the same reason the path
    /// does: the *drawn* radius and the radius `hitTest` masks with must be the
    /// same number by construction. If they drift, a corner that is masked
    /// rounder than it is painted leaves a wedge that is clickable but shows the
    /// menu bar — and in `.live` that wedge sits on live menu-bar real estate.
    public static func cornerRadius(forHeight height: CGFloat,
                                    baseHeight: CGFloat) -> CGFloat {
        guard height > baseHeight else { return cornerRadius }
        let span = max(1, expandedSize.height - baseHeight)
        let t = min(1, (height - baseHeight) / span)
        return cornerRadius + (maxCornerRadius - cornerRadius) * t
    }

    /// Hover must persist this long before the island opens (a pointer merely
    /// crossing the top of the screen must not trigger it) …
    public static let hoverOpenDelay: TimeInterval = 0.25
    /// … and this long after leaving before it closes, so a diagonal exit
    /// across a corner doesn't slam it shut.
    public static let hoverCloseDelay: TimeInterval = 0.15
    public static let activityDuration: TimeInterval = 2.0

    /// The panel never resizes: it always covers the union of every state, so
    /// the tracking area can see the pointer before the island grows.
    /// `.zero` without a hardware notch — there is no panel to size.
    public static func panelSize(_ m: NotchScreenMetrics) -> CGSize {
        guard let cutout = m.cutout else { return .zero }
        let width = max(expandedSize.width,
                        cutout.width + 2 * earWidth,
                        activitySize.width)
        let height = max(expandedSize.height, cutout.height + idleExtraHeight)
        return CGSize(width: width, height: height)
    }

    /// Nothing drawn, nothing hittable — the layout of a display with no notch,
    /// and of the `.hidden` state.
    private static func empty(panel: CGSize) -> NotchLayout {
        NotchLayout(panelSize: panel, island: .zero, leftEar: nil,
                    rightEar: nil, progressTrack: nil,
                    cornerRadius: cornerRadius)
    }

    public static func layout(_ m: NotchScreenMetrics, size: NotchHUDSize) -> NotchLayout {
        // No hardware notch, no HUD: every state collapses to nothing, whatever
        // size was asked for.
        guard let cutout = m.cutout else { return empty(panel: .zero) }
        let panel = panelSize(m)

        func centered(width: CGFloat, height: CGFloat) -> CGRect {
            CGRect(x: (panel.width - width) / 2, y: 0, width: width, height: height)
        }

        /// The short states — the cutout plus its lip — are the baseline the
        /// radius grows from.
        let baseHeight = cutout.height + idleExtraHeight
        func radius(_ island: CGRect) -> CGFloat {
            cornerRadius(forHeight: island.height, baseHeight: baseHeight)
        }

        switch size {
        case .hidden:
            return empty(panel: panel)

        case .idle:
            let island = centered(width: cutout.width, height: baseHeight)
            return NotchLayout(panelSize: panel, island: island, leftEar: nil,
                               rightEar: nil, progressTrack: nil,
                               cornerRadius: radius(island))

        case .live:
            let island = centered(width: cutout.width + 2 * earWidth,
                                  height: baseHeight)
            let cutoutMinX = (panel.width - cutout.width) / 2
            let left = CGRect(x: cutoutMinX - earWidth, y: 0,
                              width: earWidth, height: cutout.height)
            let right = CGRect(x: cutoutMinX + cutout.width, y: 0,
                               width: earWidth, height: cutout.height)
            let track = CGRect(x: island.minX,
                               y: island.maxY - progressHeight,
                               width: island.width, height: progressHeight)
            return NotchLayout(panelSize: panel, island: island, leftEar: left,
                               rightEar: right, progressTrack: track,
                               cornerRadius: radius(island))

        case .activity:
            let island = centered(width: max(activitySize.width, cutout.width),
                                  height: activitySize.height)
            return NotchLayout(panelSize: panel, island: island, leftEar: nil,
                               rightEar: nil, progressTrack: nil,
                               cornerRadius: radius(island))

        case .expanded:
            let island = centered(width: expandedSize.width,
                                  height: expandedSize.height)
            return NotchLayout(panelSize: panel, island: island, leftEar: nil,
                               rightEar: nil, progressTrack: nil,
                               cornerRadius: radius(island))
        }
    }

    /// The island's silhouette: a rectangle whose *bottom* corners are rounded,
    /// so it reads as an extension of the hardware cutout rather than a window
    /// that appeared. This is the ONE definition of that shape — the app's
    /// `IslandShape` draws this path and `hitTest` masks against it, so the drawn
    /// pixels and the clickable region cannot drift apart. (They did: masking
    /// against the bare rect left a wedge at each bottom corner that was hittable
    /// but not drawn, and in `.live` that wedge sits on live menu-bar real
    /// estate.)
    public static func islandPath(in rect: CGRect,
                                  cornerRadius: CGFloat = cornerRadius) -> CGPath {
        let p = CGMutablePath()
        guard rect.width > 0, rect.height > 0 else { return p }
        let r = min(cornerRadius, rect.height / 2, rect.width / 2)
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

    /// True when `point` (panel coordinates) is inside the *currently rendered*
    /// shape. The panel is far bigger than the island, so this is what keeps
    /// menu-bar clicks working: everything outside falls through. Always false
    /// without a hardware notch — nothing is rendered there.
    ///
    /// The ears need no test of their own: they are sub-rects of the island in
    /// `.live` and are drawn inside its silhouette, so masking against the
    /// silhouette covers them — and, unlike their rects, it does not claim the
    /// rounded-off corners.
    public static func hitTest(_ point: CGPoint, metrics: NotchScreenMetrics,
                               size: NotchHUDSize) -> Bool {
        guard metrics.hasHardwareNotch else { return false }
        let l = layout(metrics, size: size)
        guard !l.island.isEmpty else { return false }
        return islandPath(in: l.island, cornerRadius: l.cornerRadius).contains(point)
    }
}
