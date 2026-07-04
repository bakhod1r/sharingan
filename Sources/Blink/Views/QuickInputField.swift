import SwiftUI
import BlinkCore

struct QuickInputField: View {
    @ObservedObject var timer: PomodoroTimer
    @State private var text: String = ""
    @State private var error: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.magnifyingglass")
                .foregroundStyle(.white.opacity(0.6))
            TextField("25 min, 2h 30m, 5pm, Add 5 min…",
                      text: $text)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .onSubmit(submit)
            if !text.isEmpty {
                Button {
                    submit()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(timer.phase.glow)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glassCapsule(material: .regular)
        .overlay(alignment: .bottom) {
            if let e = error {
                Text(e)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.red)
                    .padding(.top, 2)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: error)
    }

    private func submit() {
        guard let parsed = NaturalLanguageParser.parse(text) else {
            error = "Unrecognized: \(text)"
            return
        }
        error = nil
        timer.applyParsed(parsed)
        if case .setDuration = parsed.kind {
            if timer.isRunning == false { timer.start() }
        }
        text = ""
    }
}