import Foundation
import Vision
import CoreVideo

public struct GazeDirection: Equatable, Sendable {
    public var dx: Double
    public var dy: Double

    public init(dx: Double, dy: Double) {
        self.dx = max(-1, min(1, dx))
        self.dy = max(-1, min(1, dy))
    }

    public static let center = GazeDirection(dx: 0, dy: 0)
    public static let up       = GazeDirection(dx: 0,  dy: -1)
    public static let down     = GazeDirection(dx: 0,  dy: 1)
    public static let left     = GazeDirection(dx: -1, dy: 0)
    public static let right    = GazeDirection(dx: 1,  dy: 0)
    public static let upLeft   = GazeDirection(dx: -0.7, dy: -0.7)
    public static let upRight  = GazeDirection(dx: 0.7,  dy: -0.7)
    public static let downLeft = GazeDirection(dx: -0.7, dy: 0.7)
    public static let downRight = GazeDirection(dx: 0.7,  dy: 0.7)

    public var magnitude: Double { sqrt(dx * dx + dy * dy) }

    public func matches(_ other: GazeDirection, tolerance: Double = 0.35) -> Bool {
        let ddx = dx - other.dx
        let ddy = dy - other.dy
        return sqrt(ddx * ddx + ddy * ddy) <= tolerance
    }

    public var label: String {
        if magnitude < 0.25 { return "center" }
        let angle = atan2(-dy, dx) * 180 / .pi
        switch angle {
        case -22.5..<22.5:     return "right"
        case 22.5..<67.5:      return "up right"
        case 67.5..<112.5:     return "up"
        case 112.5..<157.5:    return "up left"
        case 157.5...180, -180..<(-157.5): return "left"
        case -157.5..<(-112.5):return "down left"
        case -112.5..<(-67.5): return "down"
        case -67.5..<(-22.5):  return "down right"
        default:               return "?"
        }
    }
}

public struct EyeState: Equatable, Sendable {
    public var leftEyeOpenRatio: Double
    public var rightEyeOpenRatio: Double
    public var isBlinking: Bool
    public var blinkCountTotal: Int
    public var gaze: GazeDirection
    public var faceDetected: Bool
    /// Head pose in degrees (0 = facing the camera). Zero when no face.
    public var yaw: Double
    public var pitch: Double

    public init(left: Double, right: Double, blinking: Bool, total: Int,
                gaze: GazeDirection = .center, faceDetected: Bool = true,
                blinkRate: Double = 0, yaw: Double = 0, pitch: Double = 0) {
        self.yaw = yaw
        self.pitch = pitch
        self.leftEyeOpenRatio = left
        self.rightEyeOpenRatio = right
        self.isBlinking = blinking
        self.blinkCountTotal = total
        self.gaze = gaze
        self.faceDetected = faceDetected
        self.blinkRatePerMinute = blinkRate
    }

    public var averageOpenRatio: Double { (leftEyeOpenRatio + rightEyeOpenRatio) / 2 }
    /// Blinks counted in the trailing 60 s window (== blinks/min).
    public var blinkRatePerMinute: Double
}

/// Who is holding the camera. The camera runs while at least one owner holds
/// a lease, so a break ending can't kill focus tracking (and vice versa).
public enum CameraOwner: Hashable, Sendable {
    case breakExercise, focusAttention, calibration
}

@MainActor
public final class EyeTracker: ObservableObject {
    public static let shared = EyeTracker()

    @Published public private(set) var state = EyeState(left: 0, right: 0,
                                                        blinking: false, total: 0,
                                                        faceDetected: false)
    @Published public private(set) var isDetecting: Bool = false
    @Published public private(set) var lastGazeDirection: GazeDirection = .center

    public var blinkThreshold: Double = 0.20
    public var underBlinkRateThreshold: Double = 8.0 // blinks/min
    public var gazeTolerance: Double = 0.35
    /// Frames arriving sooner than this after the last analyzed one are skipped
    /// (cheap check, before any Vision work). 0 = analyze every frame.
    public var minFrameInterval: TimeInterval {
        get { gate.interval }
        set { gate.interval = newValue }
    }
    /// Lock-guarded copy of `minFrameInterval` the detached loop reads WITHOUT
    /// hopping to the main actor — skipped frames used to cost two main-actor
    /// round trips each (~30/s), just to be dropped.
    private nonisolated let gate = FrameGate()
    private var owners: Set<CameraOwner> = []
    /// Analyze cadence while only the focus guard watches: one Vision pass
    /// per second. Slightly under 1 s so capture jitter never skips a beat.
    static let focusFrameInterval: TimeInterval = 0.9
    /// Camera capture rate while only the focus guard watches (clamped up to
    /// the device's minimum). "Looked away for 2 s" needs ~1 frame/s, not 30.
    static let focusCaptureFPS: Double = 2

    /// Previous frame's blink state — a blink is counted once on the open→closed
    /// edge, not repeatedly while the eyes stay shut.
    private var wasBlinking: Bool = false
    private var binksInWindow: [Date] = []
    private var rotation: CGImagePropertyOrientation = .up
    private var faceBoundsCache: CGRect = .null
    private var trackingTask: Task<Void, Never>?

