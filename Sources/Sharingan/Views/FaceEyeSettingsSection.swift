import SwiftUI
import SharinganCore

/// Wrapping row layout for chips (no scrolling, lines break at the width).
struct ChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 400, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = arrange(width: bounds.width, subviews: subviews)
        for (i, p) in r.origins.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y),
                              proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxW: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            maxW = max(maxW, x - spacing)
        }
        return (CGSize(width: maxW, height: y + rowH), origins)
    }
}

/// One selectable pill; on = accent red border and tint.
struct SettingsChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    private static let accent = Color(red: 0.878, green: 0.196, blue: 0.173) // #e0322c

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(isOn ? .white : .white.opacity(0.65))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(isOn ? Self.accent.opacity(0.2) : Color.black.opacity(0.33)))
                .overlay(Capsule().strokeBorder(isOn ? Self.accent : Color.white.opacity(0.13), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The "Face and eye" Settings section content: Mode, then either the Fixed
/// rows or the Random pool controls.
struct FaceEyeSettingsSection: View {
    @Binding var settings: PomodoroSettings
    /// One sample drawn from the pool for the Random preview ("Shuffle" re-rolls).
    @State private var sample: BreakLook?

    private var isRandom: Bool { settings.breakFaceEyeMode == .random }

    private var previewLook: BreakLook {
        if isRandom, let sample { return sample }
        return BreakFaceEyeRandomizer.fixedLook(settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()
                preview(previewLook)
                Spacer()
            }
            .padding(.vertical, 6)

            if isRandom {
                HStack {
                    Spacer()
                    Button("Shuffle") { shuffle() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Spacer()
                }
            }

            row("Mode") {
                GlassSegmentedPicker(selection: $settings.breakFaceEyeMode,
                                     cases: BreakFaceEyeMode.allCases, label: \.label)
                    .frame(width: 260)
            }

            if isRandom { randomRows } else { fixedRows }
        }
        .onChange(of: settings.breakFaceEyeMode) { shuffle() }
        .onChange(of: settings.breakRandomFaces) { shuffle() }
        .onChange(of: settings.breakRandomEyes) { shuffle() }
        .onChange(of: settings.breakRandomPairing) { shuffle() }
        .onAppear { shuffle() }
    }

    private func shuffle() {
        guard isRandom else { sample = nil; return }
        var rng = SystemRandomNumberGenerator()
        sample = BreakFaceEyeRandomizer.look(settings: settings, previous: sample, using: &rng)
    }

    // MARK: Fixed

    @ViewBuilder private var fixedRows: some View {
        row("Face") {
            GlassSegmentedPicker(selection: $settings.breakEyeShape,
                                 cases: BreakEyeShape.allCases, label: \.label)
                .frame(width: 260)
        }
        row("Eye") {
            GlassSegmentedPicker(selection: $settings.breakIrisStyle,
                                 cases: BreakIrisStyle.allCases, label: \.label)
                .frame(width: 260)
        }
        if settings.breakEyeShape != .sharingan || settings.breakIrisStyle != .sharingan {
            caption(faceCaption)
        }
        row(settings.sharinganStyleRight == nil ? "Sharingan eye" : "Left eye") {
            SpinningIrisSwatch(style: settings.sharinganStyle)
            Picker("", selection: $settings.sharinganStyle) {
                ForEach(SharinganStyle.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden().pickerStyle(.menu).glassMenu().fixedSize()
        }
        caption("Used everywhere the mark appears: break screen, desktop wallpaper, the menu-bar icon and the Dock icon.")
    }

    private var faceCaption: String {
        let base = "Break screen only. Wallpaper and icons keep the Sharingan eye."
        switch settings.breakEyeShape {
        case .sharingan:  return base
        case .lookingFor: return base + " Plays the intro at break start and the fire-and-close outro at break end."
        case .angry:      return base + " Plays the intro at break start and fades the eyes shut at break end."
        }
    }

    // MARK: Random

    @ViewBuilder private var randomRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Faces").font(.system(.caption, design: .rounded)).foregroundStyle(.white.opacity(0.65))
            ChipFlow {
                ForEach(BreakEyeShape.allCases) { f in
                    SettingsChip(title: f.label, isOn: settings.breakRandomFaces.contains(f)) {
                        toggle(f, in: &settings.breakRandomFaces, order: BreakEyeShape.allCases)
                    }
                }
            }
        }
        VStack(alignment: .leading, spacing: 6) {
            Text("Eyes").font(.system(.caption, design: .rounded)).foregroundStyle(.white.opacity(0.65))
            ChipFlow {
                ForEach(BreakEyeChoice.allChoices) { e in
                    SettingsChip(title: e.label, isOn: settings.breakRandomEyes.contains(e)) {
                        toggle(e, in: &settings.breakRandomEyes, order: BreakEyeChoice.allChoices)
                    }
                }
            }
        }
        row("Change") {
            GlassSegmentedPicker(selection: $settings.breakRandomChange,
                                 cases: BreakRandomChange.allCases, label: \.label)
                .frame(width: 260)
        }
        row("Left / right") {
            GlassSegmentedPicker(selection: $settings.breakRandomPairing,
                                 cases: BreakRandomPairing.allCases, label: \.label)
                .frame(width: 260)
        }
        randomCaption
    }

    @ViewBuilder private var randomCaption: some View {
        if settings.breakRandomFaces.isEmpty {
            Text("Pick at least one face. Until then the break uses the Fixed choice.")
                .font(.system(.caption, design: .rounded)).foregroundStyle(Color(red: 1, green: 0.54, blue: 0.5))
        } else if settings.breakRandomEyes.isEmpty {
            Text("Pick at least one eye. Until then the break uses the Fixed choice.")
                .font(.system(.caption, design: .rounded)).foregroundStyle(Color(red: 1, green: 0.54, blue: 0.5))
        } else {
            let when = settings.breakRandomChange == .eachBreak
                ? "Drawn at the start of every break; the face stays for the whole break."
                : "The eyes are re-drawn at every exercise step; the face stays for the whole break."
            let pair = settings.breakRandomPairing == .same
                ? "Both eyes match."
                : "Left and right differ, but never mix Original with Sharingan."
            caption("\(settings.breakRandomFaces.count) faces × \(settings.breakRandomEyes.count) eyes. \(when) \(pair) Break screen only.")
        }
    }

    /// Toggle keeping the pool in canonical order (stable JSON, stable chips).
    private func toggle<T: Hashable>(_ v: T, in arr: inout [T], order: [T]) {
        var s = Set(arr)
        if s.contains(v) { s.remove(v) } else { s.insert(v) }
        arr = order.filter { s.contains($0) }
    }

    // MARK: Pieces

    private func row<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        HStack {
            Text(title).font(.system(.body, design: .rounded))
            Spacer()
            content()
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.white.opacity(0.65))
    }

    @ViewBuilder private func preview(_ look: BreakLook) -> some View {
        switch look.face {
        case .lookingFor:
            LookingForEyePair(direction: "center", gaze: .center,
                              eyeSize: 34, style: look.leftStyle,
                              rightStyle: look.rightStyle,
                              evolves: false, iris: look.iris, skipIntro: true)
        case .angry:
            AngryEyePair(direction: "center", gaze: .center,
                         eyeSize: 30, style: look.leftStyle,
                         rightStyle: look.rightStyle,
                         evolves: false, iris: look.iris, skipIntro: true)
        case .sharingan:
            MoveEyePair(direction: "center", gaze: .center,
                        eyeSize: 54, style: look.leftStyle,
                        rightStyle: look.rightStyle,
                        evolves: false, iris: look.iris)
        }
    }
}
