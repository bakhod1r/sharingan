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

/// What the island is allowed to show — `PomodoroSettings`' notch keys,
/// projected into the only form the geometry cares about.
///
/// This is not a cosmetic filter. The expanded island's height is *computed*
/// from it, and the live island's width from `ears`, so the black the HUD hangs
/// over the screen (and the hit-test mask cut from it) shrinks to what the user
/// actually asked for. Defaults reproduce the behavior the HUD shipped with, so
/// an upgraded settings blob cannot resize the island by surprise.
public struct NotchContentConfig: Equatable, Sendable {
    public var ears: NotchEarsMode
    public var showTimerControls: Bool
    public var showTasks: Bool
    public var showQuickActions: Bool
    public var showStatusStrip: Bool
    /// Requested row count — trust it for nothing: read `clampedTaskRows`.
    public var taskRows: Int

    /// The range the panel's height constants were *measured* over. Fewer than
    /// three rows is not worth a task list; more than five does not fit under
    /// the timer row without the island growing past the menu bar's neighbours.
    public static let taskRowRange = 3...5

    public init(ears: NotchEarsMode = .both,
                showTimerControls: Bool = true,
                showTasks: Bool = true,
                showQuickActions: Bool = true,
                showStatusStrip: Bool = true,
                taskRows: Int = NotchTaskRows.defaultLimit) {
        self.ears = ears
        self.showTimerControls = showTimerControls
        self.showTasks = showTasks
        self.showQuickActions = showQuickActions
        self.showStatusStrip = showStatusStrip
        self.taskRows = taskRows
    }

    /// The row count the island is actually sized and filled for. A decoded blob
    /// (or a future build's key) can carry anything; an unclamped 40 here would
    /// size the island off the bottom of the screen.
    public var clampedTaskRows: Int {
        min(max(taskRows, Self.taskRowRange.lowerBound), Self.taskRowRange.upperBound)
    }

    /// Everything on, five rows, both ears — what the HUD did before it was
    /// configurable.
    public static let `default` = NotchContentConfig()
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
    /// The expanded island's width. Everything below is measured *at* this
    /// width — a wider island would rewrap nothing (every row is `lineLimit(1)`)
    /// but a narrower one would, so the width is part of the contract.
    public static let expandedWidth: CGFloat = 340
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

    // MARK: - Expanded panel sizing (measured, not guessed)
    //
    // The expanded island's height is computed from what the panel is configured
    // to show. Every constant below was read off a structural SwiftUI replica of
    // `NotchExpandedPanel` — same stack, same spacings, same fonts — laid out at
    // `expandedWidth` and asked for its `fittingSize`. The table is in the notch
    // settings report; the formula reproduces all 40 measured combinations to
    // the point.
    //
    // Getting one of these wrong is not cosmetic. Too small and the content is
    // cropped at the island's `.clipShape` (the bug this feature already shipped
    // once, at a 260pt guess); too large and the HUD hangs dead black over the
    // user's screen.

    /// Gap between the camera housing and the first pixel of content
    /// (`NotchExpandedPanel.contentTop` is the cutout's height plus this).
    public static let contentTopGap: CGFloat = 6
    /// The panel's bottom padding.
    public static let contentBottomPadding: CGFloat = 10
    /// The `VStack`'s spacing — one gap per section, plus one for the trailing
    /// `Spacer`, which is a child of the stack like any other.
    public static let sectionSpacing: CGFloat = 8
    /// The timer row and the divider under it: 51pt measured.
    public static let timerRowHeight: CGFloat = 51
    /// One task row: 21pt of row …
    public static let taskRowHeight: CGFloat = 21
    /// … and 2pt of list spacing between rows, so a row *costs* 23pt — which is
    /// the 46pt over two rows the shipped 5-row/3-row measurement showed.
    public static let taskRowSpacing: CGFloat = 2
    /// The quick-actions row: 24pt buttons, measured.
    public static let quickActionsHeight: CGFloat = 24
    /// The blocker/streak strip: 13pt of 9pt labels, measured.
    public static let statusStripHeight: CGFloat = 13
    /// Headroom over the measured fit. `fittingSize` is the *ideal* height and
    /// the panel's `Spacer` absorbs this, so it does not read as dead space at
    /// the bottom — it is the margin that keeps a hairline of rounding from
    /// clipping the last row.
    public static let bodySlack: CGFloat = 4

