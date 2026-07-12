import Testing
import Foundation
@testable import SharinganCore

/// Regression coverage for the 2026-07 audit fixes — each test pins the
/// corrected behavior of a bug that shipped silently.
@Suite("Audit regressions")
struct AuditRegressionTests {

    // MARK: - startFocusSession (paused sessions were reset to a full pomodoro)

    @MainActor @Test func startFocusSessionResumesPausedFocus() {
        let t = PomodoroTimer()
        t.settings = PomodoroSettings()
        t.stop()
        t.start()
        t.removeTime(300) // mid-session: remaining is no longer the full duration
        let before = t.remainingSeconds
        t.pause()
        #expect(t.phase == .paused)

        t.startFocusSession()

        #expect(t.phase == .focus)
        #expect(t.isRunning)
        // The old `phase != .focus → stop()` check treated .paused as "not
        // focus" and wiped the session back to a full duration.
        #expect(abs(t.remainingSeconds - before) < 1.0)
        t.stop()
    }

    @MainActor @Test func startFocusSessionResetsFromBreak() {
        let t = PomodoroTimer()
        t.settings = PomodoroSettings()
        t.stop()
        t.start()
        t.skip()
        #expect(t.phase == .shortBreak)

        t.startFocusSession()

        #expect(t.phase == .focus)
        #expect(t.isRunning)
        #expect(t.remainingSeconds == t.settings.duration(for: .focus))
        t.stop()
    }

    // MARK: - skip() while paused (used to no-op yet corrupt session state)

    @MainActor @Test func skipWhilePausedAdvancesFromRealPhase() {
        let t = PomodoroTimer()
        t.settings = PomodoroSettings()
        t.stop()
        t.start()
        t.pause()

        t.skip()

        #expect(t.phase == .shortBreak) // old bug: stayed .paused forever
        t.stop()
    }

    // MARK: - CLI snapshot timestamp (tired reconstructs a running countdown)

    @Test func snapshotUpdatedAtRoundTripsAndLegacyDecodes() throws {
        let stamp = Date(timeIntervalSince1970: 1_000_000)
        let snap = CLIBridge.StateSnapshot(
            phase: .focus, remainingSeconds: 100, totalSeconds: 1500,
            isRunning: true, cyclesCompletedToday: 3, streak: 7,
            updatedAt: stamp)
        let back = try JSONDecoder().decode(
            CLIBridge.StateSnapshot.self, from: JSONEncoder().encode(snap))
        #expect(back.updatedAt == stamp)

        // Snapshots written before the field existed must still decode.
        let legacy = #"{"phase":"focus","remainingSeconds":10,"totalSeconds":100,"isRunning":false,"cyclesCompletedToday":0,"streak":0}"#
        let old = try JSONDecoder().decode(
            CLIBridge.StateSnapshot.self, from: Data(legacy.utf8))
        #expect(old.updatedAt == nil)
    }

    // MARK: - CLI payload files are consumed, not replayed

    @Test func cliPayloadConsumedOnRead() {
        let name = "com.blink.test.payload-consume"
        CLIBridge.postCommand(name, payload: "50m")
        #expect(CLIBridge.readPayload(name) == "50m")
        // A second read must find nothing — a leftover payload made a plain
        // `tired start` replay the previous custom duration.
        #expect(CLIBridge.readPayload(name) == nil)
    }

    @Test func plainPostClearsStalePayload() {
        let name = "com.blink.test.payload-clear"
        CLIBridge.postCommand(name, payload: "50m")
        CLIBridge.postCommand(name) // payload-less post must clear the file
        #expect(CLIBridge.readPayload(name) == nil)
    }

    // MARK: - App blocker Messages preset (never matched the real bundle ID)

    @Test func appBlockerMatchesMessagesPreset() {
        var s = AppBlockerSettings()
        s.enabled = true
        #expect(s.matches(bundleID: "com.apple.MobileSMS"))
        // Settings saved before the preset was corrected carry the lowercase
        // ID — matching stays case-insensitive so they keep working.
        #expect(s.matches(bundleID: "com.apple.mobilesms"))
        #expect(!s.matches(bundleID: "com.example.unrelated"))
    }
}
