import Foundation
import Combine
import SwiftUI

@MainActor
public protocol QuickAddController: AnyObject {
    /// Pop up the global quick-add-task window.
    func showQuickAdd()
}

@MainActor
public protocol TodayPanelController: AnyObject {
    /// Show the always-on-desktop "today" panel (tasks + timer state).
    func showTodayPanel(timer: PomodoroTimer)
    func hideTodayPanel()
}

@MainActor
public protocol FloatingWidgetController: AnyObject {
    /// Show the Dock-anchored control pill (task + time + Start/Stop/Reset).
    func showFloatingWidget(timer: PomodoroTimer)
    func hideFloatingWidget()
}

@MainActor
public final class SharinganCoordinator: ObservableObject {
    public let timer: PomodoroTimer
    /// Ordered task ids the user works through, one focus session each.
    public let focusQueue: FocusQueue
    /// True when a break just ended with nothing to work on — no valid queued
    /// task and no open active task — so the UI should ask which task is next.
    /// Cleared when a task becomes active, a focus session starts, or the UI
    /// answers via `resolveTaskPick(with:)`.
    @Published public private(set) var needsTaskPick = false
    public var breakPresenter: BreakPresenter?
    public var todayPanelController: TodayPanelController?
    public var floatingWidgetController: FloatingWidgetController?
    public var quickAddController: QuickAddController?
    public var shortcuts: KeyboardShortcutsService = .shared
    private var cancellables: Set<AnyCancellable> = []
    private var cliObservers: [String: Any] = [:]
    private var snapshotCancellable: AnyCancellable?

    /// iCloud sync, when the user has turned it on (owned by the AppDelegate).
    private weak var syncEngine: CloudSyncEngine?
    private var syncCancellable: AnyCancellable?
    /// The last timer state pushed to sync — publish only when the session
    /// payload really changed (the phase/isRunning sinks fire on every
    /// assignment, including no-op rewrites).
    private var lastPublishedTimer: ActiveTimerState?
    /// True while a fetched remote session is being applied, so the resulting
    /// phase/isRunning emissions don't publish straight back to CloudKit
    /// (A starts → B applies → B re-publishes → A re-applies, forever).
    private var isApplyingRemoteTimer = false

    /// `focusQueue`, when given (tests), backs the queue with an isolated
    /// UserDefaults suite; the app default persists to `.standard`.
    public init(timer: PomodoroTimer, focusQueue: FocusQueue? = nil) {
        self.timer = timer
        self.focusQueue = focusQueue ?? FocusQueue()
        // Prime the reward baseline from the already-earned streak so restarting
        // the app doesn't re-announce milestones the user passed days ago.
        StreakRewardCenter.shared.prime(streak: timer.stats.streak.currentStreak)
        observe()
    }

    public func installShortcuts() {
        guard timer.settings.globalShortcutsEnabled else {
            shortcuts.unregister()
            return
        }
        let actions: [GlobalShortcut: () -> Void] = [
            .toggle:        { [weak self] in self?.toggleRespectingTaskGuard() },
            .skip:         { [weak self] in self?.timer.skip() },
            .reset:        { [weak self] in self?.timer.stop() },
            .addFive:      { [weak self] in self?.timer.addTime(300) },
            // Compat (Task 11): the floating timer this shortcut used to show/hide
            // is gone. Keep the case (so a persisted custom binding under the
            // "showFloating" key still resolves to a real shortcut instead of
            // silently going dead) and retarget it to the Floating widget, which
            // is now the app's one timer window.
            .showFloating: { [weak self] in
                self?.timer.settings.dockWidgetEnabled.toggle()
            },
            .quickAddTask: { [weak self] in self?.quickAddController?.showQuickAdd() }
        ]
        var bindings: [GlobalShortcut: ShortcutBinding] = [:]
        for (key, binding) in timer.settings.shortcutBindings {
            if let shortcut = GlobalShortcut(rawValue: key) { bindings[shortcut] = binding }
        }
        shortcuts.update(actions, bindings: bindings, enabled: true)
    }

    /// Toggle the timer, but refuse to *start* a focus session when the
    /// "require a task" rule is on and nothing is selected — pop the quick-add
    /// window instead so the user can capture one.
    public func toggleRespectingTaskGuard() {
        if !timer.isRunning,
           timer.phase == .focus,
           timer.settings.requireTaskForFocus,
           TaskStore.shared.activeTask == nil {
            quickAddController?.showQuickAdd()
            return
        }
        timer.toggle()
    }

