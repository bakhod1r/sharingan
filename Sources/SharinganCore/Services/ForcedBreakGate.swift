import Foundation
import Combine

/// Decides whether a forced break may end. Closed (holds the break) only while
/// the camera can actually watch the user AND the exercise sequence is not yet
/// done; every camera failure (unauthorized, not running, no face for
/// `noFaceTimeout`) opens it, so a forced break can never trap the user.
@MainActor
public final class ForcedBreakGate: ObservableObject {
    public enum CameraState: Equatable, Sendable { case pending, usable, unavailable }

    public let validator: ExerciseValidator
    public var noFaceTimeout: TimeInterval = 30
    @Published public private(set) var camera: CameraState = .pending
    private var lastFaceSeen: Date
    private let now: () -> Date

    public init(validator: ExerciseValidator, now: @escaping () -> Date = { Date() }) {
        self.validator = validator
        self.now = now
        self.lastFaceSeen = now()
    }

    public func setCamera(_ state: CameraState) {
        camera = state
        if state == .usable { lastFaceSeen = now() }
    }

    /// Feed every tracker sample; a detected face restarts the no-face clock.
    public func noteFace(_ detected: Bool) {
        if detected { lastFaceSeen = now() }
    }

    public var faceLost: Bool { now().timeIntervalSince(lastFaceSeen) >= noFaceTimeout }

    /// The camera is watching and can see the user: forced rules apply.
    public var isEngaged: Bool { camera == .usable && !faceLost }

    /// "Camera can't see you — forced break paused" applies.
    public var showsSuspendedNotice: Bool {
        camera == .unavailable || (camera == .usable && faceLost)
    }

    /// True when the break may complete.
    public var isOpen: Bool { !isEngaged || validator.isSequenceComplete }
}
