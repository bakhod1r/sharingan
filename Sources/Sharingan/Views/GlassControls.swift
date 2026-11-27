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

/// Liquid-glass dropdown — replaces `.pickerStyle(.menu)` (+ the old
/// `.glassMenu()` wrapper). A menu-style Picker always draws the AppKit
/// NSPopUpButton bezel, so wrapping it in a capsule gave double chrome. Here the
/// closed state is our own label (text + up/down chevron) in a glass capsule,
/// and a borderless `Menu` supplies only the pop-up list.
struct GlassMenuPicker<T: Hashable>: View {
    @Binding var selection: T
    let options: [(value: T, label: String)]

    private var currentLabel: String {
        options.first { $0.value == selection }?.label ?? ""
    }

    var body: some View {
        Menu {
            Picker("", selection: $selection) {
                ForEach(options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 6) {
                Text(currentLabel)
                    .font(.system(.callout, design: .rounded).weight(.medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .opacity(0.7)
            }
            .foregroundStyle(.white.opacity(0.95))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .glassCapsule()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text("Options"))
        .accessibilityValue(Text(currentLabel))
    }
}

extension GlassMenuPicker {
    /// Sugar for CaseIterable-style lists with a label closure.
    init(selection: Binding<T>, cases: [T], label: (T) -> String) {
        self.init(selection: selection,
                  options: cases.map { ($0, label($0)) })
    }
}

/// Liquid-glass slider — replaces `Slider`, whose AppKit track/knob render as
/// system blue on the dark-glass panels. Frosted capsule track, a tinted fill
/// with a soft glow, and the same glossy knob as `GlassSwitchStyle`.
struct GlassSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    var tint: Color = .accentColor

    private let knob: CGFloat = 18

    init(value: Binding<Double>, in range: ClosedRange<Double>,
         step: Double? = nil, tint: Color = .accentColor) {
        self._value = value
        self.range = range
        self.step = step
        self.tint = tint
    }

    /// Int-backed convenience.
    init(value: Binding<Int>, in range: ClosedRange<Int>,
         step: Int = 1, tint: Color = .accentColor) {
        self.init(value: Binding(get: { Double(value.wrappedValue) },
                                 set: { value.wrappedValue = Int($0.rounded()) }),
                  in: Double(range.lowerBound)...Double(range.upperBound),
                  step: Double(step), tint: tint)
    }

    /// Float-backed convenience (TTS rate/pitch settings are Float).
    init(value: Binding<Float>, in range: ClosedRange<Float>,
         step: Float? = nil, tint: Color = .accentColor) {
        self.init(value: Binding(get: { Double(value.wrappedValue) },
                                 set: { value.wrappedValue = Float($0) }),
                  in: Double(range.lowerBound)...Double(range.upperBound),
                  step: step.map(Double.init), tint: tint)
    }

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    private func snapped(_ raw: Double) -> Double {
        var v = min(max(raw, range.lowerBound), range.upperBound)
        if let step, step > 0 {
            v = range.lowerBound + ((v - range.lowerBound) / step).rounded() * step
            v = min(max(v, range.lowerBound), range.upperBound)
        }
        return v
    }

    var body: some View {
        GeometryReader { geo in
            let travel = max(geo.size.width - knob, 1)
            let x = CGFloat(fraction) * travel
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.08))
                    .glassCapsule(strokeOpacity: 0.18)
                    .frame(height: 6)
                Capsule()
                    .fill(tint.opacity(0.85))
                    .frame(width: x + knob / 2, height: 6)
                    .shadow(color: tint.opacity(0.45), radius: 5)
                Circle()
                    .fill(LinearGradient(colors: [.white, .white.opacity(0.78)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .frame(width: knob, height: knob)
                    .offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    let f = Double((g.location.x - knob / 2) / travel)
                    value = snapped(range.lowerBound + f * (range.upperBound - range.lowerBound))
                }
            )
        }
        .frame(height: 22)
        .accessibilityRepresentation {
            if let step {
                Slider(value: $value, in: range, step: step)
            } else {
                Slider(value: $value, in: range)
            }
        }
    }
}
