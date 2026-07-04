import SwiftUI
import BlinkCore

struct MenuBarView: View {
    @ObservedObject var timer: PomodoroTimer

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusHeader
            QuickInputField(timer: timer)
            controls
            Divider().overlay(Color.white.opacity(0.15))
            statsStrip
        }
        .padding(18)
        .frame(width: 320)
    }

    private var statusHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.white.opacity(0.1))
                Image(systemName: timer.phase.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(timer.phase.glow)
            }
            .frame(width: 46, height: 46)
            .glassCapsule()

            VStack(alignment: .leading, spacing: 2) {
                Text(timer.phase.label)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                Text(formatted(timer.remainingSeconds))
                    .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            GlassButton(label: timer.isRunning ? "Pauza" : "Boshlash",
                        systemImage: timer.isRunning ? "pause.fill" : "play.fill",
                        action: { timer.toggle() })
            HStack(spacing: 8) {
                GlassButton(label: "O'tkazish",
                            systemImage: "forward.end.fill",
                            action: { timer.skip() })
                GlassButton(label: "Reset",
                            systemImage: "arrow.counterclockwise",
                            tint: .red.opacity(0.95),
                            action: { timer.stop() })
            }
            HStack(spacing: 8) {
                GlassButton(label: "+5m",
                            systemImage: "plus",
                            tint: .green.opacity(0.95),
                            action: { timer.addTime(300) })
                GlassButton(label: "-5m",
                            systemImage: "minus",
                            tint: .orange.opacity(0.95),
                            action: { timer.removeTime(300) })
            }
        }
    }

    private var statsStrip: some View {
        HStack(spacing: 14) {
            stat(value: "\(timer.stats.completedToday)", label: "Bugun")
            stat(value: "\(timer.cyclesCompletedInRound)/\(timer.settings.longBreakEvery)",
                 label: "Bosqich")
            if timer.settings.repeatConfig.enabled {
                stat(value: "\(timer.repeatIndex + 1)/\(timer.settings.repeatConfig.count)",
                     label: "Takror")
            }
            stat(value: "\(timer.stats.streak.currentStreak)", label: "Ketma-ket")
        }
        .frame(maxWidth: .infinity)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
            Text(label).font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatted(_ s: TimeInterval) -> String {
        let m = Int(s) / 60, sec = Int(s) % 60
        return String(format: "%02d:%02d", m, sec)
    }
}