    public init() {}

    /// Take a camera lease. The first owner starts the camera + detection.
    public func acquire(_ owner: CameraOwner) {
        owners.insert(owner)
        updateFrameInterval()
        if owners.count == 1 {
            CameraService.shared.start()
            start()
        }
    }

    /// Drop a lease. The last owner out stops detection and the camera.
    public func release(_ owner: CameraOwner) {
        guard owners.remove(owner) != nil else { return }
        updateFrameInterval()
        if owners.isEmpty {
            stop()
            CameraService.shared.stop()
        }
    }

    private func updateFrameInterval() {
        // Break exercises and calibration need responsive gaze; the focus guard
        // alone checks once per second (keeps CPU near idle).
        let needsFast = owners.contains(.breakExercise) || owners.contains(.calibration)
        minFrameInterval = needsFast ? 0 : Self.focusFrameInterval
        // Capture fewer frames too: analyze-side skipping alone still paid
        // for 30 fps capture + BGRA conversion (~40% CPU measured).
        CameraService.shared.setMaxFrameRate(needsFast ? nil : Self.focusCaptureFPS)
    }

    public func start() {
        guard !isDetecting else { return }
        isDetecting = true
        let stream = CameraService.shared.frames()
        let orientation = rotation
        // Vision inference runs OFF the main actor — synchronous ~30 fps
        // face-landmark detection on main janked the break UI and pinned a
        // core. Only the small Sendable per-frame summary hops back to main.
        trackingTask = Task.detached(priority: .utility) { [weak self] in
            let handler = VNSequenceRequestHandler()
            var lastAnalyzed = Date.distantPast
            guard let gate = self?.gate else { return }
            for await buffer in stream {
                // stop() cancels this task; no main-actor hop needed to notice.
                if Task.isCancelled { return }
                let interval = gate.interval
                if interval > 0 {
                    let now = Date()
                    if now.timeIntervalSince(lastAnalyzed) < interval { continue }
                    lastAnalyzed = now
                }
                let sample = Self.analyze(buffer, handler: handler,
                                          orientation: orientation)
                guard let self else { return }
                await self.apply(sample)
            }
        }
    }

    public func stop() {
        isDetecting = false
        trackingTask?.cancel()
        trackingTask = nil
    }

    public func resetBlinkWindow() {
        binksInWindow.removeAll()
        state = EyeState(left: 0, right: 0, blinking: false, total: state.blinkCountTotal,
                        faceDetected: false)
    }

    private struct FrameSample: Sendable {
        var faceDetected: Bool
        var left: Double = 0
        var right: Double = 0
        var gaze: GazeDirection = .center
        var bounds: CGRect = .null
        var yaw: Double = 0
        var pitch: Double = 0
    }

    private nonisolated static func analyze(_ buffer: CVImageBuffer,
                                            handler: VNSequenceRequestHandler,
                                            orientation: CGImagePropertyOrientation) -> FrameSample {
        // Rectangles first (revision 3 carries head yaw/pitch), then landmarks
        // on those same faces — one detection pass, not two.
        let rects = VNDetectFaceRectanglesRequest()
        rects.revision = VNDetectFaceRectanglesRequestRevision3
        try? handler.perform([rects], on: buffer, orientation: orientation)
        guard let face = rects.results?.first else {
            return FrameSample(faceDetected: false)
        }
        let request = VNDetectFaceLandmarksRequest()
        request.revision = VNDetectFaceLandmarksRequestRevision2
        request.inputFaceObservations = [face]
        try? handler.perform([request], on: buffer, orientation: orientation)
        // `results` holds VNFaceObservation — the landmarks hang off it. (The
        // old code cast the observation itself to VNFaceLandmarks2D, which
        // always failed, so no face was ever detected.)
        guard let lm = request.results?.first?.landmarks else {
            return FrameSample(faceDetected: false)
        }
        let radToDeg = 180.0 / Double.pi
        return FrameSample(faceDetected: true,
                           left: openRatio(for: lm.leftEye),
                           right: openRatio(for: lm.rightEye),
                           gaze: gazeDirection(lm),
                           bounds: boundsFromLandmarks(lm),
                           yaw: (face.yaw?.doubleValue ?? 0) * radToDeg,
                           pitch: (face.pitch?.doubleValue ?? 0) * radToDeg)
    }

    private func apply(_ sample: FrameSample) {
        guard isDetecting else { return }
        guard sample.faceDetected else {
            state = EyeState(left: state.leftEyeOpenRatio,
                             right: state.rightEyeOpenRatio,
                             blinking: state.isBlinking,
                             total: state.blinkCountTotal,
                             gaze: state.gaze,
                             faceDetected: false,
                             blinkRate: windowedBlinkRate())
            return
        }
        faceBoundsCache = sample.bounds
        let avg = (sample.left + sample.right) / 2
        let blinking = avg < blinkThreshold

        // Count exactly one blink per open→closed transition. Holding the eyes
        // shut no longer inflates the count (the old timer re-fired every 0.15s).
        var total = state.blinkCountTotal
        if blinking && !wasBlinking {
            total += 1
            binksInWindow.append(Date())
        }
        wasBlinking = blinking

        let rate = windowedBlinkRate()

        lastGazeDirection = sample.gaze
        state = EyeState(left: sample.left, right: sample.right, blinking: blinking,
                         total: total, gaze: sample.gaze, faceDetected: true,
                         blinkRate: rate, yaw: sample.yaw, pitch: sample.pitch)
    }

