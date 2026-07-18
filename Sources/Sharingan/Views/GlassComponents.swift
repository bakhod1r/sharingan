import SwiftUI
import SharinganCore

// MARK: - Liquid Glass primitives

struct GlassBackground<S: InsettableShape & Shape>: ViewModifier {
    let shape: S
    var material: Material = .ultraThin
    var strokeOpacity: Double = 0.18

    func body(content: Content) -> some View {
        let insetShape = shape.inset(by: 0.5)
        return content
            .background(material, in: shape)
            .overlay {
                insetShape
                    .stroke(LinearGradient(
                        colors: [Color.white.opacity(0.55),
                                 Color.white.opacity(strokeOpacity)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing),
                        lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .overlay {
                shape
                    .stroke(Color.white.opacity(0.06), lineWidth: 4)
                    .blur(radius: 6)
                    .offset(x: 0, y: 2)
                    .mask(shape)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func glass<S: InsettableShape & Shape>(_ shape: S,
                  material: Material = .ultraThin,
                  strokeOpacity: Double = 0.18) -> some View {
        modifier(GlassBackground(shape: shape,
                                 material: material,
                                 strokeOpacity: strokeOpacity))
    }

    func glassRounded(_ radius: CGFloat = 24,
                      material: Material = .ultraThin,
                      strokeOpacity: Double = 0.18) -> some View {
        glass(RoundedRectangle(cornerRadius: radius, style: .continuous),
              material: material, strokeOpacity: strokeOpacity)
    }

    func glassCapsule(material: Material = .ultraThin,
                      strokeOpacity: Double = 0.18) -> some View {
        glass(Capsule(), material: material, strokeOpacity: strokeOpacity)
    }

    func liquidShadow(color: Color = .black.opacity(0.35),
                      radius: CGFloat = 20, y: CGFloat = 14) -> some View {
        shadow(color: color, radius: radius, x: 0, y: y)
    }

    func specular() -> some View {
        overlay(alignment: .top) {
            LinearGradient(
                colors: [Color.white.opacity(0.35), .clear],
                startPoint: .top, endPoint: .center
            )
            .blendMode(.screen)
            .mask(LinearGradient(colors: [.white, .clear],
                                 startPoint: .top, endPoint: .center))
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Press feedback

/// A single, calm press interaction used across every interactive surface so
/// clicks feel intentional instead of jittery. Subtle scale + dim, spring-eased.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1, anchor: .center)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(DS.Motion.snappy,
                       value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    /// Subtle press feedback for large tappable surfaces (cards, glass buttons).
    static var pressable: PressableStyle { PressableStyle() }
    /// Gentler feedback for small controls where a big scale looks twitchy.
    static var pressableSubtle: PressableStyle { PressableStyle(scale: 0.92) }
}

// MARK: - macOS System Settings-style grouped card

/// Lays rows in a rounded card with an inset hairline between each — the
/// grouped-list look of macOS System Settings. Every row gets uniform padding,
/// so section content stays plain (no per-control padding needed).
private struct _SettingsRows: _VariadicView_MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        return VStack(spacing: 0) {
            ForEach(children) { child in
                child
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                if child.id != last {
                    Divider()
                        .overlay(Color.white.opacity(0.12))
                        .padding(.leading, 16)
                }
            }
        }
    }
}

struct SettingsCard<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        _VariadicView.Tree(_SettingsRows()) { content }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Gradient mesh backdrop (liquid ambiance)

struct LiquidMeshBackground: View {
    var colors: [Color]

    private static func bubble(radius: CGFloat = 260) -> RadialGradient {
        RadialGradient(colors: [.white.opacity(0.55), .clear],
                       center: .center, startRadius: 0, endRadius: radius)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: colors,
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Self.bubble())
                .frame(width: 600, height: 600)
                .offset(x: -180, y: -260).opacity(0.55)
            Circle().fill(Self.bubble(radius: 240))
                .frame(width: 520, height: 520)
                .offset(x: 240, y: 220).opacity(0.45)
            Circle().fill(Self.bubble(radius: 220))
                .frame(width: 480, height: 480)
                .offset(x: -60, y: 360).opacity(0.35)
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.18))
        }
        .ignoresSafeArea()
    }
}
/// The app's window surface: the deep theme gradient, darkened for text
/// contrast, with a screen-blended highlight in the top-leading corner.
/// `MainWindowView` fills the whole window with it, and the notch island wears
/// the same recipe cut to its silhouette — one definition, so the island and
/// the app's windows are the same surface by construction rather than two
/// approximations of each other.
struct ThemeWindowWash: View {
    var theme: SharinganTheme
    /// The corner highlight's reach. 620 suits a full window; small surfaces
    /// (the notch body, the live ears) pass their own so the highlight scales
    /// with them instead of washing them out.
    var highlightRadius: CGFloat = 620

