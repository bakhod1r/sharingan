import Foundation

/// Which edge the macOS Dock occupies, derived from the difference between a
/// screen's full frame and its visibleFrame. An auto-hidden Dock leaves the
/// two (nearly) equal and reads as `.bottom`.
public enum DockSide: Equatable, Sendable { case bottom, left, right }

/// Pure placement math for the Dock widget pill. Extracted (like
/// NotchGeometry) so corner-vs-center decisions are unit-testable without
/// AppKit windows.
public enum DockWidgetGeometry {
    public static func side(visibleFrame vis: CGRect, fullFrame full: CGRect) -> DockSide {
        if vis.minX > full.minX { return .left }
        if vis.maxX < full.maxX { return .right }
        return .bottom
    }

    /// Where the pill's window goes: flush above a bottom Dock at the chosen
    /// end, or flush beside a vertical Dock at its vertical center (the
    /// Position setting is a horizontal-Dock concept; a corner-parked pill
    /// next to a vertical Dock is exactly the bug this replaces).
    public static func origin(size: CGSize, alignment: DockWidgetAlignment,
                              visibleFrame vis: CGRect, fullFrame full: CGRect) -> CGPoint {
        switch side(visibleFrame: vis, fullFrame: full) {
        case .left:
            return CGPoint(x: vis.minX + 8, y: vis.midY - size.height / 2)
        case .right:
            return CGPoint(x: vis.maxX - size.width - 8, y: vis.midY - size.height / 2)
        case .bottom:
            let x: CGFloat
            switch alignment {
            case .leading:  x = vis.minX + 16
            case .center:   x = vis.midX - size.width / 2
            case .trailing: x = vis.maxX - size.width - 16
            }
            return CGPoint(x: x, y: vis.minY + 4)
        }
    }

    /// Which container edge the pill hugs, so hover expansion grows away from
    /// the Dock. Reuses DockWidgetAlignment as the anchor vocabulary.
    public static func expandAnchor(alignment: DockWidgetAlignment,
                                    visibleFrame vis: CGRect, fullFrame full: CGRect) -> DockWidgetAlignment {
        switch side(visibleFrame: vis, fullFrame: full) {
        case .left:   return .leading
        case .right:  return .trailing
        case .bottom: return alignment
        }
    }

    /// Clamp a custom (user-dragged) origin for a widget of `size` into
    /// `visibleFrame`, keeping a repositioned pill on screen after a display
    /// change.
    public static func clamp(origin: CGPoint, size: CGSize, visibleFrame vis: CGRect) -> CGPoint {
        let x = min(max(origin.x, vis.minX), max(vis.minX, vis.maxX - size.width))
        let y = min(max(origin.y, vis.minY), max(vis.minY, vis.maxY - size.height))
        return CGPoint(x: x, y: y)
    }

    /// Hover-expand anchor for a custom-positioned (undocked) pill: whichever
    /// half of the screen its frame's midX falls in — left half opens
    /// rightward (`.leading`), right half opens leftward (`.trailing`).
    public static func expandAnchor(customOrigin origin: CGPoint, size: CGSize,
                                    visibleFrame vis: CGRect) -> DockWidgetAlignment {
        (origin.x + size.width / 2) <= vis.midX ? .leading : .trailing
    }
}
