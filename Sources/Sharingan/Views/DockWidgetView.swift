import SwiftUI
import SharinganCore

/// The Dock widget pill: a "now playing"-style strip anchored to the Dock by
/// DockWidgetWindowManager. Progress ring + active task + remaining time on
/// the left, three always-standing transport buttons on the right —
/// ▶︎ start (resumes a paused session), ⏸ stop (pause), ⟲ reset (the engine's
/// stop(): fresh focus, counters zeroed). Buttons disable rather than hide so
/// the pill never changes shape under the pointer.
struct DockWidgetView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var tasks = TaskStore.shared

    private var phaseColors: [Color] { timer.phase.gradient }

    var body: some View {
        HStack(spacing: 12) {
            ring
            VStack(alignment: .leading, spacing: 2) {
                titleRow
                Text(timer.settings.timeFormat.string(max(0, timer.remainingSeconds)))
                    .font(.dsTimer(17))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.3), value: timer.remainingSeconds)
            }
            Spacer(minLength: 8)
            controls
        }
        .padding(.horizontal, 14)
        .frame(width: 320, height: 56)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Mini progress ring stroked with the phase gradient; dimmed while idle.
    private var ring: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.15), lineWidth: 3.5)
            Circle()
                .trim(from: 0, to: max(0.003, timer.progress))
                .stroke(AngularGradient(colors: phaseColors, center: .center),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 30, height: 30)
        .opacity(timer.isRunning ? 1 : 0.55)
        .animation(.snappy(duration: 0.3), value: timer.progress)
    }

    @ViewBuilder
    private var titleRow: some View {
        if let task = tasks.activeTask {
            HStack(spacing: 5) {
                Circle().fill(Color(hex: tasks.color(for: task.category)))
                    .frame(width: 6, height: 6)
                Text(task.title)
                    .font(.system(size: 12, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
            }
        } else {
            Text("No task selected")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            control("play.fill", enabled: !timer.isRunning, help: "Start") {
                timer.start()
            }
            control("pause.fill", enabled: timer.isRunning, help: "Stop") {
                timer.pause()
            }
            control("arrow.counterclockwise", enabled: true, help: "Reset") {
                timer.stop()
            }
        }
    }

    private func control(_ symbol: String, enabled: Bool, help: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(enabled ? 0.9 : 0.3))
                .frame(width: 26, height: 26)
                .background(Circle().fill(.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
    }
}