    /// Height of the panel's content — everything below the camera housing.
    /// The cutout gap is added by `expandedSize`, which knows the real cutout,
    /// rather than baked in at one machine's notch height.
    public static func expandedBodyHeight(_ config: NotchContentConfig = .default) -> CGFloat {
        var sections: [CGFloat] = []
        if config.showTimerControls { sections.append(timerRowHeight) }
        if config.showTasks {
            let rows = CGFloat(config.clampedTaskRows)
            sections.append(taskRowHeight * rows + taskRowSpacing * (rows - 1))
        }
        if config.showQuickActions { sections.append(quickActionsHeight) }
        if config.showStatusStrip { sections.append(statusStripHeight) }

        // n sections and the always-present `Spacer` are n+1 children, so n+1-1
        // = n gaps between them.
        return contentBottomPadding
            + sections.reduce(0, +)
            + sectionSpacing * CGFloat(sections.count)
            + bodySlack
    }

    /// The expanded island, sized to what it was configured to show.
    ///
    /// Floored at the announcement's height for a reason that is not
    /// cosmetic: `NotchHUDSize.growthRank` promises `.expanded` is the biggest
    /// shape, and the motion layer picks the opening spring or the closing one
    /// off that promise alone. An all-sections-off config would otherwise
    /// produce a 57pt island — smaller than `.activity` — and hovering it would
    /// spring *shut* as it opened.
    public static func expandedSize(_ config: NotchContentConfig = .default,
                                    cutout: CGSize) -> CGSize {
        let height = cutout.height + contentTopGap + expandedBodyHeight(config)
        return CGSize(width: expandedWidth, height: max(height, activitySize.height))
    }

    /// How wide the live island grows: the cutout, plus one ear per ear the user
    /// still wants. This is the *silhouette*, so it is also exactly how much
    /// menu bar the HUD can swallow — which is the whole point of the setting.
    public static func liveWidth(cutout: CGSize, ears: NotchEarsMode) -> CGFloat {
        cutout.width + earWidth * CGFloat(ears.earCount)
    }

