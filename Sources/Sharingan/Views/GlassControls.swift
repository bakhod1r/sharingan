import SwiftUI

/// Liquid-glass segmented control — replaces `.pickerStyle(.segmented)`
/// everywhere in Settings, where the AppKit segmented control rendered as an
/// opaque blue block that ignored the app's dark-glass design. Built on the
/// same `glassCapsule`/`DS.Motion` primitives as the rest of the app rather
/// than inventing new chrome.
///
/// Anatomy: a translucent capsule track with a frosted thumb that *slides*
/// between segments (matchedGeometryEffect) instead of teleporting.
struct GlassSegmentedPicker<T: Hashable>: View {
    @Binding var selection: T
    let options: [(value: T, label: String)]
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Text(option.label)
                    .font(.system(.callout, design: .rounded).weight(selected ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(selected ? 1 : 0.65))
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .contentShape(Capsule())
                    .background {
                        if selected {
                            Capsule()
                                .fill(.white.opacity(0.22))
                                .glassCapsule(strokeOpacity: 0.4)
                                .matchedGeometryEffect(id: "thumb", in: thumb)
                        }
                    }
                    .onTapGesture {
                        withAnimation(DS.Motion.snappy) { selection = option.value }
                    }
            }
        }
        .padding(3)
        .glassCapsule()
    }
}

extension GlassSegmentedPicker {
    /// Sugar for CaseIterable enums with a `label`.
    init(selection: Binding<T>, cases: [T], label: (T) -> String) {
        self.init(selection: selection,
                  options: cases.map { ($0, label($0)) })
    }
}

/// Liquid-glass pill button — for the plain-text Settings action buttons
/// (Preview, Stop, Check Now…) that previously rendered as unstyled system
/// buttons floating on the glass panels.
struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.callout, design: .rounded).weight(.medium))
            .foregroundStyle(.white.opacity(0.95))
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .glassCapsule()
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(DS.Motion.snappy, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GlassButtonStyle {
    static var glass: GlassButtonStyle { GlassButtonStyle() }
}

/// Dresses a `.pickerStyle(.menu)` dropdown in the same glass capsule as
/// `GlassSegmentedPicker`/`.glass` buttons. AppKit still renders the actual
/// pop-up menu (SwiftUI has no supported hook into that chrome), but the
/// closed-state control — the part visible everywhere in Settings — now
/// matches the rest of the liquid-glass surface instead of sitting there as
/// a plain system control.
struct GlassMenuStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .tint(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .glassCapsule()
    }
}

extension View {
    func glassMenu() -> some View { modifier(GlassMenuStyle()) }
}
