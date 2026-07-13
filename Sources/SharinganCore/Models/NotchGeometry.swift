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

    /// The cutout the island is modelled on — real on a notched Mac, synthetic
    /// (a pill of the same nominal size) everywhere else.
    public var cutout: CGSize {
        hasHardwareNotch
            ? CGSize(width: notchWidth, height: notchHeight)
            : CGSize(width: NotchGeometry.syntheticNotchWidth, height: menuBarHeight)
    }
}

/// The five shapes the island can take. `activity` is a transient announcement
/// (session done, break started) that collapses on its own.
public enum NotchHUDSize: String, CaseIterable, Sendable {
    case hidden, idle, live, activity, expanded
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
    /// Nominal 14"/16" cutout width, used when the display has no real notch.
    public static let syntheticNotchWidth: CGFloat = 190
    public static let expandedSize = CGSize(width: 340, height: 260)
    public static let earWidth: CGFloat = 78
    /// The idle island is the cutout plus this lip, so it reads as hardware.
    public static let idleExtraHeight: CGFloat = 4
    public static let activitySize = CGSize(width: 300, height: 68)
    public static let progressHeight: CGFloat = 3
    public static let cornerRadius: CGFloat = 14

    /// Hover must persist this long before the island opens (a pointer merely
    /// crossing the top of the screen must not trigger it) …
    public static let hoverOpenDelay: TimeInterval = 0.25
    /// … and this long after leaving before it closes, so a diagonal exit
    /// across a corner doesn't slam it shut.
    public static let hoverCloseDelay: TimeInterval = 0.15
    public static let activityDuration: TimeInterval = 2.0

    /// The panel never resizes: it always covers the union of every state, so
    /// the tracking area can see the pointer before the island grows.
    public static func panelSize(_ m: NotchScreenMetrics) -> CGSize {
        let width = max(expandedSize.width,
                        m.cutout.width + 2 * earWidth,
                        activitySize.width)
        let height = max(expandedSize.height, m.cutout.height + idleExtraHeight)
        return CGSize(width: width, height: height)
    }

    public static func layout(_ m: NotchScreenMetrics, size: NotchHUDSize) -> NotchLayout {
        let panel = panelSize(m)
        let cutout = m.cutout

        func centered(width: CGFloat, height: CGFloat) -> CGRect {
            CGRect(x: (panel.width - width) / 2, y: 0, width: width, height: height)
        }

        switch size {
        case .hidden:
            return NotchLayout(panelSize: panel, island: .zero, leftEar: nil,
                               rightEar: nil, progressTrack: nil,
                               cornerRadius: cornerRadius)

        case .idle:
            let island = centered(width: cutout.width,
                                  height: cutout.height + idleExtraHeight)
            return NotchLayout(panelSize: panel, island: island, leftEar: nil,
                               rightEar: nil, progressTrack: nil,
                               cornerRadius: cornerRadius)

        case .live:
            let island = centered(width: cutout.width + 2 * earWidth,
                                  height: cutout.height + idleExtraHeight)
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
                               cornerRadius: cornerRadius)

        case .activity:
            let island = centered(width: max(activitySize.width, cutout.width),
                                  height: activitySize.height)
            return NotchLayout(panelSize: panel, island: island, leftEar: nil,
                               rightEar: nil, progressTrack: nil,
                               cornerRadius: cornerRadius)

        case .expanded:
            let island = centered(width: expandedSize.width,
                                  height: expandedSize.height)
            return NotchLayout(panelSize: panel, island: island, leftEar: nil,
                               rightEar: nil, progressTrack: nil,
                               cornerRadius: cornerRadius)
        }
    }

    /// True when `point` (panel coordinates) is inside the *currently rendered*
    /// shape. The panel is far bigger than the island, so this is what keeps
    /// menu-bar clicks working: everything outside falls through.
    public static func hitTest(_ point: CGPoint, metrics: NotchScreenMetrics,
                               size: NotchHUDSize) -> Bool {
        let l = layout(metrics, size: size)
        if l.island.contains(point) { return true }
        if let left = l.leftEar, left.contains(point) { return true }
        if let right = l.rightEar, right.contains(point) { return true }
        return false
    }
}