    var body: some View {
        // `surface` is already a dark, text-safe base (see SharinganTheme), so the
        // darkening ramp only needs to deepen the bottom a touch for depth, and the
        // corner highlight is kept gentle — it lifts the top-leading corner without
        // ever blowing it out to a light patch that would swallow the white text.
        let colors = theme.surface
        ZStack {
            LinearGradient(colors: colors,
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            LinearGradient(colors: [Color.black.opacity(0.0),
                                    Color.black.opacity(0.28)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [(colors.first ?? .blue).opacity(0.55), .clear],
                           center: .topLeading, startRadius: 0,
                           endRadius: highlightRadius)
                .blendMode(.screen)
            // The Hacker theme's signature: green digital rain falling behind the
            // UI. Kept dim so the white content still reads on top.
            if theme.hasMatrixRain {
                MatrixRainView(color: theme.accent)
                    .opacity(0.5)
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Matrix digital rain (Hacker theme)

/// A lightweight "digital rain" — columns of glyphs falling down the surface,
/// the lead glyph bright and a fading green trail behind it. Drawn in a single
/// `Canvas` off a `TimelineView` clock so the whole effect is one layer with no
/// per-glyph views. Deterministic per column (seeded speeds/offsets) so it looks
/// organic without storing mutable state.
struct MatrixRainView: View {
    var color: Color

    private static let glyphs = Array("01ｱｲｳｴｵｶｷｸｹｺｻｼｽｾ日ﾊﾋﾎ012789ﾘﾙﾚﾜ")
    private let cell: CGFloat = 14
    private let fontSize: CGFloat = 13

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let cols = max(1, Int(size.width / cell))
                let rows = max(1, Int(size.height / cell))
                for c in 0..<cols {
                    // Deterministic per-column speed and phase from a cheap hash.
                    let seed = Double((c &* 2654435761) & 0xffff) / 0xffff
                    let speed = 4.0 + seed * 10.0          // rows per second
                    let head = (t * speed + seed * Double(rows)) .truncatingRemainder(dividingBy: Double(rows + 12))
                    let trail = 10
                    for k in 0..<trail {
                        let row = Int(head) - k
                        guard row >= 0, row < rows else { continue }
                        let fade = 1.0 - Double(k) / Double(trail)
                        let gi = (c &* 31 &+ row &* 17 &+ Int(t * 8)) % Self.glyphs.count
                        let glyph = Self.glyphs[(gi + Self.glyphs.count) % Self.glyphs.count]
                        let isHead = k == 0
                        let text = Text(String(glyph))
                            .font(.system(size: fontSize, weight: isHead ? .bold : .regular,
                                          design: .monospaced))
                            .foregroundStyle(isHead ? Color.white.opacity(0.95)
                                                    : color.opacity(fade * 0.85))
                        ctx.draw(text, at: CGPoint(x: CGFloat(c) * cell + cell / 2,
                                                   y: CGFloat(row) * cell + cell / 2))
                    }
                }
            }
        }
    }
}
