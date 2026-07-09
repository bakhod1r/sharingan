import SwiftUI

/// A sharp, tilted almond eye — drawn as the LEFT eye: the outer corner sits at
/// `minX` (high) and the inner/nasal corner at `maxX` (low), so a mirrored pair
/// slants down toward the centre.
///
/// The old PNG-based `SharinganEyeView`/`SharinganEyePair` were replaced by the
/// vector `MoveEyeView`/`MoveEyePair` (see MoveEyesView.swift). This shape stays
/// because `EyeExerciseAnimation` still draws with it.
struct AlmondEyeShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        let outer = CGPoint(x: r.minX, y: r.minY + h * 0.50)   // outer corner, near mid
        let inner = CGPoint(x: r.maxX, y: r.minY + h * 0.52)   // nasal corner, near mid
        p.move(to: outer)
        // Human eye: domed upper lid arching well above the level corners.
        p.addQuadCurve(to: inner, control: CGPoint(x: r.minX + w * 0.45, y: r.minY - h * 0.24))
        // Shallow lower lid — a gentle curve, as under a real eye.
        p.addQuadCurve(to: outer, control: CGPoint(x: r.minX + w * 0.50, y: r.maxY + h * 0.06))
        p.closeSubpath()
        return p
    }
}
