import AppKit
import SwiftUI
import Combine
import SharinganCore

/// The notch HUD's window. One `NSPanel` on one screen, pinned to the top
/// center and **only ever as tall as the current island state's silhouette**
/// (`NotchGeometry.panelHeight`; `syncPanelFrame` follows every state change).
/// It is *above* the menu bar, so the content view's `hitTest` must return nil
/// everywhere the island isn't drawn — otherwise the top of the screen stops
/// accepting clicks. The frame hugging is the second, sturdier line of the same
/// defense: hit-testing and alpha click-through only protect the region the
/// window covers *correctly*, and the window server's cached click shape for a
/// transparent window has been observed to go stale — so the closed island
/// simply leaves no window over the desktop below the menu bar at all.
@MainActor
final class NotchWindowManager {
    static let shared = NotchWindowManager()

    private var panel: NSPanel?
    private var screenObserver: NSObjectProtocol?
    private var cancellables: Set<AnyCancellable> = []
    private var activityJob: Task<Void, Never>?
    private var hoverJob: Task<Void, Never>?
    /// The pending *deferred* frame change, `nil` when none is in flight: a
    /// shrink (or an order-out for `.hidden`) waits out the island's collapse
    /// animation before touching the window. Cancelled by the next state
    /// change — a rapid re-open flips the frame back before this ever lands —
    /// and by anything that re-places or tears down the panel wholesale.
    private var frameJob: Task<Void, Never>?
    /// What the in-flight `hoverJob` is about to commit, `nil` when nothing is
    /// pending. Debouncing has to compare against *this*, not the committed
    /// `state.hovering` — see `hoverChanged(_:)`.
    private var pendingHover: Bool?

    private weak var timer: PomodoroTimer?
    /// The phase `syncTimer` last saw, so a flip announces exactly once. `nil`
    /// until the first tick, so app launch (restoring whatever phase the timer
    /// was already in) never announces — only a transition *observed live*
    /// does.
    private var lastPhase: PomodoroPhase?
    /// Last settings we reacted to, so a settings edit re-places the panel while
    /// a plain countdown tick does not. `content` carries the ears *and* the
    /// section switches, because both resize the island — and the panel's frame
    /// is cut from that size.
    private var appliedSettings: (enabled: Bool, content: NotchContentConfig,
                                  activity: Bool)?
    let model = NotchHUDModel()

