import Foundation

/// Face-space geometry of the Looking-for eye (left eye; the right eye is its mirror image).
/// Shared by the renderer and the choreography so both agree on where the eye opening is.
extension LookingForEyesPose {
    /// 0 = resting eye size, 1 = the bulged angry eye of the frown phase.
    public var bulge: Double { min(1, max(0, (ringBottom - 507) / 14)) }
    public var ringLeft: Double { axis + ringLeftRel }
    public var ringRX: Double { 162 * (1 + 0.112 * bulge) }
    public var ringRY: Double { 143 * (1 + 0.15 * bulge) }
    public var whiteRX: Double { 137 * (1 + 0.08 * bulge) }
    public var whiteRY: Double { 110.4 * (1 + 0.04 * bulge) }
    public var whiteCX: Double { ringLeft + 178.5 + 14.2 * bulge }
    public var whiteCY: Double { ringBottom - whiteGap - whiteRY }
    /// Centre of the iris / pupil of the left eye.
    public var irisCenter: (x: Double, y: Double) {
        (ringLeft + 185.5 + pupilShift, pupilY + 84 - 85.7)
    }

    /// x positions of the 9 `lid` samples.
    public var lidXs: [Double] { (0..<9).map { ringLeft + 12 + 34.5 * Double($0) } }

    /// y of the lid edge at x (the renderer's clip line; extended along its end slopes).
    public func lidEdgeY(atX x: Double) -> Double {
        let xs = lidXs, ys = lid.map { $0 - 3 }
        let step = 34.5
        if x <= xs[0] { return ys[0] + (ys[1] - ys[0]) / step * (x - xs[0]) }
        if x >= xs[8] { return ys[8] + (ys[8] - ys[7]) / step * (x - xs[8]) }
        let f = (x - xs[0]) / step
        let i = min(7, Int(f))
        let k = f - Double(i)
        return ys[i] + (ys[i + 1] - ys[i]) * k
    }

    /// The visible eye opening of the left eye (white of the eye cut by the lid).
    public func eyeOpening(lidMargin: Double = 0) -> BreakEyeOpening {
        let p = self
        return BreakEyeOpening(cx: whiteCX, cy: whiteCY, rx: whiteRX, ry: whiteRY,
                               lidMargin: lidMargin) { p.lidEdgeY(atX: $0) }
    }
}
