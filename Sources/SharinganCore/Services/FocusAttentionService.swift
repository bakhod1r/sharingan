import Foundation
import AppKit
import Combine

/// Draws / updates / removes the red "look back" tint (UI layer).
@MainActor
public protocol AttentionAlertPresenter: AnyObject {
    /// Called on every alerting state change and once per elapsed second, so
    /// "Away for N s" can update in place.
    func showAttentionAlert(state: AttentionState, taskTitle: String?)
    func hideAttentionAlert()
}

/// Feeds camera-derived samples to the guard. The real source leases the
/// camera; tests inject a fake and drive `ingest` directly.
@MainActor
public protocol AttentionSampleSource: AnyObject {
    func start(onSample: @escaping @MainActor (AttentionSample) -> Void)
    func stop()
}

/// Real source: leases the camera through `EyeTracker` and maps its published
/// state to samples. Does nothing (silently) when camera access is denied.
@MainActor
public final class EyeTrackerAttentionSource: AttentionSampleSource {
    /// System-wide idle time since the last key/mouse/trackpad event. Reads
    /// the HID idle counter — no Input Monitoring permission, no event tap.
    nonisolated static func secondsSinceLastInput() -> TimeInterval {
        let any = CGEventType(rawValue: ~0)!   // kCGAnyInputEventType
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
    }

    private var task: Task<Void, Never>?
    private var cancellable: AnyCancellable?
    private var leased = false

    public init() {}

    public func start(onSample: @escaping @MainActor (AttentionSample) -> Void) {
        stop()
        task = Task { @MainActor [weak self] in
            let granted = await CameraService.shared.requestPermission()
            guard let self, !Task.isCancelled, granted else { return }
            EyeTracker.shared.acquire(.focusAttention)
            self.leased = true
            self.cancellable = EyeTracker.shared.$state
                .dropFirst()
                .sink { st in
                    let now = Date()
                    onSample(AttentionSample(faceDetected: st.faceDetected,
                                             yaw: st.yaw, pitch: st.pitch,
                                             gaze: st.gaze, eyesClosed: st.isBlinking,
                                             at: now,
                                             lastInputAt: now.addingTimeInterval(
                                                -Self.secondsSinceLastInput())))
                }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        cancellable = nil
        if leased {
            leased = false
            EyeTracker.shared.release(.focusAttention)
        }
    }
}

/// Application service: while a focus session runs it turns samples into an
/// `AttentionState`, shows the red alert and pauses the timer when the user
/// looks away, and resumes the timer (only if the guard paused it) when they
/// look back.
@MainActor
public final class FocusAttentionService: ObservableObject {
    public static let shared = FocusAttentionService()
    public static let snoozeDuration: TimeInterval = 5 * 60

    public weak var presenter: AttentionAlertPresenter?
    public var source: AttentionSampleSource

    @Published public private(set) var state: AttentionState = .attentive
    /// True while the timer is paused BECAUSE the guard alerted — the only case
    /// where the guard auto-resumes it.
    @Published public private(set) var pausedByGuard = false
    @Published public private(set) var isEngaged = false
    public private(set) var snoozedUntil: Date?

    public var now: () -> Date = Date.init
    public var pauseTimer: () -> Void = {}
    public var resumeTimer: () -> Void = {}
    public var taskTitle: () -> String? = { nil }
    public var soundEnabled = false
    public var playAlertSound: () -> Void = { NSSound(named: "Funk")?.play() }

    private var monitor = AttentionMonitor()
    private var isShowingAlert = false
    private var lastShown: (alerting: AttentionState, second: Int)?

    // Per-session away stats. Survive release()/engage() (a manual pause
    // releases mid-session) and are cleared only by `takeSessionStats()`.
    private var awayEvents = 0
    private var awaySeconds: TimeInterval = 0
    private var alertingSince: Date?
    /// True once the guard engaged since the last `takeSessionStats()`.
    public private(set) var wasEngagedThisSession = false

    public init(source: AttentionSampleSource? = nil) {
        self.source = source ?? EyeTrackerAttentionSource()
    }

    /// Idempotent: a second call only refreshes the policy.
    public func engage(policy: AttentionPolicy) {
        if isEngaged {
            if monitor.policy != policy { monitor.policy = policy }
            return
        }
        isEngaged = true
        wasEngagedThisSession = true
        monitor = AttentionMonitor(policy: policy)
        source.start { [weak self] sample in self?.ingest(sample) }
    }

    /// Stops tracking and clears everything. Does NOT resume the timer — the
    /// caller decides (stop/skip must not, a setting flip does).
    public func release() {
        if isEngaged { source.stop() }
        closeAlertSpan()
        isEngaged = false
        pausedByGuard = false
        monitor.reset()
        state = .attentive
        hideAlert()
    }

    /// The user resumed the timer by hand while the guard had it paused.
    public func userResumed() {
        closeAlertSpan()
        pausedByGuard = false
        monitor.reset()
        state = .attentive
        hideAlert()
    }

    /// 5 minutes of no alerts. A guard-pause in flight is lifted.
    public func snooze() {
        snoozedUntil = now().addingTimeInterval(Self.snoozeDuration)
        closeAlertSpan()
        monitor.reset()
        state = .attentive
        hideAlert()
        if pausedByGuard {
            pausedByGuard = false
            resumeTimer()
        }
    }

    func ingest(_ sample: AttentionSample) {
        guard isEngaged else { return }
        if let until = snoozedUntil {
            if now() < until { return }
            snoozedUntil = nil
            monitor.reset()
        }
        let was = state
        let new = monitor.ingest(sample)
        state = new
        if new.isAlerting {
            if !was.isAlerting {
                // Flag first: the timer's pause lands in the coordinator's
                // sinks, which must see the pause as the guard's own.
                pausedByGuard = true
                awayEvents += 1
                alertingSince = now()
                pauseTimer()
                if soundEnabled { playAlertSound() }
            }
            present(new, at: sample.at)
        } else if was.isAlerting {
            closeAlertSpan()
            hideAlert()
            if pausedByGuard {
                // Clear before resuming so the resume isn't mistaken for a
                // manual one.
                pausedByGuard = false
                resumeTimer()
            }
        }
    }

    private func closeAlertSpan() {
        guard let since = alertingSince else { return }
        awaySeconds += max(0, now().timeIntervalSince(since))
        alertingSince = nil
    }

    /// Away stats since the last take (an open alert is closed out at `now`),
    /// then resets. `events == 0` with `wasEngagedThisSession` = guard ran, clean.
    @discardableResult
    public func takeSessionStats() -> (events: Int, seconds: TimeInterval) {
        closeAlertSpan()
        let r = (events: awayEvents, seconds: awaySeconds)
        awayEvents = 0
        awaySeconds = 0
        wasEngagedThisSession = false
        return r
    }

    private func present(_ s: AttentionState, at: Date) {
        let since: Date
        switch s {
        case .away(let d), .noFace(let d): since = d
        default: return
        }
        let second = max(0, Int(at.timeIntervalSince(since)))
        if isShowingAlert, let last = lastShown, last.alerting == s, last.second == second { return }
        lastShown = (s, second)
        isShowingAlert = true
        presenter?.showAttentionAlert(state: s, taskTitle: taskTitle())
    }

    private func hideAlert() {
        lastShown = nil
        guard isShowingAlert else { return }
        isShowingAlert = false
        presenter?.hideAttentionAlert()
    }
}