    public func syncAlarm() {
        // Honor the "alarm sound" toggle centrally: a disabled alarm maps to `.silent`
        // so every `playSelected()` call site stays a no-op without extra guards.
        AlarmSoundService.shared.selected = timer.settings.alarmSoundEnabled
            ? (AlarmSoundService.Sound(rawValue: timer.settings.alarmSound) ?? .glass)
            : .silent
    }

    public func syncCamera() {
        // The camera runs ONLY during a break (started/stopped by BreakView), never
        // during focus. So we don't start anything here — we only tear it down if
        // the feature was switched off while a break happens to be active.
        guard !timer.settings.cameraEyeTrackingEnabled else { return }
        EyeTracker.shared.stop()
        CameraService.shared.stop()
    }

    /// Like the Floating widget, the today panel is not tied to a running
    /// session — it follows its settings flag alone.
    public func syncTodayPanel() {
        if timer.settings.showTodayPanel {
            todayPanelController?.showTodayPanel(timer: timer)
        } else {
            todayPanelController?.hideTodayPanel()
        }
    }

    /// Like the today panel, the Floating widget follows its settings flag
    /// alone — it stays up while the timer is idle so Start is always reachable.
    public func syncFloatingWidget() {
        if timer.settings.dockWidgetEnabled {
            floatingWidgetController?.showFloatingWidget(timer: timer)
        } else {
            floatingWidgetController?.hideFloatingWidget()
        }
    }

    public func installCLIBridge() {
        cliObservers.removeAll()
        cliObservers["start"]    = CLIBridge.observe(CLIBridge.darwinCommandStart)    { [weak self] p in self?.cliStart(payload: p) }
        cliObservers["pause"]    = CLIBridge.observe(CLIBridge.darwinCommandPause)   { [weak self] _ in self?.timer.pause() }
        cliObservers["resume"]   = CLIBridge.observe(CLIBridge.darwinCommandResume)  { [weak self] _ in self?.timer.start() }
        cliObservers["skip"]     = CLIBridge.observe(CLIBridge.darwinCommandSkip)    { [weak self] _ in self?.timer.skip() }
        cliObservers["stop"]     = CLIBridge.observe(CLIBridge.darwinCommandStop)    { [weak self] _ in self?.timer.stop() }
        cliObservers["add"]      = CLIBridge.observe(CLIBridge.darwinCommandAdd)     { [weak self] p in self?.cliAdjust(payload: p, negative: false) }
        cliObservers["remove"]   = CLIBridge.observe(CLIBridge.darwinCommandRemove)  { [weak self] p in self?.cliAdjust(payload: p, negative: true) }
        cliObservers["setDur"]   = CLIBridge.observe(CLIBridge.darwinCommandSetDuration) { [weak self] p in self?.cliSetDuration(p) }
        cliObservers["taskAdd"]   = CLIBridge.observe(CLIBridge.darwinCommandTaskAdd)   { [weak self] p in self?.cliTaskAdd(p, store: .shared) }
        cliObservers["taskDone"]  = CLIBridge.observe(CLIBridge.darwinCommandTaskDone)  { [weak self] p in self?.cliTaskDone(p) }
        cliObservers["taskStart"] = CLIBridge.observe(CLIBridge.darwinCommandTaskStart) { [weak self] p in self?.cliTaskStart(p) }
        cliObservers["taskQueue"] = CLIBridge.observe(CLIBridge.darwinCommandTaskQueue) { [weak self] p in self?.cliTaskQueue(p) }
        publishSnapshot()
        // Task counterpart of publishSnapshot(): every task change rewrites the
        // CLI-readable task list (and the sink fires once on install, priming it).
        snapshotCancellable = TaskStore.shared.$tasks
            .receive(on: DispatchQueue.main)
            .sink { tasks in
                CLIBridge.writeTaskSnapshot(CLIBridge.taskSnapshotEntries(from: tasks))
            }
    }

    // MARK: - Timer sync (iCloud lockstep)

    /// UserDefaults key for the "Mirror timer across Macs" toggle. Default ON
    /// while sync is on — absent key reads as true.
    public static let timerMirrorDefaultsKey = "sync.timerMirror"

