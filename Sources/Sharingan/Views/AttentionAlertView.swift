import SwiftUI
import SharinganCore

/// What the red tint shows. A shared model so the panel can update the text
/// in place (once per second) instead of being rebuilt.
@MainActor
final class AttentionAlertModel: ObservableObject {
    @Published var state: AttentionState = .attentive
    @Published var taskTitle: String?
}

/// Full-screen red tint. Click-through (the panel ignores mouse events), so it
/// only has to look right. The "pulse" is a one-shot ease per update tick, not
/// a forever animation (ForeverAnimationGuard keeps SwiftUI off the display link).
struct AttentionAlertView: View {
    @ObservedObject var model: AttentionAlertModel

    var body: some View {
        // Re-evaluate once per second so "Away for N s" counts up without
        // the presenter pushing every tick.
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            content(now: ctx.date)
        }
    }

    private func content(now: Date) -> some View {
        let secs = elapsed(now: now)
        return ZStack {
            RadialGradient(
                colors: [Color(red: 1.0, green: 45 / 255, blue: 58 / 255).opacity(0.38),
                         Color(red: 179 / 255, green: 0, blue: 15 / 255).opacity(0.62)],
                center: .center, startRadius: 0, endRadius: 900)
                .opacity(secs % 2 == 0 ? 1 : 0.88)
                .animation(.easeInOut(duration: 1), value: secs % 2)
            VStack(spacing: 10) {
                Text("Stay focused")
                    .font(.dsDisplay)
                Text("Look at the screen. Back to your task.")
                    .font(.dsHeadline)
                    .opacity(0.9)
                if let title = model.taskTitle, !title.isEmpty {
                    Text("▸ \(title)")
                        .font(.dsCallout)
                        .padding(.top, 6)
                }
                Text(statusLine(secs))
                    .font(.dsCaption)
                    .opacity(0.8)
                Text("⏸ Timer paused · resumes when you look back")
                    .font(.dsMicro)
                    .opacity(0.7)
                    .padding(.top, 14)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
            .multilineTextAlignment(.center)
            .padding(40)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func elapsed(now: Date) -> Int {
        switch model.state {
        case .away(let d), .noFace(let d): return max(0, Int(now.timeIntervalSince(d)))
        default: return 0
        }
    }

    private func statusLine(_ secs: Int) -> String {
        if case .noFace = model.state { return "Face not visible" }
        return "Away for \(secs) s"
    }
}
