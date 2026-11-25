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

/// Liquid-glass switch — replaces `.toggleStyle(.switch)`, whose AppKit track
/// renders as an opaque system-blue/grey block on the dark-glass panels.
/// A frosted capsule track that fills with `tint` when on, and a glossy knob
/// that slides with `DS.Motion.snappy`.
struct GlassSwitchStyle: ToggleStyle {
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? tint.opacity(0.85) : .white.opacity(0.08))
                    .glassCapsule(strokeOpacity: configuration.isOn ? 0.35 : 0.18)
                    .shadow(color: configuration.isOn ? tint.opacity(0.45) : .clear, radius: 6)
                Circle()
                    .fill(LinearGradient(colors: [.white, .white.opacity(0.78)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .padding(2.5)
            }
            .frame(width: 42, height: 24)
            .contentShape(Capsule())
            .onTapGesture {
                withAnimation(DS.Motion.snappy) { configuration.isOn.toggle() }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(configuration.isOn ? "On" : "Off")
        }
    }
}

extension ToggleStyle where Self == GlassSwitchStyle {
    static func glassSwitch(tint: Color) -> GlassSwitchStyle { GlassSwitchStyle(tint: tint) }
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