    func install(timer: PomodoroTimer, coordinator: SharinganCoordinator) {
        self.timer = timer

        // Track the timer so the ears and progress bar follow it.
        // `DispatchQueue.main`, not `RunLoop.main`: the latter schedules in the
        // default run-loop mode only, so the sink is starved while a menu is
        // tracking or a window is being live-dragged — and the island's
        // countdown would visibly freeze.
        timer.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak timer] _ in
                guard let self, let timer else { return }
                self.syncTimer(timer)
                self.refreshIfSettingsChanged(timer.settings)
            }
            .store(in: &cancellables)

        // The only signal that a phase truly *finished*: `PomodoroTimer` posts
        // it from `phaseComplete()` and from nowhere else, so — unlike the phase
        // sink above, which sees pauses, resumes, resets and skips alike — what
        // arrives here really did run to zero. "Session complete" is announced
        // from here or not at all.
        NotificationCenter.default.publisher(for: .phaseDidComplete)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let phase = note.userInfo?["phase"] as? PomodoroPhase,
                      let activity = NotchActivity.forCompletedPhase(phase) else { return }
                self?.announce(activity)
            }
            .store(in: &cancellables)

        // The island is sized from the number of task rows the panel actually
        // draws, so the task list — and the focus queue, which orders it — are
        // inputs to the *geometry*, not just to the content. Tick a task off the
        // island and it has to close up behind it.
        //
        // The queue comes from the `coordinator` we were handed, not from
        // `AppServices`: that is the same object, but only once the AppDelegate
        // has assigned it, and subscribing to the orphan queue instead would be a
        // silent no-op that nothing would ever fail on.
        //
        // `receive(on:)` and not a direct sink: `objectWillChange` fires *before*
        // the store has changed, so a synchronous read here would count the row
        // that is about to leave. The hop puts the read after the mutation, which
        // is the same reason the timer sink above takes it.
        for source in [TaskStore.shared.objectWillChange.eraseToAnyPublisher(),
                       coordinator.focusQueue.objectWillChange.eraseToAnyPublisher()] {
            source
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.syncTaskRows() }
                .store(in: &cancellables)
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { NotchWindowManager.shared.refresh() }
        }

        // The window's frame follows the island's state: grow before the
        // opening spring, shrink after the closing one (see `syncPanelFrame`).
        // Subscribed to the model rather than hooked into each state write —
        // `state` is written from half a dozen places (hover commits,
        // announcements, timer ticks, settings, the break overlay), and the
        // window has to follow all of them or none.
        //
        // Deliberately *no* `receive(on:)`: `$state` emits synchronously during
        // the write (always on the main actor here), which is what puts a
        // *growing* resize ahead of the SwiftUI render pass that starts the
        // opening spring — the island only ever springs inside a window that
        // already has room for it. The sink reads nothing off `model.state`
        // (mid-willSet it would still be the old value); the new size arrives
        // as the element.
        model.$state
            .map(\.size)
            .removeDuplicates()
            .sink { [weak self] size in self?.syncPanelFrame(for: size) }
            .store(in: &cancellables)

        syncTimer(timer)
        refresh()
    }

    // MARK: - Task rows

    /// The user's real open work, in the order and to the cap the expanded island
    /// shows it: the active task, then the focus queue, then today's tasks, then
    /// the rest of the open list — deduped (see `NotchTaskRows`). The last tier is
    /// why an all-undated task list still fills the island instead of reporting
    /// "No open tasks": the `.today` filter can't see a dateless task, but the
    /// open-tasks fallback can.
    ///
    /// **This is the single list.** `NotchExpandedPanel` renders exactly what it
    /// returns, and `syncTaskRows` sizes the island from exactly its count — so
    /// the island cannot reserve room for a row the panel does not draw, and the
    /// panel cannot draw a row the island (and its hit-test mask) was not sized
    /// for. Two separate readings of the list would be free to drift, and the
    /// drifting one would be a clipped row or a strip of dead black.
    static func taskRows(limit: Int) -> [TaskItem] {
        let store = TaskStore.shared
        // Tier 4: the open list, most-recently-created first. There is no
        // "last touched" stamp on a task, so creation time is the closest
        // stand-in for "most recently relevant" — a task added just now is the
        // likeliest thing the user means to work on.
        let fallback = store.tasks
            .filter { !$0.isDone }
            .sorted { $0.createdAt > $1.createdAt }
        return NotchTaskRows.rows(today: store.grouped(filter: .today).flatMap(\.items),
                                  queue: AppServices.focusQueue.taskIDs,
                                  active: store.activeTaskID,
                                  fallback: fallback,
                                  limit: limit)
    }

    /// Republish the row count into the model's config, which is where the
    /// geometry reads it — one write, so the drawn shape, the mask and the
    /// panel's list all keep coming off one number.
    ///
    /// The panel's *window* is not re-placed: `NotchGeometry.panelHeight` (and
    /// `panelSize`, the geometry's canvas) are pinned to the row cap on
    /// purpose, so the open window already covers the fullest list this config
    /// can draw. Resizing the window here would clip the island while it is
    /// still springing to its new height (see `panelHeight`).
    private func syncTaskRows() {
        let count = Self.taskRows(limit: model.config.clampedTaskRows).count
        guard model.config.taskCount != count else { return }
        model.config.taskCount = count
    }

    /// Re-reads settings and screens: shows, hides or re-places the panel.
    func refresh() {
        guard let timer else { return }
        let settings = timer.settings
        appliedSettings = (settings.notchHUDEnabled, settings.notchContent,
                           settings.notchLiveActivity)
        model.state.enabled = settings.notchHUDEnabled
        model.state.liveActivityEnabled = settings.notchLiveActivity
        // The one write of the config: the view's layout, the panel's sections
        // and the hosting view's hit-test mask all read it back off the model.
        //
        // The settings only carry the row *cap*; the count of rows there actually
        // are is not a setting and has to be stamped on here, or a settings edit
        // would reset the island to the cap and hang the dead black back over the
        // screen until the next task edit.
        let rows = Self.taskRows(limit: settings.notchContent.clampedTaskRows).count
        model.config = settings.notchContent.withTaskCount(rows)

        guard settings.notchHUDEnabled, let screen = Self.hudScreen() else {
            teardown()
            return
        }
        model.metrics = Self.metrics(for: screen)
        place(on: screen)
    }

    /// The timer publishes on every tick; only a *settings* edit needs the panel
    /// re-placed, so filter the firehose down to the notch keys. The content
    /// switches are in here and not merely cosmetic: each one resizes the
    /// island, and the panel's frame is cut from that size, so a flipped
    /// checkbox that never reached `place(on:)` would leave the panel sized for
    /// the old island and clip the new one.
    private func refreshIfSettingsChanged(_ settings: PomodoroSettings) {
        let now = (settings.notchHUDEnabled, settings.notchContent,
                   settings.notchLiveActivity)
        guard let applied = appliedSettings else { refresh(); return }
        guard applied != now else { return }
        refresh()
    }

    func announce(_ activity: NotchActivity) {
        guard model.state.enabled, model.state.liveActivityEnabled else { return }
        model.state.activity = activity
        activityJob?.cancel()
        activityJob = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(NotchGeometry.activityDuration))
            guard !Task.isCancelled else { return }
            self?.model.state.activity = nil
        }
    }

    /// The break overlay covers the whole screen; the HUD stands down so it
    /// isn't drawing an island on top of it.
    ///
    /// Raising the overlay is a *suspension*, exactly like `teardown()`, and it
    /// has to forget the pointer for the same reason — with one extra edge the
    /// teardown path does not have: the overlay is a `.screenSaver`-level window,
    /// so it lands **on top of** the notch panel. A pointer resting on the island
    /// when the break begins may therefore never produce the `mouseExited` that
    /// would have closed it. Without this reset the island comes back `.expanded`
    /// when the break ends — full hit-test mask over the menu bar, pointer
    /// nowhere near it, and nothing left that can close it.
    func setBreakOverlay(_ up: Bool) {
        model.state.breakOverlayUp = up
        if up { suspendInteraction() }
    }

    /// The half of `teardown()` that is about *state* rather than the window:
    /// cancel the jobs, and clear what they were going to clear. Cancelling alone
    /// is not enough — a cancelled hover job leaves `hovering` set at whatever it
    /// was, which is the bug `NotchHUDState.clearTransientInteraction` describes.
    ///
    /// Shared by the two ways the island goes away: the HUD being switched off
    /// (or its screen disappearing) and the break overlay coming up.
    private func suspendInteraction() {
        hoverJob?.cancel()
        hoverJob = nil
        pendingHover = nil
        activityJob?.cancel()
        activityJob = nil
        model.state.clearTransientInteraction()
        model.pointerInside = false
    }

    // MARK: - Screen

    /// A real hardware notch: a top safe-area inset *and* both auxiliary areas,
    /// which is what makes the cutout width computable. Without both, `notchWidth`
    /// would come out 0 and the island would have nothing to sit on.
    private static func hasHardwareNotch(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0
            && screen.auxiliaryTopLeftArea != nil
            && screen.auxiliaryTopRightArea != nil
    }

    /// The one screen the HUD lives on: the notched one, or none at all. It never
    /// follows the mouse and it never falls back to a notchless display — on a
    /// Mac with no notch there is simply no HUD, and `refresh()` tears the panel
    /// down.
    static func hudScreen() -> NSScreen? {
        NSScreen.screens.first(where: { hasHardwareNotch($0) })
    }

    static func metrics(for screen: NSScreen) -> NotchScreenMetrics {
        let frame = screen.frame
        let visible = screen.visibleFrame
        // The menu bar is exactly the strip `visibleFrame` gives up at the *top*
        // of `frame`. (The brief subtracted the total inset minus the top gap,
        // which is the Dock's reserve, not the menu bar's — see the report.)
        // Auto-hidden menu bar / full screen reports a 0 gap, so fall back to the
        // notch height, then to the status bar's own thickness.
        let topGap = frame.maxY - visible.maxY
        let notchHeight = screen.safeAreaInsets.top
        let menuBarHeight = max(topGap, notchHeight, NSStatusBar.system.thickness, 24)

        var notchWidth: CGFloat = 0
        if notchHeight > 0 {
            let left = screen.auxiliaryTopLeftArea?.width ?? 0
            let right = screen.auxiliaryTopRightArea?.width ?? 0
            if left > 0, right > 0 {
                notchWidth = frame.width - left - right
            }
        }
        return NotchScreenMetrics(
            screenWidth: frame.width,
            menuBarHeight: menuBarHeight,
            notchWidth: max(0, notchWidth),
            notchHeight: notchHeight)
    }

    // MARK: - Panel

    /// The window's frame for one island state: the union **width** (the live
    /// ears legitimately span it, and its side margins sit in the menu-bar row,
    /// which the silhouette mask already hands back), the state's own
    /// **height** (`NotchGeometry.panelHeight`), top edge pinned to the
    /// screen's.
    ///
    /// The pinning is what makes a resize coordinate-neutral: AppKit is y-up,
    /// the geometry y-down with its origin at the panel's *top*-left, so a
    /// top-pinned window whose only moving edge is the bottom
    /// (`origin.y = screen.maxY - height`) never shifts a coordinate the mask,
    /// the tracking or the views use — geometry (0,0) stays exactly at the
    /// screen's top-center-left of the panel, whatever the height.
    private func panelFrame(on screen: NSScreen, for size: NotchHUDSize) -> NSRect {
        let width = NotchGeometry.panelSize(model.metrics, config: model.config).width
        let height = NotchGeometry.panelHeight(model.metrics, size: size,
                                               config: model.config)
        return NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,   // top-anchored (AppKit y-up)
            width: width, height: height)
    }

    /// One place for the frame write and what has to follow it: the shadow is
    /// invalidated (harmless while `hasShadow` is false, and mandatory the day
    /// it isn't — a borderless window's shadow is cached against its old
    /// shape). The tracking area needs nothing here: it is `.inVisibleRect`,
    /// so it follows the view's visible rect by itself, and the hosting view
    /// autoresizes with the window (`autoresizingMask = [.width, .height]`).
    private func apply(_ frame: NSRect, to panel: NSPanel) {
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    /// Resize the window to hug `size`'s silhouette — **the dead-click-zone
    /// fix** (see the class comment and `NotchGeometry.panelHeight`). Runs on
    /// every state change, and the direction decides the clock:
    ///
    /// - **Growing** (or staying): resize immediately. The sink fires
    ///   synchronously during the state write, before SwiftUI has rendered the
    ///   change, so the opening spring always plays inside a window that
    ///   already has room for it.
    /// - **Shrinking**: the collapse animation has to play inside the old,
    ///   larger window first — a window that shrinks on the spot clips the
    ///   island mid-spring — so the resize waits out
    ///   `NotchMotion.windowShrinkDelay`. The job is cancelled by the next
    ///   state change: hover back within the beat and the shrink never lands.
    ///   (It also cannot shrink under a pointer that is *using* the island: a
    ///   shrink only follows a state change to a smaller shape, and the only
    ///   route out of `.expanded` is the hover debounce having already said
    ///   the pointer left.)
    /// - **`.hidden`**: ordered out entirely, after the same beat (the island
    ///   fades over its departure — and this path is the break overlay, whose
    ///   `.screenSaver`-level window is covering the screen anyway; *disabling*
    ///   the HUD tears the panel down via `refresh()` instead). No window, no
    ///   stale click shape, nothing to swallow a click.
    ///
    /// Hover keeps working across all of it. In idle/live the window is
    /// exactly the menu-bar strip — which is where the island, the only hover
    /// target, lives, so the tracking area still sees the pointer. Opening
    /// grows the window before the body springs down, so the pointer can
    /// travel into the body without ever leaving the window. And when the
    /// window does shrink under a pointer idling where the body used to be,
    /// the resulting `mouseExited` is a no-op: the island closed the moment
    /// the debounce saw the pointer leave it, long before this fired.
    private func syncPanelFrame(for size: NotchHUDSize) {
        frameJob?.cancel()
        frameJob = nil
        guard let panel, let screen = Self.hudScreen() else { return }

        guard size != .hidden else {
            frameJob = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(NotchMotion.windowShrinkDelay))
                guard !Task.isCancelled else { return }
                self?.panel?.orderOut(nil)
                self?.frameJob = nil
            }
            return
        }

        let frame = panelFrame(on: screen, for: size)
        guard panel.isVisible else {
            // Back from `.hidden`: nothing is animating inside a window that
            // is not on screen, so there is no collapse to protect — frame it
            // to the new state and show it, whatever direction that is.
            apply(frame, to: panel)
            panel.orderFrontRegardless()
            return
        }

        if frame.height >= panel.frame.height {
            apply(frame, to: panel)
        } else {
            frameJob = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(NotchMotion.windowShrinkDelay))
                guard !Task.isCancelled, let self, let panel = self.panel else { return }
                self.apply(frame, to: panel)
                self.frameJob = nil
            }
        }
    }

    private func place(on screen: NSScreen) {
        // Before anything is built: a panel with no timer to host has nothing
        // to show, and constructing one first would just leak it.
        guard let timer else { return }
        // A re-place is a re-decision: whatever deferred resize was in flight
        // was computed against the old screen or the old settings.
        frameJob?.cancel()
        frameJob = nil

        let size = model.state.size
        // `.hidden` with the HUD still enabled is the break overlay. Keep the
        // panel built (so the state change that ends the break has a window to
        // bring back — `syncPanelFrame` re-frames an invisible panel before
        // showing it) but off screen; a panel first *created* mid-break takes
        // the idle frame as a sane shape to come back with.
        let frame = panelFrame(on: screen, for: size == .hidden ? .idle : size)

        if let panel {
            if size == .hidden {
                panel.orderOut(nil)
            } else {
                apply(frame, to: panel)
                if !panel.isVisible { panel.orderFrontRegardless() }
            }
            return
        }

        let panel = NotchPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false)
        // `.transient` makes the panel step aside during Mission Control /
        // Exposé (and when the app is hidden), just like the menu bar does —
        // AppKit removes transient windows from the screen for the duration.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                    .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.ignoresMouseEvents = false
        panel.isFloatingPanel = true
        // The whole hover interaction is driven by `.mouseMoved` out of the
        // hosting view's tracking area, and a window drops those on the floor
        // unless it is told to accept them.
        panel.acceptsMouseMovedEvents = true
        // Above the menu bar — the whole point is to draw on the notch, which
        // the menu bar owns.
        panel.level = NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)

        let host = NotchHostingView(
            rootView: NotchHUDView(model: model, timer: timer)
                .environmentObject(timer))
        host.model = model
        host.autoresizingMask = [.width, .height]
        // Belt and braces with the view's own `.ignoresSafeArea()`: on a
        // notched Mac the hosted root would otherwise be inset by the screen's
        // top safe area, drawing the island a notch-height below the rect the
        // hit-test mask assumes it occupies.
        host.safeAreaRegions = []
        panel.contentView = host

        self.panel = panel
        if size != .hidden { panel.orderFrontRegardless() }
    }

    private func teardown() {
        // Cancelling the jobs is not enough: whatever they were going to clear
        // has to be cleared too, or disabling the HUD mid-hover (or
        // mid-announcement) leaves `hovering`/`activity` set and re-enabling it
        // brings the panel back already expanded. Shared with `setBreakOverlay`,
        // which is the same suspension.
        suspendInteraction()
        // A deferred frame change outliving the panel it was for would be a
        // no-op (the job re-reads `self.panel`), but cancel it anyway: the next
        // panel deserves a fresh decision.
        frameJob?.cancel()
        frameJob = nil
        guard let panel else { return }
        self.panel = nil
        panel.orderOut(nil)
        panel.contentView = nil
    }

    private func syncTimer(_ timer: PomodoroTimer) {
        model.progress = timer.progress
        model.remaining = timer.remainingSeconds
        model.phase = timer.phase
        model.state.engaged = timer.isRunning
            || (timer.remainingSeconds > 0 && timer.remainingSeconds < timer.totalSeconds)

        // A break *starting* is the one moment this sink interrupts for, whether
        // the focus phase ran out or the user hit Skip — `skip()` posts no
        // `.phaseDidComplete`, so the coordinator never runs `presentBreak` for
        // it and the island's announcement is the only thing that tells the user
        // the break began. Everything else this sink sees (a pause, a resume, a
        // Reset back to focus, a skip out of a break) is a write to `phase`
        // rather than an event, and `forPhaseChange` keeps it quiet. A break
        // that genuinely ends announces itself through `.phaseDidComplete`.
        if let last = lastPhase,
           let activity = NotchActivity.forPhaseChange(from: last, to: timer.phase) {
            announce(activity)
        }
        lastPhase = timer.phase
    }

    // MARK: - Hover (debounced)

    /// Called by the hosting view's tracking area on every pointer move.
    ///
    /// Two things happen, on two different clocks. The island acknowledges the
    /// pointer *immediately* — `model.pointerInside` drives a hairline on the
    /// silhouette, so the HUD is not dead for the 250ms of `hoverOpenDelay` and
    /// then suddenly enormous. Whether it actually *opens* still goes through the
    /// debounce below, unchanged: a pointer merely crossing the top of the screen
    /// lights the hairline for a few frames and nothing more.
    func pointerMoved(inside: Bool) {
        if model.pointerInside != inside { model.pointerInside = inside }
        hoverChanged(inside)
    }

    /// The debounce has to compare `inside` against the value that is *going*
    /// to be committed — the pending job's target if one is in flight, the
    /// committed value otherwise. Comparing against the committed value alone
    /// lets a pointer sweeping across the island leave the island stuck open:
    /// `mouseMoved(inside)` schedules the open job, `mouseExited` 100ms later
    /// sees `hovering == false, inside == false`, early-returns without
    /// cancelling, and the open job fires behind the pointer's back.
    func hoverChanged(_ inside: Bool) {
        let target = pendingHover ?? model.state.hovering
        guard target != inside else { return }

        hoverJob?.cancel()
        hoverJob = nil
        pendingHover = nil

        // The pending job was the only thing standing between us and `inside`;
        // cancelling it already got us there. Nothing left to schedule.
        guard model.state.hovering != inside else { return }

        pendingHover = inside
        let delay = inside ? NotchGeometry.hoverOpenDelay : NotchGeometry.hoverCloseDelay
        hoverJob = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.model.state.hovering = inside
            self.pendingHover = nil
            self.hoverJob = nil
        }
    }
}

