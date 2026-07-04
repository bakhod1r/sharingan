import SwiftUI

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