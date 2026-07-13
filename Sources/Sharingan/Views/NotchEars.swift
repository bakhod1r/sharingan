import SwiftUI
import SharinganCore

/// The live state: remaining time to the left of the cutout, the task (or the
/// phase) to its right, and a progress line along the island's bottom edge.
/// Ears sit in the menu bar row and overlap what's under them — hence
/// `NotchEarsMode`, which lets the user drop one or both.
///
/// The ears do not appear fully formed. The island widens first
/// (`NotchMotion.contentLead`), then the labels slide out from behind the cutout
/// into the room that has just been made — the time leftward, the task
/// rightward. On the way out they simply fade: the shape is narrowing back to
/// the cutout underneath them and the `.clipShape` eats them as it goes, which
/// is the retraction.
struct NotchEars: View {
    @ObservedObject var model: NotchHUDModel
    /// Only for `settings.timeFormat` — the countdown itself comes off the model,
    /// which the window manager keeps in step with the timer.
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject var tasks = TaskStore.shared
    let layout: NotchLayout
    let reduceMotion: Bool

    /// Flipped in `onAppear`: the ears stage their own arrival rather than
    /// riding a `.transition`, because SwiftUI runs only the outermost inserted
    /// view's transition and that is this view, not its labels.
    @State private var emerged = false

    var body: some View {
        // Reduce Motion drops the slide entirely and leaves the cross-fade.
        let settled = emerged || reduceMotion

        // Which ears exist is the *layout's* answer, not a second reading of the
        // setting: the island is only as wide as the ears it grew, and a label
        // drawn where no ear was made would be clipped by the silhouette — and
        // would sit over menu bar the hit-test mask has already given back.
        return ZStack(alignment: .topLeading) {
            if let left = layout.leftEar {
                timeLabel
                    .frame(width: left.width, height: left.height)
                    // Emerges leftward, out from under the cutout.
                    .offset(x: settled ? 0 : NotchMotion.earDrift)
                    .opacity(emerged ? 1 : 0)
                    .animation(NotchMotion.earArrival(reduceMotion: reduceMotion),
                               value: emerged)
                    .offset(x: left.minX - layout.island.minX, y: left.minY)
            }
            if let right = layout.rightEar {
                taskLabel
                    .frame(width: right.width, height: right.height)
                    // … and this one rightward.
                    .offset(x: settled ? 0 : -NotchMotion.earDrift)
                    .opacity(emerged ? 1 : 0)
                    .animation(NotchMotion.earArrival(reduceMotion: reduceMotion),
                               value: emerged)
                    .offset(x: right.minX - layout.island.minX, y: right.minY)
            }
            if let track = layout.progressTrack {
                NotchProgressBar(progress: model.progress, phase: model.phase,
                                 width: track.width, height: track.height,
                                 reduceMotion: reduceMotion)
                    // The line is the last thing to arrive: it belongs to the
                    // island's bottom edge, which is the last edge to stop
                    // moving.
                    .opacity(emerged ? 1 : 0)
                    .animation(NotchMotion.arrival(section: 1,
                                                   reduceMotion: reduceMotion),
                               value: emerged)
                    .offset(x: track.minX - layout.island.minX, y: track.minY)
            }
        }
        // Pin this view's own top-left to the island's top-left explicitly.
        // The parent attaches us via `.overlay(alignment: .top)` on the island
        // shape; without a frame that matches the island exactly, an
        // auto-sized ZStack would be centered inside the island instead of
        // anchored at its origin, and every offset above (computed relative
        // to `layout.island.minX`/`.minY`) would land in the wrong place.
        .frame(width: layout.island.width, height: layout.island.height,
               alignment: .topLeading)
        .onAppear { emerged = true }
    }

    private var timeLabel: some View {
        Text(timer.settings.timeFormat.string(max(0, model.remaining)))
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.trailing, 6)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var taskLabel: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(model.phase.gradient.first ?? .white)
                // The dot carries the phase color; a flip cross-fades it, the
                // same beat the progress line's gradient takes.
                .animation(NotchMotion.phaseFade(reduceMotion: reduceMotion),
                           value: model.phase)
                .frame(width: 6, height: 6)
            Text(tasks.activeTask?.title ?? model.phase.label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.leading, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The one piece of the HUD that can never collide with anything: a hairline
/// under the island filling with the session's progress.
///
/// The fill moves once a second, when the timer's tick writes `model.progress`,
/// and it is tweened linearly over exactly that second (`NotchMotion.tick`): it
/// lands on the next value as the next value arrives, so the line creeps
/// continuously instead of stepping. A spring would wobble at this pace.
struct NotchProgressBar: View {
    let progress: Double
    let phase: PomodoroPhase
    let width: CGFloat
    let height: CGFloat
    let reduceMotion: Bool

    var body: some View {
        let clamped = max(0, min(1, progress))
        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.12))
            Capsule()
                .fill(LinearGradient(colors: phase.gradient,
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: max(0, width * clamped))
                // The phase is the fill's *identity*, which buys two things at
                // once: a flip cross-fades the color instead of cutting it, and
                // the width does not interpolate across the flip — the new
                // phase's bar fades in at its own (near-zero) width while the
                // old one fades out at full, instead of visibly sweeping
                // backwards over a second like a rewind.
                .id(phase)
                .transition(.opacity)
        }
        .frame(width: width, height: height)
        .animation(NotchMotion.progressFill(reduceMotion: reduceMotion), value: clamped)
        .animation(NotchMotion.phaseFade(reduceMotion: reduceMotion), value: phase)
    }
}
