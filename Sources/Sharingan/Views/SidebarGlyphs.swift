import SwiftUI
import SharinganCore

/// The two custom marks the sidebar uses for the default category and project
/// icons — hand-drawn to match the supplied artwork rather than approximated by
/// an SF Symbol. Everywhere a category/project icon renders as a plain view
/// (the sidebar rows, the editor preview, the icon picker) routes through
/// `CategoryGlyph`, which swaps these two in and falls back to `Image(system:)`
/// for every other choice. Menu rows keep using the SF Symbol name directly,
/// since a `Label` can only take a system image.

/// Connected-nodes mark: two squares linked across the top and a third hanging
/// below, linked back — the default **category** glyph.
struct GraphNodeGlyph: View {
    var color: Color
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let lw = s * 0.12
            let sq = s * 0.30
            let leftX = sq / 2 + lw / 2
            let rightX = s - sq / 2 - lw / 2
            let topY = sq / 2 + lw / 2
            let botX = s * 0.5
            let botY = s - sq / 2 - lw / 2
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: leftX, y: topY))
                    p.addLine(to: CGPoint(x: rightX, y: topY))
                    p.move(to: CGPoint(x: leftX, y: topY))
                    p.addLine(to: CGPoint(x: botX, y: botY))
                }
                .stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round))
                node(sq, lw).position(x: leftX, y: topY)
                node(sq, lw).position(x: rightX, y: topY)
                node(sq, lw).position(x: botX, y: botY)
            }
            .frame(width: s, height: s)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
    private func node(_ sq: CGFloat, _ lw: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: sq * 0.3, style: .continuous)
            .strokeBorder(color, lineWidth: lw)
            .frame(width: sq, height: sq)
    }
}

/// Four rounded squares in a 2×2 — the default **project** glyph.
struct GridGlyph: View {
    var color: Color
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let lw = s * 0.12
            let sq = s * 0.40
            let gap = s - 2 * sq
            VStack(spacing: gap) {
                HStack(spacing: gap) { cell(sq, lw); cell(sq, lw) }
                HStack(spacing: gap) { cell(sq, lw); cell(sq, lw) }
            }
            .frame(width: s, height: s)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
    private func cell(_ sq: CGFloat, _ lw: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: sq * 0.28, style: .continuous)
            .strokeBorder(color, lineWidth: lw)
            .frame(width: sq, height: sq)
    }
}

/// Renders a category/project icon symbol: the two custom defaults draw their
/// hand-made glyph, everything else is a system image. One entry point so the
/// sidebar, preview and picker stay identical.
struct CategoryGlyph: View {
    let symbol: String
    var color: Color = .white
    var size: CGFloat = 13

    var body: some View {
        switch symbol {
        case TaskCategory.defaultCategoryIcon:
            GraphNodeGlyph(color: color).frame(width: size, height: size)
        case TaskCategory.defaultProjectIcon:
            GridGlyph(color: color).frame(width: size, height: size)
        default:
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(color)
        }
    }
}