    /// The bottom radius interpolates with the island's height: a taller island
    /// is a rounder one. `maxHeight` is the tallest island *this config* draws —
    /// the expanded one — so the ramp always tops out exactly there.
    ///
    /// This lives in Core, next to `islandPath`, for the same reason the path
    /// does: the *drawn* radius and the radius `hitTest` masks with must be the
    /// same number by construction. If they drift, a corner that is masked
    /// rounder than it is painted leaves a wedge that is clickable but shows the
    /// menu bar — and in `.live` that wedge sits on live menu-bar real estate.
    public static func cornerRadius(forHeight height: CGFloat,
                                    baseHeight: CGFloat,
                                    maxHeight: CGFloat) -> CGFloat {
        guard height > baseHeight else { return cornerRadius }
        let span = max(1, maxHeight - baseHeight)
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

    /// The panel covers the union of every state the *current config* can draw,
    /// so the tracking area can see the pointer before the island grows. It is
    /// invisible and click-through everywhere the mask says no, so its only job
    /// is to be big enough. `.zero` without a hardware notch — there is no panel
    /// to size.
    public static func panelSize(_ m: NotchScreenMetrics,
                                 config: NotchContentConfig = .default) -> CGSize {
        guard let cutout = m.cutout else { return .zero }
        let expanded = expandedSize(config, cutout: cutout)
        // The panel is centered on the cutout, but a one-eared island is *not*
        // symmetric about it — so an ear must be reserved on both sides even
        // when only one is grown, or the trailing ear (island 278pt wide, panel
        // 340pt) hangs 8pt past the panel's edge and is clipped away with its
        // hit region. Reserving it costs nothing: the panel is invisible and
        // click-through everywhere `hitTest` says no. The *mask* is what gives
        // the menu bar back, not the panel's width.
        let earReserve = config.ears.earCount > 0 ? 2 * earWidth : 0
        let width = max(expanded.width,
                        cutout.width + earReserve,
                        activitySize.width)
        let height = max(expanded.height, cutout.height + idleExtraHeight)
        return CGSize(width: width, height: height)
    }

    /// Nothing drawn, nothing hittable — the layout of a display with no notch,
    /// and of the `.hidden` state.
    private static func empty(panel: CGSize) -> NotchLayout {
        NotchLayout(panelSize: panel, island: .zero, leftEar: nil,
                    rightEar: nil, progressTrack: nil,
                    cornerRadius: cornerRadius)
    }

    public static func layout(_ m: NotchScreenMetrics, size: NotchHUDSize,
                              config: NotchContentConfig = .default) -> NotchLayout {
        // No hardware notch, no HUD: every state collapses to nothing, whatever
        // size was asked for.
        guard let cutout = m.cutout else { return empty(panel: .zero) }
        let panel = panelSize(m, config: config)
        let expanded = expandedSize(config, cutout: cutout)

        func centered(width: CGFloat, height: CGFloat) -> CGRect {
            CGRect(x: (panel.width - width) / 2, y: 0, width: width, height: height)
        }

        /// The short states — the cutout plus its lip — are the baseline the
        /// radius grows from, and the expanded island is the top of the ramp.
        let baseHeight = cutout.height + idleExtraHeight
        func radius(_ island: CGRect) -> CGFloat {
            cornerRadius(forHeight: island.height, baseHeight: baseHeight,
                         maxHeight: expanded.height)
        }

        /// The cutout's own left edge. The island is anchored to the hardware,
        /// never centered on the panel — with one ear, centering would slide the
        /// black half an ear off the camera housing.
        let cutoutMinX = (panel.width - cutout.width) / 2

        switch size {
        case .hidden:
            return empty(panel: panel)

        case .idle:
            let island = centered(width: cutout.width, height: baseHeight)
            return NotchLayout(panelSize: panel, island: island, leftEar: nil,
                               rightEar: nil, progressTrack: nil,
                               cornerRadius: radius(island))

        case .live:
            // The island grows only the ears the user still wants — so this is
            // also how much menu bar the mask below can swallow. `.none` leaves
            // the island exactly the cutout, with the progress line along its
            // bottom edge and not one pixel of the menu bar taken.
            let ears = config.ears
            let width = liveWidth(cutout: cutout, ears: ears)
            let minX = ears.showsLeadingEar ? cutoutMinX - earWidth : cutoutMinX
            let island = CGRect(x: minX, y: 0, width: width, height: baseHeight)
            let left = ears.showsLeadingEar
                ? CGRect(x: cutoutMinX - earWidth, y: 0,
                         width: earWidth, height: cutout.height)
                : nil
            let right = ears.showsTrailingEar
                ? CGRect(x: cutoutMinX + cutout.width, y: 0,
                         width: earWidth, height: cutout.height)
                : nil
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
            let island = centered(width: expanded.width, height: expanded.height)
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
    ///
    /// `config` must be the one the view is drawing with, or the mask and the
    /// shape drift: an island narrowed to one ear but masked for two would keep
    /// swallowing menu-bar clicks in a strip that is no longer even black.
    public static func hitTest(_ point: CGPoint, metrics: NotchScreenMetrics,
                               size: NotchHUDSize,
                               config: NotchContentConfig = .default) -> Bool {
        guard metrics.hasHardwareNotch else { return false }
        let l = layout(metrics, size: size, config: config)
        guard !l.island.isEmpty else { return false }
        return islandPath(in: l.island, cornerRadius: l.cornerRadius).contains(point)
    }
}
