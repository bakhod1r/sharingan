import SwiftUI
import SharinganCore

/// Break-screen "Angry" eyes: the clip's fade-in and first look-around, an angry-squint exercise
/// guide with the pupils following the step gaze, then the clip's dim-and-shut ending at break end.
/// All motion comes from the pure `AngryBreakChoreography`; this view only owns the clock and the
/// per-step bookkeeping (same inputs as `LookingForEyePair`).
struct AngryEyePair: View {
    var direction: String
    var gaze: GazeDirection
    var eyeSize: CGFloat = 92
    var style: SharinganStyle = .classic
    var rightStyle: SharinganStyle? = nil
    var holdSeconds: Double = 0
    var transition: PatternTransitionSpeed = .normal
    var endDate: Date? = nil
    var evolves = true
    var spinSeconds: Double = 0
    var iris: BreakIrisStyle = .sharingan
    /// Settings preview: start in the exercise pose (no intro, no outro).
    var skipIntro = false

    @State private var appearStart: TimeInterval = 0
    @State private var phaseStart: TimeInterval = 0
    @State private var activation = ActivationSpin()
    @State private var transitionFrom: Double = 1
    @State private var lastDirection: String = ""
    /// Step gaze target of the previous step, to rebuild the old step's live offset on a change.
    @State private var lastGaze: GazeDirection = .center
    /// Iris offset at the moment the step changed: it glides from here back to center, then out.
    @State private var previousGaze: GazeDirection = .center
    @State private var evolutionCount: Int = 0
    @State private var crossfade = StyleCrossfade()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Eye-space window around both eyeballs (the eyes span x 110...980, y 10...350).
    static let crop = CGRect(x: 95, y: -5, width: 890, height: 370)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let input = choreographyInput(at: t)
            let pose = AngryBreakChoreography.pose(input)
            let pf = evolution.frame(at: t)
            AngryFaceCanvas(
                pose: pose, iris: iris,
                left: LookingForIrisSpec(style: pf.left, spin: spin(at: t),
                                         emergence: pf.emergence, tomoeStage: pf.tomoeStage,
                                         previousStyle: pf.previousLeft, blend: pf.blend),
                right: LookingForIrisSpec(style: pf.right, spin: spin(at: t),
                                          emergence: pf.emergence, tomoeStage: pf.tomoeStage,
                                          previousStyle: pf.previousRight, blend: pf.blend),
                placement: .crop(Self.crop))
                .frame(width: eyeSize * 4.4, height: eyeSize * 4.4 * Self.crop.height / Self.crop.width)
        }
        .onAppear {
            let now = Date().timeIntervalSinceReferenceDate
            appearStart = now
            phaseStart = now
            activation.reset(start: now + 1.1)
            transitionFrom = 1
            lastDirection = direction
            lastGaze = gaze
            previousGaze = .center
        }
        .onChange(of: style) { old, new in
            crossfade.change(oldLeft: old, oldRight: rightStyle ?? old,
                             newLeft: new, newRight: rightStyle ?? new,
                             at: Date().timeIntervalSinceReferenceDate,
                             transition: transition, reduceMotion: reduceMotion)
        }
        .onChange(of: rightStyle) { old, new in
            crossfade.change(oldLeft: style, oldRight: old ?? style,
                             newLeft: style, newRight: new ?? style,
                             at: Date().timeIntervalSinceReferenceDate,
                             transition: transition, reduceMotion: reduceMotion)
        }
        .onChange(of: direction) { _, newDirection in
            let now = Date().timeIntervalSinceReferenceDate
            transitionFrom = AngryBreakChoreography.steadyOpenness(
                direction: lastDirection, phaseElapsed: now - phaseStart)
            // Live iris offset under the OLD step, no sway: the glide starts exactly where the iris is.
            var old = choreographyInput(at: now)
            old.direction = lastDirection
            old.gaze = lastGaze
            let live = BreakGazePath.gazeOffset(old, sway: false)
            previousGaze = GazeDirection(dx: live.x, dy: live.y)
            lastDirection = newDirection
            lastGaze = gaze
            phaseStart = now
            activation.restart(at: now, now: now)
            evolutionCount += 1
        }
    }

    private func choreographyInput(at t: TimeInterval) -> AngryBreakChoreography.Input {
        let skip = skipIntro ? AngryBreakChoreography.introDuration + AngryBreakChoreography.blendDuration : 0
        return AngryBreakChoreography.Input(
            elapsed: max(0, t - appearStart) + skip,
            remaining: skipIntro ? nil : endDate.map { $0.timeIntervalSinceReferenceDate - t },
            direction: direction, gaze: gaze,
            phaseElapsed: max(0, t - phaseStart), holdSeconds: holdSeconds,
            previousOpenness: transitionFrom, reduceMotion: reduceMotion, iris: iris,
            previousGaze: previousGaze)
    }

    private var evolution: PatternEvolution {
        PatternEvolution(transition: transition,
                         appearStart: appearStart,
                         phaseStart: phaseStart,
                         evolutionCount: evolutionCount,
                         end: endDate?.timeIntervalSinceReferenceDate,
                         reduceMotion: reduceMotion,
                         baseLeft: style,
                         baseRight: rightStyle ?? style,
                         evolves: evolves,
                         crossfade: crossfade)
    }

    private func spin(at t: TimeInterval) -> Double {
        if reduceMotion { return 0 }
        var s = activation.angle(at: t)
        if spinSeconds > 0 { s += max(0, t - appearStart) * 360 / spinSeconds }
        return s
    }
}
