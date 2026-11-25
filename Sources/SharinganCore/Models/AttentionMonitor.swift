import Foundation

/// Turns a stream of `AttentionSample`s into an `AttentionState`.
///
/// - Median of the last `policy.smoothingWindow` frames filters jitter.
/// - Off/on streaks are dated from their first RAW sample, so the median's
///   lag doesn't add to `grace` / `recovery` (matters at a 1 Hz cadence).
/// - Off-screen time must be continuous for `grace` before the alert fires.
/// - An alert clears only after `recovery` of continuous on-screen time.
public struct AttentionMonitor {
    public var policy: AttentionPolicy
    public private(set) var state: AttentionState = .attentive

    private var yaws: [Double] = []
    private var pitches: [Double] = []
    private var gazeXs: [Double] = []
    private var gazeYs: [Double] = []
    private var offScreenSince: Date?
    private var onScreenSince: Date?
    private var noFaceSince: Date?
    /// First raw (unsmoothed) sample of the current off / on streak.
    private var rawOffSince: Date?
    private var rawOnSince: Date?

    public init(policy: AttentionPolicy = AttentionPolicy()) {
        self.policy = policy
    }

    public mutating func reset() {
        state = .attentive
        yaws = []; pitches = []; gazeXs = []; gazeYs = []
        offScreenSince = nil; onScreenSince = nil; noFaceSince = nil
        rawOffSince = nil; rawOnSince = nil
    }

    @discardableResult
    public mutating func ingest(_ s: AttentionSample) -> AttentionState {
        if policy.hasRecentInput(s) { return ingestWorking(s) }
        guard s.faceDetected else { return ingestNoFace(at: s.at) }
        noFaceSince = nil
        if policy.isOnScreen(s) {
            rawOffSince = nil
            if rawOnSince == nil { rawOnSince = s.at }
        } else {
            rawOnSince = nil
            if rawOffSince == nil { rawOffSince = s.at }
        }
        push(s)
        let smoothed = AttentionSample(faceDetected: true,
                                       yaw: Self.median(yaws), pitch: Self.median(pitches),
                                       gaze: GazeDirection(dx: Self.median(gazeXs),
                                                           dy: Self.median(gazeYs)),
                                       eyesClosed: s.eyesClosed, at: s.at)
        if policy.isOnScreen(smoothed) {
            offScreenSince = nil
            let since = onScreenSince ?? rawOnSince ?? s.at
            onScreenSince = since
            if state.isAlerting {
                if s.at.timeIntervalSince(since) >= policy.recovery { state = .attentive }
            } else {
                state = .attentive
            }
        } else {
            onScreenSince = nil
            let since = offScreenSince ?? rawOffSince ?? s.at
            offScreenSince = since
            switch state {
            case .away: break
            case .noFace(let n): state = .away(since: n)
            default:
                state = s.at.timeIntervalSince(since) >= policy.grace
                    ? .away(since: since) : .drifting(since: since)
            }
        }
        return state
    }

    /// Hands on keyboard/mouse: attentive regardless of pose or face (typing
    /// while looking at the keys, or Vision losing a steeply-tilted face).
    /// An active alert still needs `recovery` of continued activity to clear.
    private mutating func ingestWorking(_ s: AttentionSample) -> AttentionState {
        if s.faceDetected { push(s) }
        noFaceSince = nil; offScreenSince = nil; rawOffSince = nil
        if rawOnSince == nil { rawOnSince = s.at }
        let since = onScreenSince ?? rawOnSince ?? s.at
        onScreenSince = since
        if !state.isAlerting || s.at.timeIntervalSince(since) >= policy.recovery {
            state = .attentive
        }
        return state
    }

    private mutating func ingestNoFace(at: Date) -> AttentionState {
        onScreenSince = nil
        rawOnSince = nil
        let since = noFaceSince ?? at
        noFaceSince = since
        if offScreenSince == nil { offScreenSince = since }
        if at.timeIntervalSince(since) >= policy.noFaceGrace {
            // Stale pose history must not outvote the first frames after return.
            yaws = []; pitches = []; gazeXs = []; gazeYs = []
            state = .noFace(since: since)
        } else if !state.isAlerting {
            state = .drifting(since: since)
        }
        return state
    }

    private var window: Int { policy.smoothingWindow }

    private mutating func push(_ s: AttentionSample) {
        Self.append(&yaws, s.yaw, window)
        Self.append(&pitches, s.pitch, window)
        // A blink drags the pupil landmarks around — keep the last open-eye gaze.
        if !s.eyesClosed {
            Self.append(&gazeXs, s.gaze.dx, window)
            Self.append(&gazeYs, s.gaze.dy, window)
        }
    }

    private static func append(_ a: inout [Double], _ v: Double, _ window: Int) {
        a.append(v)
        if a.count > window { a.removeFirst(a.count - window) }
    }

    private static func median(_ a: [Double]) -> Double {
        guard !a.isEmpty else { return 0 }
        return a.sorted()[a.count / 2]
    }
}