    public static func timerMirrorEnabled(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: timerMirrorDefaultsKey) != nil else { return true }
        return defaults.bool(forKey: timerMirrorDefaultsKey)
    }

    /// Wires the sync engine in: fetched remote sessions drive this Mac's
    /// timer (subject to the mirror toggle), and local phase transitions
    /// publish through `publishTimerToSync()` (called from the phase and
    /// isRunning sinks in `observe()` — the narrowest seam that sees every
    /// start/pause/resume/stop/complete without touching the tick loop).
    public func installSync(engine: CloudSyncEngine) {
        syncEngine = engine
        syncCancellable = engine.$remoteTimer
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] state in self?.applyRemoteTimer(state) }
    }

    public func uninstallSync() {
        syncEngine = nil
        syncCancellable = nil
    }

    /// This Mac's session as an ActiveTimerState snapshot (see that type for
    /// the wall-clock contract).
    func currentTimerState(now: Date = Date()) -> ActiveTimerState {
        let isPaused = timer.phase == .paused
        // A non-running, non-paused timer is idle: stopped, freshly reset, or
        // waiting at a pending phase. Waiting states deliberately mirror as
        // idle too — "the timer is not running" is the truth both Macs share.
        let idle = !timer.isRunning && !isPaused
        let remaining = max(0, timer.remainingSeconds)
        return ActiveTimerState(
            deviceID: DeviceIdentity.current,
            deviceName: DeviceIdentity.name,
            phase: idle ? ActiveTimerState.idlePhase : timer.effectivePhase.rawValue,
            startedAt: now.addingTimeInterval(-max(0, timer.elapsedSeconds)),
            endsAt: idle ? nil : now.addingTimeInterval(remaining),
            isPaused: isPaused,
            taskTitle: TaskStore.shared.activeTask?.title,
            updatedAt: now)
    }

    private func publishTimerToSync() {
        guard let syncEngine, !isApplyingRemoteTimer else { return }
        let state = currentTimerState()
        if let last = lastPublishedTimer, last.samePayload(as: state) { return }
        lastPublishedTimer = state
        syncEngine.publishActiveTimer(state)
    }

    // Internal (not private) so tests can drive fetched records directly.
    func applyRemoteTimer(_ state: ActiveTimerState) {
        guard Self.timerMirrorEnabled() else { return }
        // Independent sessions may run side by side (a 10-min on one Mac, a
        // 25-min on the other): a remote record only drives this timer while
        // it is idle — nothing local to clobber — or while it is already the
        // mirror of the remote session (so the owner's pause/skip/stop keeps
        // landing). A locally-owned running or paused session is never
        // overwritten by sync.
        let engaged = timer.isRunning || timer.phase == .paused
        guard !engaged || timer.isMirroredSession else { return }
        let wasBreak = engaged && timer.effectivePhase.isBreak
        isApplyingRemoteTimer = true
        // Remember the remote payload as "already published" so the echo of
        // this apply (if any sink slips through) is deduped by content too.
        lastPublishedTimer = ActiveTimerState(
            deviceID: DeviceIdentity.current, deviceName: DeviceIdentity.name,
            phase: state.phase, startedAt: state.startedAt, endsAt: state.endsAt,
            isPaused: state.isPaused, taskTitle: state.taskTitle,
            updatedAt: state.updatedAt)
        if state.isIdle {
            timer.stop()
        } else if let phase = PomodoroPhase(rawValue: state.phase), phase != .paused {
            timer.applyMirroredSession(phase: phase,
                                       isPaused: state.isPaused,
                                       startedAt: state.startedAt,
                                       endsAt: state.endsAt,
                                       asOf: state.updatedAt)
        }
        // Mirrored phase changes never post `.phaseDidComplete`, so the break
        // overlay must be driven from HERE: a record that lands this Mac in a
        // break blocks this screen (eye exercises) too, and one that leaves
        // the break tears the overlay down again.
        let isBreakNow = timer.isMirroredSession
            && (timer.isRunning || timer.phase == .paused)
            && timer.effectivePhase.isBreak
        if isBreakNow && !wasBreak {
            beginBreakSideEffects()
        } else if wasBreak && !isBreakNow {
            endBreakSideEffects()
        }
        // The suppression flag must outlive this turn: the phase/isRunning
        // sinks re-deliver via DispatchQueue.main, i.e. on a LATER queue slot
        // — which is already enqueued by now, so clearing behind them is safe.
        DispatchQueue.main.async { [weak self] in
            self?.isApplyingRemoteTimer = false
        }
    }

    /// Dispatch a parsed `sharingan://` URL command through the exact same
    /// paths the CLI bridge uses. `.show` is a UI concern (window managers
    /// live in the app target) and is handled by the AppDelegate instead.
    public func handle(_ command: URLCommand) {
        switch command {
        case .start(let interval):
            if let interval { timer.setCustomDuration(interval) }
            if !timer.isRunning { timer.start() }
            publishSnapshot()
        case .pause:
            timer.pause()
        case .resume:
            timer.start()
        case .skip:
            timer.skip()
        case .reset:
            timer.stop()
        case .addTask(let text):
            cliTaskAdd(text, store: .shared)
        case .toggleFloating:
            // Compat (Task 11): `sharingan://toggle-floating` used to show/hide
            // the now-removed floating timer. Keep the URL command recognized
            // (an old Shortcuts/Raycast script must not silently fail) and
            // retarget it to the Floating widget.
            timer.settings.dockWidgetEnabled.toggle()
        case .show:
            break
        }
    }

    /// Internal (not private) with an injectable store so tests can assert
    /// exactly-once adds without touching the real database. (No `.shared`
    /// default: a MainActor-isolated default argument trips Swift 6.)
    func cliTaskAdd(_ payload: String?, store: TaskStore) {
        guard let p = payload?.trimmingCharacters(in: .whitespacesAndNewlines),
              !p.isEmpty else { return }
        // Whole documents (CLI heredocs, multi-line URL payloads) bulk-import,
        // same as every add field in the UI. Headless path — duplicates are
        // skipped silently, there is no one to ask.
        if store.importIfDocument(p) != nil { return }
        let parsed = TaskInputParser.parse(p)
        // A line of pure tokens ("ertaga 15:00") parses to an empty title —
        // fall back to the raw text so the add never silently vanishes.
        store.add(title: parsed.title.isEmpty ? p : parsed.title,
                  tags: parsed.tags,
                  dueDate: parsed.dueDate,
                  estimatedPomodoros: parsed.estimatedPomodoros,
                  recurrence: parsed.recurrence,
                  project: parsed.project,
                  priority: parsed.priority)
    }

    private func cliTaskDone(_ payload: String?) {
        guard let id = payload.flatMap(UUID.init(uuidString:)) else { return }
        TaskStore.shared.toggleDone(id)
    }

    private func cliTaskStart(_ payload: String?) {
        // setActive doesn't validate the id, so an id the store has never seen
        // (a stale CLI snapshot) must not become the "active task".
        guard let id = payload.flatMap(UUID.init(uuidString:)),
              TaskStore.shared.tasks.contains(where: { $0.id == id }) else { return }
        TaskStore.shared.setActive(id)
    }

    private func cliTaskQueue(_ payload: String?) {
        guard let id = payload.flatMap(UUID.init(uuidString:)),
              TaskStore.shared.tasks.contains(where: { $0.id == id }) else { return }
        focusQueue.enqueue(id)
    }

    private func cliStart(payload: String?) {
        let p = payload ?? ""
        if p.isEmpty {
            if !timer.isRunning { timer.start() }
        } else if let parsed = NaturalLanguageParser.parse(p) {
            timer.applyParsed(parsed)
            if case .setDuration = parsed.kind, !timer.isRunning { timer.start() }
        } else if let mins = Int(p) {
            timer.setCustomDuration(TimeInterval(mins) * 60)
            if !timer.isRunning { timer.start() }
        }
        publishSnapshot()
    }

    private func cliAdjust(payload: String?, negative: Bool) {
        let p = payload ?? "5m"
        let parsed = NaturalLanguageParser.parse(p)
        if case .addTime(let d) = parsed?.kind {
            timer.addTime(negative ? -d : d)
        } else if case .removeTime(let d) = parsed?.kind {
            timer.addTime(negative ? d : -d)
        } else if let mins = Int(p.trimmingCharacters(in: .letters).trimmingCharacters(in: .whitespaces)),
                  mins > 0 {
            timer.addTime(Double(negative ? -mins : mins) * 60)
        }
        publishSnapshot()
    }

    private func cliSetDuration(_ p: String?) {
        guard let p = p, !p.isEmpty else { return }
        if let parsed = NaturalLanguageParser.parse(p), case .setDuration(let d) = parsed.kind {
            timer.setCustomDuration(d)
        } else if let mins = Int(p.trimmingCharacters(in: .letters).trimmingCharacters(in: .whitespaces)), mins > 0 {
            timer.setCustomDuration(TimeInterval(mins) * 60)
        }
        publishSnapshot()
    }

    /// Reference point of the last write, used to skip writes the CLI can
    /// reconstruct on its own (the natural 1 s countdown).
    private var lastSnapshotRef: (remaining: TimeInterval, at: Date)?

    public func publishSnapshot() {
        let snap = CLIBridge.StateSnapshot(
            phase: timer.phase,
            remainingSeconds: timer.remainingSeconds,
            totalSeconds: timer.totalSeconds,
            isRunning: timer.isRunning,
            cyclesCompletedToday: timer.stats.completedTodayCount(),
            streak: timer.stats.streak.currentStreak,
            updatedAt: Date()
        )
        lastSnapshotRef = (timer.remainingSeconds, Date())
        CLIBridge.writeSnapshot(snap)
    }

    // NOTE: all sinks hop via DispatchQueue.main, NOT RunLoop.main — the
    // RunLoop scheduler only fires in the .default run-loop mode, so an open
    // menu or a drag/scroll (event-tracking mode) would stall the break
    // overlay, alarm, and DND toggle until tracking ends.
    private func observe() {
        // `object: timer`, not any timer: previews and tests build their own
        // PomodoroTimer instances, and an unfiltered subscription made every
        // coordinator react to every timer's completions.
        NotificationCenter.default.publisher(for: .phaseDidComplete, object: timer)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in self?.handlePhaseComplete(note) }
            .store(in: &cancellables)

        // Safety net for the break overlay: `.phaseDidComplete` only fires when
        // a countdown runs to zero, but a break can also end via skip/stop —
        // global shortcut, CLI, `startFocusSession` — paths that jump straight
        // to focus without the notification and used to strand the overlay
        // (plus ambience/dim) on screen. Tear everything down on ANY arrival
        // at focus; every call is idempotent, so the natural-completion path
        // running them a second time is harmless. `.paused` is deliberately
        // not a teardown: a paused break is still a break.
        timer.$phase
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                guard let self, phase == .focus else { return }
                self.breakPresenter?.dismissAll()
                BreakAmbienceService.shared.stop()
                self.restoreBrightness()
                EyeTracker.shared.stop()
                CameraService.shared.stop()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .focusFiveMinLeft)
            .receive(on: DispatchQueue.main)
            .sink { _ in NotificationService.shared.focusFiveMinLeft() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .streakUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in self?.handleStreakUpdate(note) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .dailyGoalReached)
            .receive(on: DispatchQueue.main)
            .sink { note in
                let n = note.userInfo?["count"] as? Int ?? 0
                NotificationService.shared.notify(
                    title: "Daily goal reached 🎯",
                    body: "\(n)/\(n) pomodoros today. Great work!",
                    identifier: "sharingan.dailyGoal")
            }
            .store(in: &cancellables)

        timer.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                guard let self else { return }
                // Starting a focus session settles the "which task next?"
                // question, whichever way the user answered it.
                if running && self.timer.phase == .focus { self.needsTaskPick = false }
                // Blocking distracting apps follows the running state so pausing
                // a focus session releases them, resuming re-blocks.
                self.refreshAppBlocker()
                self.syncDND()
                self.publishSnapshot()
                // Start/pause/resume/stop all flip isRunning — the timer-sync
                // publish rides this sink (deduped by payload inside).
                self.publishTimerToSync()
            }
            .store(in: &cancellables)

        timer.$settings
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] s in
                self?.syncChanged(s)
                self?.syncDND()
            }
            .store(in: &cancellables)

        // Picking any task — from the queue, the task list, or quick-add —
        // answers the "which task next?" question.
        TaskStore.shared.$activeTaskID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] id in
                if id != nil { self?.needsTaskPick = false }
            }
            .store(in: &cancellables)

        timer.$phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.publishSnapshot()
                self?.refreshAppBlocker()
                // Skip/complete change the phase without necessarily flipping
                // isRunning (auto-start) — publish here too, deduped inside.
                self?.publishTimerToSync()
            }
            .store(in: &cancellables)
        // The CLI reconstructs a running countdown from `updatedAt`, so the
        // per-second tick needs no write — only publish when remaining jumps
        // in a way wall-clock can't explain (addTime, set, stop, …).
        timer.$remainingSeconds
            .receive(on: DispatchQueue.main)
            .dropFirst()
            .sink { [weak self] rem in
                guard let self else { return }
                guard let last = self.lastSnapshotRef else { self.publishSnapshot(); return }
                let elapsed = Date().timeIntervalSince(last.at)
                let expected = self.timer.isRunning ? last.remaining - elapsed : last.remaining
                if abs(rem - expected) > 2 { self.publishSnapshot() }
            }
            .store(in: &cancellables)
    }

    /// The last settings value each service group was synced against. Syncing
    /// everything on every `$settings` emission re-registered all Carbon
    /// hotkeys and re-queried SMAppService dozens of times per second while a
    /// slider was being dragged — so each group only syncs when its own slice
    /// of the settings actually changed.
    private var lastSyncedSettings: PomodoroSettings?

    private func syncChanged(_ new: PomodoroSettings) {
        guard let old = lastSyncedSettings else {
            lastSyncedSettings = new
            syncAll()
            return
        }
        lastSyncedSettings = new
        if old.alarmSoundEnabled != new.alarmSoundEnabled
            || old.alarmSound != new.alarmSound { syncAlarm() }
        if old.globalShortcutsEnabled != new.globalShortcutsEnabled
            || old.shortcutBindings != new.shortcutBindings { installShortcuts() }
        if old.cameraEyeTrackingEnabled != new.cameraEyeTrackingEnabled { syncCamera() }
        if old.showTodayPanel != new.showTodayPanel { syncTodayPanel() }
        if old.dockWidgetEnabled != new.dockWidgetEnabled
            || old.dockWidgetSize != new.dockWidgetSize
            || old.dockWidgetAlignment != new.dockWidgetAlignment
            || old.dockWidgetOpacity != new.dockWidgetOpacity
            || old.dockWidgetExpandOnHover != new.dockWidgetExpandOnHover { syncFloatingWidget() }
        if old.appBlockerSettings != new.appBlockerSettings
            || old.blockScreenDuringBreak != new.blockScreenDuringBreak
            || old.blockAppsDuringFocus != new.blockAppsDuringFocus { refreshAppBlocker() }
        if old.ttsSettings.enabled != new.ttsSettings.enabled { syncTTS() }
        if old.ambienceEnabled != new.ambienceEnabled
            || old.ambienceSound != new.ambienceSound { syncAmbience() }
        if old.reminderSettings != new.reminderSettings { syncReminders() }
        if old.launchAtLogin != new.launchAtLogin { syncLaunchAtLogin() }
        if old.ttsSettings != new.ttsSettings
            || old.ttsRate != new.ttsRate
            || old.ttsPitch != new.ttsPitch {
            TTSKalibrator.shared.update(settings: new.ttsSettings,
                                        rate: new.ttsRate,
                                        pitch: new.ttsPitch)
        }
        if old.exerciseSettings != new.exerciseSettings {
            ExerciseValidator.shared.exercises = new.exerciseSettings.buildSequence()
        }
    }

    private func syncAll() {
        syncAlarm()
        installShortcuts()
        syncCamera()
        syncTodayPanel()
        syncFloatingWidget()
        refreshAppBlocker()
        syncTTS()
        syncAmbience()
        syncReminders()
        syncLaunchAtLogin()
        TTSKalibrator.shared.update(settings: timer.settings.ttsSettings,
                                    rate: timer.settings.ttsRate,
                                    pitch: timer.settings.ttsPitch)
        ExerciseValidator.shared.exercises = timer.settings.exerciseSettings.buildSequence()
    }

    private func syncLaunchAtLogin() {
        let want = timer.settings.launchAtLogin
        guard want != LaunchAtLoginService.shared.isEnabled else { return }
        LaunchAtLoginService.shared.setEnabled(want)
    }

    private func syncTTS() {
        guard timer.settings.ttsSettings.enabled else {
            TTSService.shared.stop()
            return
        }
    }

    private func syncAmbience() {
        BreakAmbienceService.shared.selected =
            BreakAmbienceService.Ambience(rawValue: timer.settings.ambienceSound) ?? .rain
        if timer.settings.ambienceEnabled, timer.phase.isBreak {
            BreakAmbienceService.shared.start()
        } else if !timer.settings.ambienceEnabled {
            BreakAmbienceService.shared.stop()
        }
    }

    private func syncReminders() {
        ReminderService.shared.update(timer.settings.reminderSettings,
                                      focusPhase: timer.phase == .focus)
    }

    private func startAmbience() {
        guard timer.settings.ambienceEnabled else { return }
        BreakAmbienceService.shared.selected =
            BreakAmbienceService.Ambience(rawValue: timer.settings.ambienceSound) ?? .rain
        BreakAmbienceService.shared.start()
    }

    private func startBrightnessDim() {
        BrightnessService.shared.enabled = timer.settings.brightnessDimEnabled
        BrightnessService.shared.levelPercent = Float(timer.settings.brightnessDimPercent)
        BrightnessService.shared.smooth = timer.settings.brightnessSmooth
        BrightnessService.shared.dimToBreak()
        // Night Shift warmth shares the dim lifecycle: on at break start,
        // restored at break end. Off by default; no-ops when unavailable.
        if timer.settings.nightShiftBreakEnabled {
            NightShiftService.shared.beginBreakWarmth(
                strength: Float(timer.settings.nightShiftBreakStrength))
        }
    }

    private func restoreBrightness() {
        BrightnessService.shared.restore()
        // Idempotent: a no-op when the warmth was never begun (setting off).
        NightShiftService.shared.endBreakWarmth()
    }

    /// Drive the app blocker from the current phase + settings: block during a
    /// break (when "block screen" is on) and/or during a running focus session
    /// (when "block during focus" is on).
    func refreshAppBlocker() {
        let s = timer.settings
        let blocker = s.appBlockerSettings
        guard blocker.enabled else {
            AppBlockerService.shared.deactivate()
            return
        }
        // "Always block" mode (onlyDuringBreak == false): keep distracting apps
        // blocked the whole time the app runs, regardless of phase.
        if !blocker.onlyDuringBreak {
            AppBlockerService.shared.update(blocker)
            AppBlockerService.shared.activate()
            return
        }
        // Otherwise blocking is phase-driven: during a break (when "block screen"
        // is on) and/or during a running focus session (when "block during focus").
        let isBreak = (timer.phase == .shortBreak || timer.phase == .longBreak)
        let isFocus = (timer.phase == .focus)
        let shouldBlock = (isBreak && s.blockScreenDuringBreak)
            || (isFocus && s.blockAppsDuringFocus && timer.isRunning)
        if shouldBlock {
            AppBlockerService.shared.update(blocker)
            AppBlockerService.shared.activate()
        } else {
            AppBlockerService.shared.deactivate()
        }
    }

    /// DND follows "a focus session is actually running" — pausing or
    /// finishing focus restores normal mode; breaks never engage it.
    public func syncDND() {
        DNDShortcutService.shared.sync(
            focusActive: timer.isRunning && timer.phase == .focus,
            settings: timer.settings)
    }

    private func handlePhaseComplete(_ note: Notification) {
        guard let phase = note.userInfo?["phase"] as? PomodoroPhase else { return }
        syncDND()
        let willRepeat = note.userInfo?["willRepeat"] as? Bool ?? false
        let mirrored = note.userInfo?["mirrored"] as? Bool ?? false
        // A mirrored phase just ran out — the owner Mac is publishing what
        // comes next right now. Fetch immediately instead of waiting for the
        // poll, so the follow-up (break start, next focus) lands in seconds.
        if mirrored { syncEngine?.fetchChanges() }
        switch phase {
        case .focus:
            // Synced data is credited by the session's OWNER Mac only — the
            // task syncs over, so a mirror crediting it too double-counted
            // the pomodoro and advanced the queue twice.
            if !mirrored {
                // A completed focus still counts as a pomodoro for the active task.
                if let taskID = TaskStore.shared.activeTaskID {
                    let seconds = note.userInfo?["seconds"] as? TimeInterval ?? 0
                    TaskStore.shared.incrementPomodoro(taskID, seconds: seconds)
                }
                // The finished session hands the active slot to the next queued task.
                advanceQueueAfterFocus(store: TaskStore.shared)
            }
            AlarmSoundService.shared.playSelected()

            // Repetition: no break happens, so skip the entire break sequence
            // (overlay, dim, ambience, blocker) — just note the rep and return.
            if willRepeat {
                NotificationService.shared.notify(
                    title: "Sharingan",
                    body: "Focus session done — next repetition starting.",
                    identifier: "sharingan.repeat")
                return
            }

            // A mirrored focus rolls to a *pending* break (the owner Mac
            // decides when the break actually starts), so presenting the
            // overlay here froze its countdown at full length. The overlay
            // comes up when the owner's break record applies in
            // `applyRemoteTimer` — with a live, ticking session behind it.
            if mirrored { return }
            NotificationService.shared.notify(
                title: "Sharingan",
                body: "Focus complete. Starting break.",
                identifier: "sharingan.focusDone")
            beginBreakSideEffects()
        case .shortBreak, .longBreak:
            NotificationService.shared.notify(
                title: "Sharingan",
                body: "Break complete. Back to focus.",
                identifier: "sharingan.breakDone")
            AlarmSoundService.shared.playSelected()
            endBreakSideEffects()
            // Mirror Macs only tear the overlay down — the owner Mac runs the
            // "what's next" ceremony (TTS, task pick) and publishes the result.
            guard !mirrored else { return }
            speakFocusStart()
            // Queue drained and nothing active → ask the UI for the next task.
            evaluateTaskPickAfterBreak(store: TaskStore.shared)
        case .paused:
            break
        }
    }

    /// Everything that makes a break tangible on this screen — overlay (eye
    /// exercises), TTS, ambience, dim, blocker. Shared by the local
    /// phase-complete path and the mirrored-session path, so a break synced
    /// in from another Mac blocks this screen exactly like a local one.
    private func beginBreakSideEffects() {
        ReminderService.shared.pauseForBreak()
        if let p = breakPresenter, timer.settings.blockScreenDuringBreak {
            p.presentBreak(
                timer: timer,
                onTapSkip: { [weak self] in self?.timer.skip() }
            )
        }
        speakBreakStart()
        startAmbience()
        startBrightnessDim()
        refreshAppBlocker()
    }

    /// The teardown twin of `beginBreakSideEffects` — also shared by both
    /// paths, so a mirrored break that ends (or is skipped on the owner Mac)
    /// releases this screen too.
    private func endBreakSideEffects() {
        breakPresenter?.dismissAll()
        BreakAmbienceService.shared.stop()
        restoreBrightness()
        refreshAppBlocker()
        // Belt-and-suspenders: BreakView.onDisappear stops the camera, but make
        // sure it's released even if the break was dismissed some other way.
        EyeTracker.shared.stop()
        CameraService.shared.stop()
        ReminderService.shared.resumeForFocus()
    }

    // MARK: - Focus queue

    /// After a focus session completes (and the pomodoro is credited), moves
    /// the queue along:
    /// - A finished task that is now *done* falls out of the queue wherever it
    ///   sits, and the next valid queued task becomes active.
    /// - A finished task at the queue *head* (done or not) yields the head to
    ///   the next valid queued task — each session advances the queue.
    /// When the queue yields nothing (or the active task was never queued),
    /// the active task is left untouched.
    func advanceQueueAfterFocus(store: TaskStore) {
        guard let finishedID = store.activeTaskID else { return }
        let finishedIsDone = store.tasks.first { $0.id == finishedID }?.isDone ?? true
        if focusQueue.taskIDs.contains(finishedID), finishedIsDone {
            focusQueue.remove(finishedID)
            if let next = focusQueue.current(validatedAgainst: store) {
                store.setActive(next)
            }
        } else if focusQueue.current(validatedAgainst: store) == finishedID {
            if let next = focusQueue.advance(validatedAgainst: store) {
                store.setActive(next)
            }
        }
    }

    /// After a break ends: flag the UI to ask "which task next?" when the
    /// queue has no valid entry AND there's no open active task. Also clears
    /// a stale flag when there *is* something to work on.
    func evaluateTaskPickAfterBreak(store: TaskStore) {
        let hasOpenActiveTask = store.activeTask.map { !$0.isDone } ?? false
        needsTaskPick = focusQueue.current(validatedAgainst: store) == nil
            && !hasOpenActiveTask
    }

    /// The UI's answer to `needsTaskPick`: activates the chosen task (nil
    /// means "no task, thanks") and clears the flag.
    public func resolveTaskPick(with id: UUID?) {
        resolveTaskPick(with: id, store: TaskStore.shared)
    }

    /// Store-injectable core of `resolveTaskPick(with:)` (tests).
    func resolveTaskPick(with id: UUID?, store: TaskStore) {
        if let id { store.setActive(id) }
        needsTaskPick = false
    }

    private func speakBreakStart() {
        guard timer.settings.ttsSettings.enabled else { return }
        TTSService.shared.speak(
            "Break started. \(timer.settings.breakMessage)",
            rate: timer.settings.ttsRate,
            pitch: timer.settings.ttsPitch)
    }

    private func speakFocusStart() {
        guard timer.settings.ttsSettings.enabled else { return }
        TTSService.shared.speak(
            "Break complete. You can return to focus.",
            rate: timer.settings.ttsRate,
            pitch: timer.settings.ttsPitch)
    }

    private func handleStreakUpdate(_ note: Notification) {
        guard let streak = note.userInfo?["streak"] as? StreakStore else { return }
        // Announce ONLY a newly-unlocked milestone. Reading the lingering
        // pendingReward instead made it re-speak "First pomodoro" on every
        // pomodoro until the banner was dismissed.
        guard let reward = StreakRewardCenter.shared.evaluate(streak: streak.currentStreak) else {
            return
        }
        NotificationService.shared.notify(
            title: "Sharingan — Milestone achieved",
            body: "\(reward.badge.emoji) \(reward.badge.title): \(reward.badge.subtitle)",
            identifier: "sharingan.streak.\(reward.badge.id)"
        )
        if timer.settings.ttsSettings.enabled {
            TTSService.shared.speak(
                "Achievement unlocked: \(reward.badge.title). \(reward.badge.subtitle)",
                rate: timer.settings.ttsRate,
                pitch: timer.settings.ttsPitch)
        }
    }
}