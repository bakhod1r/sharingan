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

    public init(left: Double, right: Double, blinking: Bool, total: Int,
                gaze: GazeDirection = .center, faceDetected: Bool = true) {
        self.leftEyeOpenRatio = left
        self.rightEyeOpenRatio = right
        self.isBlinking = blinking
        self.blinkCountTotal = total
        self.gaze = gaze
        self.faceDetected = faceDetected
    }

    public var averageOpenRatio: Double { (leftEyeOpenRatio + rightEyeOpenRatio) / 2 }
    public var blinkRatePerMinute: Double { 0 }
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

    private var sequenceHandler: VNSequenceRequestHandler?
    /// Previous frame's blink state — a blink is counted once on the open→closed
    /// edge, not repeatedly while the eyes stay shut.
    private var wasBlinking: Bool = false
    private var binksInWindow: [Date] = []
    private var rotation: CGImagePropertyOrientation = .up
    private var faceBoundsCache: CGRect = .null

    public init() {}

    public func start() {
        guard !isDetecting else { return }
        sequenceHandler = VNSequenceRequestHandler()
        isDetecting = true
        Task { await runTracking() }
    }

    public func stop() {
        isDetecting = false
        sequenceHandler = nil
    }

    public func resetBlinkWindow() {
        binksInWindow.removeAll()
        state = EyeState(left: 0, right: 0, blinking: false, total: state.blinkCountTotal,
                        faceDetected: false)
    }

    private func runTracking() async {
        let stream = CameraService.shared.frames()
        for await buffer in stream {
            guard isDetecting else { return }
            process(buffer)
        }
    }

    private func process(_ buffer: CVImageBuffer) {
        let faceReq = VNDetectFaceLandmarksRequest { [weak self] req, _ in
            MainActor.assumeIsolated {
                self?.handleResult(req)
            }
        }
        faceReq.revision = VNDetectFaceLandmarksRequestRevision2
        do {
            try sequenceHandler?.perform([faceReq], on: buffer, orientation: rotation)
        } catch {
            // Vision error — drop frame quietly.
        }
    }

    private func handleResult(_ request: VNRequest) {
        guard let observation = request.results?.first as? VNFaceLandmarks2D else {
            state = EyeState(left: state.leftEyeOpenRatio,
                             right: state.rightEyeOpenRatio,
                             blinking: state.isBlinking,
                             total: state.blinkCountTotal,
                             gaze: state.gaze,
                             faceDetected: false)
            return
        }
        // VNFaceLandmarks2D itself has no boundingBox; derive face bounds
        // from the union of all available landmark points.
        let bounds = boundsFromLandmarks(observation)
        faceBoundsCache = bounds
        let left = openRatio(for: observation.leftEye)
        let right = openRatio(for: observation.rightEye)
        let avg = (left + right) / 2
        let blinking = avg < blinkThreshold

        let gaze = gazeDirection(observation)

        // Count exactly one blink per open→closed transition. Holding the eyes
        // shut no longer inflates the count (the old timer re-fired every 0.15s).
        var total = state.blinkCountTotal
        if blinking && !wasBlinking {
            total += 1
            binksInWindow.append(Date())
        }
        wasBlinking = blinking

        binksInWindow = binksInWindow.filter { Date().timeIntervalSince($0) < 60 }

        lastGazeDirection = gaze
        state = EyeState(left: left, right: right, blinking: blinking, total: total,
                         gaze: gaze, faceDetected: true)
    }

    private func boundsFromLandmarks(_ lm: VNFaceLandmarks2D) -> CGRect {
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
    private func openRatio(for eye: VNFaceLandmarkRegion2D?) -> Double {
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
    private func gazeDirection(_ lm: VNFaceLandmarks2D) -> GazeDirection {
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
    private func eyeGaze(eye: VNFaceLandmarkRegion2D?,
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
}