    private nonisolated static func boundsFromLandmarks(_ lm: VNFaceLandmarks2D) -> CGRect {
        let regions: [VNFaceLandmarkRegion2D?] = [
            lm.faceContour, lm.leftEye, lm.rightEye,
            lm.leftEyebrow, lm.rightEyebrow, lm.nose, lm.outerLips, lm.innerLips,
            lm.medianLine
        ]
        var allX: [CGFloat] = []
        var allY: [CGFloat] = []
        for region in regions {
            guard let r = region else { continue }
            for p in r.normalizedPoints {
                allX.append(p.x); allY.append(p.y)
            }
        }
        guard let minX = allX.min(), let maxX = allX.max(),
              let minY = allY.min(), let maxY = allY.max(),
              maxX > minX, maxY > minY else {
            return CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Eye openness ratio in [0,1]. Lower values = more closed eye.
    private nonisolated static func openRatio(for eye: VNFaceLandmarkRegion2D?) -> Double {
        guard let eye = eye else { return 1.0 }
        let points = eye.normalizedPoints
        guard points.count >= 2 else { return 1.0 }
        let ys = points.map { $0.y }
        guard let minY = ys.min(), let maxY = ys.max() else { return 1.0 }
        return max(0, min(1, Double(maxY - minY) * 14.0))
    }

    /// Estimate gaze from the pupil's position WITHIN each eye's own opening,
    /// averaged over both eyes. Measuring relative to the eye — not the face box —
    /// removes the structural upward bias of the old method (the eyes always sit
    /// above the face-box center, so "look down" could never validate).
    /// Vision returns normalized points in image coords (origin bottom-left).
    private nonisolated static func gazeDirection(_ lm: VNFaceLandmarks2D) -> GazeDirection {
        let samples = [eyeGaze(eye: lm.leftEye, pupil: lm.leftPupil),
                       eyeGaze(eye: lm.rightEye, pupil: lm.rightPupil)].compactMap { $0 }
        guard !samples.isEmpty else { return .center }
        let nx = samples.map(\.0).reduce(0, +) / Double(samples.count)
        let ny = samples.map(\.1).reduce(0, +) / Double(samples.count)
        // Gain so a moderate eye movement reaches the 8-way target labels; the
        // pupil rarely travels to the eye's edge. dy negated: Vision up = +y,
        // but a downward gaze should map to +dy (screen-down).
        let gain = 2.2
        return GazeDirection(dx: nx * gain, dy: -ny * gain)
    }

    /// Pupil offset from the eye's center, normalized to the eye's half-extents,
    /// giving roughly -1…1 per axis. Falls back to the eye centroid (≈0 offset)
    /// when no pupil landmark is available.
    private nonisolated static func eyeGaze(eye: VNFaceLandmarkRegion2D?,
                                            pupil: VNFaceLandmarkRegion2D?) -> (Double, Double)? {
        guard let eye, !eye.normalizedPoints.isEmpty else { return nil }
        let xs = eye.normalizedPoints.map { $0.x }
        let ys = eye.normalizedPoints.map { $0.y }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max(),
              maxX > minX, maxY > minY else { return nil }

        let pupilPt: CGPoint
        if let p = pupil?.normalizedPoints.first {
            pupilPt = p
        } else {
            pupilPt = CGPoint(x: xs.reduce(0, +) / CGFloat(xs.count),
                              y: ys.reduce(0, +) / CGFloat(ys.count))
        }
        let cx = (minX + maxX) / 2
        let cy = (minY + maxY) / 2
        let nx = Double((pupilPt.x - cx) / ((maxX - minX) / 2))
        let ny = Double((pupilPt.y - cy) / ((maxY - minY) / 2))
        return (nx, ny)
    }

    public var binksLastMinute: Int { binksInWindow.count }

    /// Prunes the window to the last 60 s and returns its size (= blinks/min).
    private func windowedBlinkRate(now: Date = Date()) -> Double {
        binksInWindow = binksInWindow.filter { now.timeIntervalSince($0) < 60 }
        return Double(binksInWindow.count)
    }
}

/// Thread-safe holder for the analyze throttle, shared between the main actor
/// (writer) and the detached Vision loop (reader).
private final class FrameGate: @unchecked Sendable {
    private let lock = NSLock()
    private var _interval: TimeInterval = 0
    var interval: TimeInterval {
        get { lock.lock(); defer { lock.unlock() }; return _interval }
        set { lock.lock(); _interval = newValue; lock.unlock() }
    }
}
