import Foundation

/// The visible eye opening of a break face: an eyeball ellipse cut by the upper lid line.
/// Pure geometry (any consistent coordinate space) used to size and place the iris so the
/// whole iris circle stays visible instead of being sliced by the lid.
public struct BreakEyeOpening {
    /// Eyeball ellipse.
    public var cx: Double, cy: Double, rx: Double, ry: Double
    /// y of the upper lid edge at x (y grows downward; the opening is below it).
    public var lidY: (Double) -> Double
    /// Clearance kept between the iris and the lid edge (the lid casts a shadow there).
    public var lidMargin: Double

    public init(cx: Double, cy: Double, rx: Double, ry: Double,
                lidMargin: Double = 0, lidY: @escaping (Double) -> Double) {
        self.cx = cx; self.cy = cy; self.rx = rx; self.ry = ry
        self.lidMargin = lidMargin
        self.lidY = lidY
    }

    /// A face counts as "open" (lids at the open state the iris was fitted to) while its lid openness
    /// is at least this. Below it the lids are closing or opening as an animation (a blink, the
    /// fade-in, the final shut) and may cover the iris like a real eyelid; the iris keeps its fitted
    /// size and position meanwhile.
    public static let openThreshold = 0.99

    /// A circle placed in the opening.
    public struct Circle: Equatable, Sendable {
        public var x: Double, y: Double, radius: Double
    }

    // MARK: Containment

    /// True when the whole circle lies inside the eyeball and below the lid edge (+ margin).
    public func contains(x: Double, y: Double, radius r: Double) -> Bool {
        // inside the ellipse (tiny tolerance for the sampling)
        for k in 0..<96 {
            let a = Double(k) / 96 * 2 * .pi
            let px = (x + cos(a) * r - cx) / rx, py = (y + sin(a) * r - cy) / ry
            if px * px + py * py > 1.0005 { return false }
        }
        // below the lid over the circle's whole width
        for k in 0...64 {
            let dx = (Double(k) / 64 * 2 - 1) * r
            let top = y - (r * r - dx * dx).squareRoot()
            if top < lidY(x + dx) + lidMargin - 0.001 { return false }
        }
        return true
    }

    /// Vertical opening (lid edge to the bottom of the eyeball) at x.
    public func height(atX x: Double) -> Double {
        let u = (x - cx) / rx
        guard abs(u) < 1 else { return 0 }
        return max(0, cy + ry * (1 - u * u).squareRoot() - lidY(x))
    }

    // MARK: Largest inscribed circle

    /// Radius of the biggest circle centred at (x, y) that fits (negative = centre not visible).
    public func clearance(x: Double, y: Double) -> Double {
        let ex = (x - cx) / rx, ey = (y - cy) / ry
        guard ex * ex + ey * ey < 1 else { return -1 }
        var d = Double.infinity
        for k in 0..<72 {
            let a = Double(k) / 72 * 2 * .pi
            d = min(d, hypot(cx + cos(a) * rx - x, cy + sin(a) * ry - y))
        }
        // a vertical drop to the lid edge is a safe over-estimate of the distance to the lid;
        // the minimum over the sampled lid curve gives the true distance
        var lid = Double.infinity
        let steps = 48
        for k in 0...steps {
            let px = cx - rx + 2 * rx * Double(k) / Double(steps)
            lid = min(lid, hypot(px - x, lidY(px) - y))
        }
        guard y > lidY(x) else { return -1 }
        return min(d, lid - lidMargin)
    }

    /// The biggest circle that fits. With `centeredAtX` the centre is pulled towards that x
    /// (a slanted lid leaves the most room on the outer side; this keeps the eyes from looking
    /// apart) at the cost of a slightly smaller circle, and the choice is unique and stable.
    public func largestCircle(centeredAtX: Double? = nil, pull: Double = 0.5) -> Circle {
        func score(_ x: Double, _ y: Double) -> Double {
            let c = clearance(x: x, y: y)
            guard let h = centeredAtX else { return c }
            return c - pull * abs(x - h)
        }
        var best = (x: cx, y: cy, s: -Double.infinity)
        let n = 16
        for i in 0...n {
            for j in 0...n {
                let x = cx - rx + 2 * rx * Double(i) / Double(n)
                let y = cy - ry + 2 * ry * Double(j) / Double(n)
                let s = score(x, y)
                if s > best.s { best = (x, y, s) }
            }
        }
        var step = max(rx, ry) / Double(n)
        for _ in 0..<24 {
            var moved = false
            for (dx, dy) in [(1.0, 0.0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)] {
                let x = best.x + dx * step, y = best.y + dy * step
                let s = score(x, y)
                if s > best.s { best = (x, y, s); moved = true }
            }
            if !moved { step *= 0.6 }
        }
        return Circle(x: best.x, y: best.y, radius: max(0, clearance(x: best.x, y: best.y)))
    }

    // MARK: Fit

    /// Places an iris of at most `radius` so that it is fully visible. The size is capped at
    /// `fill` of the largest circle that fits, the centre goes to `anchor` (the largest circle's
    /// centre unless given) displaced by `offset`, pulled back along the displacement just as far
    /// as needed to keep the whole circle inside.
    public func fit(radius: Double, fill: Double = 0.92,
                    offset: (x: Double, y: Double) = (0, 0),
                    anchor: Circle? = nil) -> Circle {
        let a = anchor ?? largestCircle()
        var r = min(radius, a.radius * fill)
        while r > 1, !contains(x: a.x, y: a.y, radius: r) { r *= 0.97 }
        let tx = a.x + offset.x, ty = a.y + offset.y
        if contains(x: tx, y: ty, radius: r) { return Circle(x: tx, y: ty, radius: r) }
        var lo = 0.0, hi = 1.0
        for _ in 0..<18 {
            let m = (lo + hi) / 2
            if contains(x: a.x + offset.x * m, y: a.y + offset.y * m, radius: r) { lo = m } else { hi = m }
        }
        return Circle(x: a.x + offset.x * lo, y: a.y + offset.y * lo, radius: r)
    }
}
