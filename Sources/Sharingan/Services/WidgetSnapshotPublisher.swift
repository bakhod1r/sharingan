import Foundation
import Combine
import WidgetKit
import SharinganCore

/// Feeds the WidgetKit extension: freezes timer/task state into a
/// `WidgetSnapshot`, writes it to the app-group file and pokes WidgetCenter.
///
/// The timer publishes every second while running, but the widget only needs
/// a rewrite when the *shape* of the state changes — while a session simply
/// ticks, its end date stays put and `Text(timerInterval:)` in the widget
/// does the counting. A fingerprint (with the end date bucketed to 5 s to
/// absorb tick jitter) filters the noise so chronod isn't reloaded 60×/min.
@MainActor
final class WidgetSnapshotPublisher {
    static let shared = WidgetSnapshotPublisher()

    private weak var timer: PomodoroTimer?
    private var bag = Set<AnyCancellable>()
    private var lastFingerprint: String?

    func install(timer: PomodoroTimer) {
        self.timer = timer
        Publishers.Merge(timer.objectWillChange.map { _ in () },
                         TaskStore.shared.objectWillChange.map { _ in () })
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.publish() }
            .store(in: &bag)
        // A widget placed while the app sits idle materializes its container
        // with no snapshot in it, and no timer/task event follows to write
        // one — this slow tick notices (`needsSeed`) and seeds the file.
        Timer.publish(every: 30, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.publish() }
            .store(in: &bag)
        publish()
    }

    /// Called from applicationWillTerminate: a quit app can't keep its end
    /// date honest, so the widget is parked in the idle state instead of
    /// counting down a session that no longer exists.
    func publishFinal() {
        guard let timer else { return }
        let now = Date()
        var snap = snapshot(from: timer, now: now)
        if snap.isRunning { snap = snap.idled() }
        WidgetSnapshotStore.write(snap)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func publish() {
        guard let timer else { return }
        let snap = snapshot(from: timer, now: Date())
        let key = fingerprint(snap)
        // `needsSeed` overrides the fingerprint: the widget's container can
        // appear between publishes (first widget placement) and its copy of
        // the snapshot must be written even though nothing changed.
        guard key != lastFingerprint || WidgetSnapshotStore.needsSeed else { return }
        lastFingerprint = key
        WidgetSnapshotStore.write(snap)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func snapshot(from timer: PomodoroTimer, now: Date) -> WidgetSnapshot {
        let total = timer.totalSeconds
        let remaining = timer.isCountUpMode
            ? max(0, total - timer.elapsedSeconds)
            : max(0, timer.remainingSeconds)
        // Same "engaged" reading as MenuBarController: a fresh/reset timer
        // (not running, full remaining) is idle, not "focus about to happen".
        let engaged = timer.isRunning || (remaining > 0 && remaining < total)
        let phase = engaged
            ? (WidgetSnapshot.Phase(rawValue: timer.phase.rawValue) ?? .focus)
            : .idle

        return WidgetSnapshot(
            phase: phase,
            isRunning: timer.isRunning,
            endDate: timer.isRunning ? now.addingTimeInterval(remaining) : nil,
            remainingSeconds: remaining,
            totalSeconds: total,
            taskTitle: TaskStore.shared.activeTask?.title,
            todayPomodoros: timer.stats.completedTodayCount(now: now),
            dailyGoal: timer.settings.dailyPomodoroGoal,
            streakDays: timer.stats.streakDays,
            updatedAt: now)
    }

    private func fingerprint(_ s: WidgetSnapshot) -> String {
        // Running: bucketed end date (remaining ticks down, end stays put).
        // Not running: exact remaining (it only moves on real user actions).
        let time = s.isRunning
            ? "e\(Int(((s.endDate ?? .distantPast).timeIntervalSinceReferenceDate / 5).rounded()))"
            : "r\(Int(s.remainingSeconds.rounded()))"
        return [s.phase.rawValue, "\(s.isRunning)", time, "\(Int(s.totalSeconds))",
                s.taskTitle ?? "", "\(s.todayPomodoros)", "\(s.dailyGoal)",
                "\(s.streakDays)"].joined(separator: "|")
    }
}
