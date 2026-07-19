import Foundation
import AppKit
import CoreGraphics
import os.log

/// Records which app is frontmost during a focus session, app-level only — no
/// window titles, no Accessibility permission. Accumulation lives in the pure
/// `AppUsageAccumulator`; this is the thin AppKit wrapper that feeds it
/// `NSWorkspace` activation events and parks it when the user goes idle.
/// The coordinator starts/stops it per `AppTrackingMode` and calls
/// `flushUsage()` at session end to stamp the session's `appUsage`.
@MainActor
public final class ActiveAppTracker {
    public static let shared = ActiveAppTracker()

    private var acc = AppUsageAccumulator()
    private var observer: NSObjectProtocol?
    private var idleTimer: Timer?
    private static let idleThreshold: TimeInterval = 120
    private static let log = Logger(subsystem: "sharingan", category: "apptracker")

    public private(set) var isRunning = false

    public init() {}

    /// Start a focus session's tracking window: reset accumulation to this
    /// session and (re)wire the activation observer. Safe to call whether or
    /// not the observer is already up (always-mode keeps it up between
    /// sessions; this still resets the per-session accumulation).
    public func beginFocusSession(now: Date = Date()) {
        acc = AppUsageAccumulator()
        acc.activate(bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                     at: now)
        guard !isRunning else { return }
        isRunning = true
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                self?.acc.activate(bundleID: app?.bundleIdentifier, at: Date())
            }
        }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIdle() }
        }
    }

    private func checkIdle() {
        // Seconds since any input event; guard the optional so an unexpected
        // CGEventType never crashes the app.
        guard let anyType = CGEventType(rawValue: ~0) else { return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                           eventType: anyType)
        if idle > Self.idleThreshold {
            // Credit only up to when the user went quiet, then park.
            acc.idle(at: Date().addingTimeInterval(-(idle - Self.idleThreshold)))
        }
    }

    /// Credit the current app up to now and return per-app seconds so far,
    /// without stopping — used to stamp a finished session.
    public func flushUsage(now: Date = Date()) -> [String: TimeInterval] {
        acc.flush(at: now)
        return acc.result()
    }

    public func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
        idleTimer?.invalidate()
        idleTimer = nil
        isRunning = false
    }
}
