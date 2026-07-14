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
    /// Which container edge the pill hugs — the Dock-nearest edge, supplied
    /// by `DockWidgetWindowManager` (`DockWidgetGeometry.expandAnchor`), not
    /// the raw Position setting: on a vertical Dock the pill must expand
    /// away from the Dock regardless of what Position says, since Position
    /// is a horizontal-Dock concept.
    var anchor: DockWidgetAlignment = .trailing
    /// True while the pointer sits over the pill — drives the compact ↔
    /// expanded spring when `dockWidgetExpandOnHover` is on.
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var phaseColors: [Color] { timer.phase.gradient }
    private var preset: DockWidgetSize { timer.settings.dockWidgetSize }
    /// Every metric below is tuned at the medium preset (56pt tall, k = 1)
    /// and scales linearly with whichever size is chosen.
    private var k: CGFloat { preset.height / 56 }
    /// Off = always fully open; on = compact (ring + time) at rest, full pill
    /// under the pointer — the Dock's now-playing widgets' behavior.
    private var expanded: Bool { !timer.settings.dockWidgetExpandOnHover || hovering }
    private var containerAlignment: Alignment {
        switch anchor {
        case .leading:  return .leading
        case .center:   return .center
        case .trailing: return .trailing
        }
    }

    var body: some View {
        // A full-preset-size transparent container (matching the window's
        // frame) with the pill anchored to the chosen Dock-hugging edge; the
        // pill itself — not this container — resizes on hover.
        pill
            .frame(width: preset.width, height: preset.height,
                   alignment: containerAlignment)
    }

    private var pill: some View {
        HStack(spacing: 12 * k) {
            ring
            if expanded {
                VStack(alignment: .leading, spacing: 2) {
                    titleRow
                    timeText
                }
                Spacer(minLength: 8 * k)
                controls
            } else {
                timeText
            }
        }
        .padding(.horizontal, 14 * k)
        // Only the width animates between the compact and expanded pill —
        // the height stays pinned to the preset so the pill never bobs.
        .frame(width: expanded ? preset.width : preset.height * 2.6,
               height: preset.height)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.78),
                   value: hovering)
    }

    private var timeText: some View {
        Text(timer.settings.timeFormat.string(max(0, timer.remainingSeconds)))
            .font(.dsTimer(17 * k))
            .foregroundStyle(.white)
            .lineLimit(1)
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.3), value: timer.remainingSeconds)
    }

    /// Mini progress ring stroked with the phase gradient; dimmed while idle.
    private var ring: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.15), lineWidth: 3.5 * k)
            Circle()
                .trim(from: 0, to: max(0.003, timer.progress))
                .stroke(AngularGradient(colors: phaseColors, center: .center),
                        style: StrokeStyle(lineWidth: 3.5 * k, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 30 * k, height: 30 * k)
        .opacity(timer.isRunning ? 1 : 0.55)
        .animation(.snappy(duration: 0.3), value: timer.progress)
    }

    @ViewBuilder
    private var titleRow: some View {
        if let task = tasks.activeTask {
            HStack(spacing: 5) {
                Circle().fill(Color(hex: tasks.color(for: task.category)))
                    .frame(width: 6 * k, height: 6 * k)
                Text(task.title)
                    .font(.system(size: 12 * k, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
            }
        } else {
            Text("No task selected")
                .font(.system(size: 12 * k, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private var controls: some View {
        HStack(spacing: 8 * k) {
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
                .font(.system(size: 12 * k, weight: .bold))
                .foregroundStyle(.white.opacity(enabled ? 0.9 : 0.3))
                .frame(width: 26 * k, height: 26 * k)
                .background(Circle().fill(.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
    }
}
