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
        if magnitude < 0.25 { return "markaz" }
        // angle in degrees: 0 = right, 90 = up (screen coords flip)
        let angle = atan2(-dy, dx) * 180 / .pi
        switch angle {
        case -22.5..<22.5:     return "o'ng"
        case 22.5..<67.5:      return "yuqori o'ng"
        case 67.5..<112.5:     return "yuqori"
        case 112.5..<157.5:    return "yuqori chap"
        case 157.5...180, -180..<(-157.5): return "chap"
        case -157.5..<(-112.5):return "past chap"
        case -112.5..<(-67.5): return "past"
        case -67.5..<(-22.5):  return "past o'ng"
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
    private var lastBlinkDate: Date?
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

        let gaze = gazeDirection(leftEye: observation.leftEye,
                                  rightEye: observation.rightEye,
                                  faceBounds: bounds)

        var total = state.blinkCountTotal
        if blinking, let last = lastBlinkDate, Date().timeIntervalSince(last) > 0.15 {
            total += 1
            binksInWindow.append(Date())
            lastBlinkDate = Date()
        } else if blinking, lastBlinkDate == nil {
            total += 1
            binksInWindow.append(Date())
            lastBlinkDate = Date()
        } else if !blinking, let last = lastBlinkDate, Date().timeIntervalSince(last) > 0.15 {
            lastBlinkDate = nil
        }

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

    /// Estimate gaze direction by comparing iris/eye center against face center.
    /// Vision returns normalized points in image coords (origin bottom-left).
    private func gazeDirection(leftEye: VNFaceLandmarkRegion2D?,
                                rightEye: VNFaceLandmarkRegion2D?,
                                faceBounds: CGRect) -> GazeDirection {
        guard !faceBounds.isNull,
              let lc = centroid(leftEye),
              let rc = centroid(rightEye) else {
            return .center
        }
        let eyeMidX = (lc.x + rc.x) / 2
        let eyeMidY = (lc.y + rc.y) / 2
        // Face center
        let faceCenterX = faceBounds.midX
        let faceCenterY = faceBounds.midY
        // faceHalfWidth/Height for normalization
        let halfW = max(0.001, faceBounds.width / 2)
        let halfH = max(0.001, faceBounds.height / 2)

        // dx: positive when eyes shifted right of face center (looking right)
        let dx = (eyeMidX - faceCenterX) / halfW
        // dy: Vision image coords have origin bottom-left, so up = +y.
        // We map screen-down (gaze down) to +dy, hence negate.
        let dy = -(eyeMidY - faceCenterY) / halfH

        // Eye-vs-eye asymmetry leans the gaze slightly L/R; combine for stability.
        let asym = (rc.x - lc.x) - (faceBounds.width * 0.36)
        let lean = asym / max(0.001, faceBounds.width)

        let combined = GazeDirection(dx: dx * 1.6 + lean * 0.6,
                                      dy: dy * 1.6)
        return combined
    }

    private func centroid(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
        guard let region, !region.normalizedPoints.isEmpty else { return nil }
        let p = region.normalizedPoints
        let x = p.reduce(0) { $0 + $1.x } / CGFloat(p.count)
        let y = p.reduce(0) { $0 + $1.y } / CGFloat(p.count)
        return CGPoint(x: x, y: y)
    }

    public var binksLastMinute: Int { binksInWindow.count }
}