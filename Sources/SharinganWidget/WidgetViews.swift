import SwiftUI
import WidgetKit

// The appex doesn't link SharinganCore (only the two WidgetSnapshot* files
// are compiled in), so the phase colors mirror
// Sources/SharinganCore/Models/Palette.swift by value — keep them in sync.
private extension WidgetSnapshot.Phase {
    var gradient: [Color] {
        switch self {
        case .focus:
            return [Color(red: 0.36, green: 0.62, blue: 1.00),
                    Color(red: 0.20, green: 0.34, blue: 0.98)]
        case .shortBreak:
            return [Color(red: 0.30, green: 0.96, blue: 0.78),
                    Color(red: 0.16, green: 0.74, blue: 0.66)]
        case .longBreak:
            return [Color(red: 0.86, green: 0.74, blue: 1.00),
                    Color(red: 0.62, green: 0.42, blue: 0.98)]
        case .paused, .idle:
            return [Color(red: 0.55, green: 0.57, blue: 0.62),
                    Color(red: 0.34, green: 0.36, blue: 0.42)]
        }
    }

    var systemImage: String {
        switch self {
        case .focus:      return "brain.head.profile.fill"
        case .shortBreak: return "cup.and.saucer.fill"
        case .longBreak:  return "leaf.fill"
        case .paused:     return "pause.circle.fill"
        case .idle:       return "play.circle.fill"
        }
    }
}

/// Same dark-glass family as the app (which pins itself to dark aqua).
struct WidgetBackground: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.10, green: 0.11, blue: 0.15),
                                Color(red: 0.05, green: 0.06, blue: 0.09)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct PomodoroWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PomodoroEntry

    var body: some View {
        switch family {
        case .systemMedium: MediumView(entry: entry)
        default:            SmallView(entry: entry)
        }
    }
}

// MARK: - Shared pieces

private struct TimerRing: View {
    let snapshot: WidgetSnapshot
    let entryDate: Date
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: snapshot.progress(at: entryDate))
                .stroke(LinearGradient(colors: snapshot.phase.gradient,
                                       startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Running → self-updating countdown; paused/idle → static remaining.
private struct TimeText: View {
    let snapshot: WidgetSnapshot
    let entryDate: Date

    var body: some View {
        if snapshot.isRunning, let end = snapshot.endDate, end > entryDate {
            Text(timerInterval: entryDate...end, countsDown: true)
        } else {
            Text(Self.clock(snapshot.remainingSeconds))
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct TodayLine: View {
    let snapshot: WidgetSnapshot
    var showGoal = false

    var body: some View {
        HStack(spacing: 4) {
            Text("🍅").font(.caption2)
            if showGoal && snapshot.dailyGoal > 0 {
                Text("\(snapshot.todayPomodoros) / \(snapshot.dailyGoal) today")
            } else {
                Text("\(snapshot.todayPomodoros) today")
            }
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.white.opacity(0.7))
    }
}

// MARK: - Families

private struct SmallView: View {
    let entry: PomodoroEntry

    var body: some View {
        let snap = entry.snapshot
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                TimerRing(snapshot: snap, entryDate: entry.date, lineWidth: 4)
                    .frame(width: 26, height: 26)
                Spacer()
                Image(systemName: snap.phase.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: snap.phase.gradient,
                                                    startPoint: .top, endPoint: .bottom))
            }
            Spacer(minLength: 0)
            TimeText(snapshot: snap, entryDate: entry.date)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(snap.phase.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))
            TodayLine(snapshot: snap)
        }
        .widgetURL(URL(string: "sharingan://show"))
    }
}

private struct MediumView: View {
    let entry: PomodoroEntry

    var body: some View {
        let snap = entry.snapshot
        HStack(spacing: 16) {
            ZStack {
                TimerRing(snapshot: snap, entryDate: entry.date, lineWidth: 6)
                TimeText(snapshot: snap, entryDate: entry.date)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .padding(.horizontal, 10)
            }
            .frame(width: 84, height: 84)

            VStack(alignment: .leading, spacing: 4) {
                Text(snap.taskTitle ?? "No task selected")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(snap.taskTitle == nil ? .white.opacity(0.45) : .white)
                    .lineLimit(2)
                Text(snap.phase.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 2)
                HStack(spacing: 12) {
                    TodayLine(snapshot: snap, showGoal: true)
                    if snap.streakDays > 0 {
                        HStack(spacing: 3) {
                            Text("🔥").font(.caption2)
                            Text("\(snap.streakDays)d")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
                // Deep links, not AppIntents (pure-SwiftPM appex): each tap
                // opens the agent app, which routes via URLCommandRouter.
                HStack(spacing: 8) {
                    TransportLink(symbol: "play.fill", url: "sharingan://start",
                                  active: !snap.isRunning)
                    TransportLink(symbol: "pause.fill", url: "sharingan://pause",
                                  active: snap.isRunning)
                    TransportLink(symbol: "arrow.counterclockwise", url: "sharingan://reset",
                                  active: snap.phase != .idle)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct TransportLink: View {
    let symbol: String
    let url: String
    /// Dimmed (but still tappable) when the action is a no-op right now.
    let active: Bool

    var body: some View {
        Link(destination: URL(string: url)!) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(active ? 0.9 : 0.35))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.12)))
        }
    }
}