/// Never key and never main: clicking the island must not take key status from
/// the frontmost app's window (`.nonactivatingPanel` only stops the *app* from
/// activating). SwiftUI/AppKit buttons still receive their clicks in a non-key
/// window — matches `FloatingMiniPanel`.
private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hit-testing is the safety-critical part: the panel spans ~356pt of the
/// menu-bar row at all times (and hangs ~290pt below it while the island is
/// open), and anything it swallows is a click the user loses. Only the
/// currently rendered island shape is hittable. The window's frame hugging the
/// state (`syncPanelFrame`) is the belt to this suspender: everywhere the
/// island *can't* be, there is no window to hit-test at all.
private final class NotchHostingView<Content: View>: NSHostingView<Content> {
    weak var model: NotchHUDModel?
    private var tracking: NSTrackingArea?

    /// `NotchGeometry` speaks panel coordinates: origin top-left, y grows down.
    /// `NSHostingView` overrides `isFlipped` to `true` on current SDKs, so a
    /// point already converted into our bounds is *already* top-left — flipping
    /// it again would mirror the mask onto the empty bottom of the panel. Handle
    /// both cases rather than assuming either.
    private func geometryPoint(_ local: CGPoint) -> CGPoint {
        isFlipped ? local : CGPoint(x: local.x, y: bounds.height - local.y)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let model else { return nil }
        let local = convert(point, from: superview)
        // `model.config` — the same value the view drew the island from. Masking
        // with anything else (the default, say) would keep swallowing clicks in
        // a strip of menu bar the user's ears setting has already given back.
        guard NotchGeometry.hitTest(geometryPoint(local), metrics: model.metrics,
                                    size: model.state.size,
                                    config: model.config) else { return nil }
        return super.hitTest(point)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard let model else { return }
        let local = convert(event.locationInWindow, from: nil)
        // Hovering the *island* opens it; hovering the expanded body keeps it open.
        let inside = NotchGeometry.hitTest(geometryPoint(local), metrics: model.metrics,
                                           size: model.state.size,
                                           config: model.config)
        NotchWindowManager.shared.pointerMoved(inside: inside)
    }

    override func mouseExited(with event: NSEvent) {
        NotchWindowManager.shared.pointerMoved(inside: false)
    }
}
