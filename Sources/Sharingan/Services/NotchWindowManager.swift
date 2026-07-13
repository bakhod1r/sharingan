import AppKit
import SwiftUI
import Combine
import SharinganCore

/// The notch HUD's window. One `NSPanel` on one screen, sized to the union of
/// every island state and pinned to the top center. It is *above* the menu bar,
/// so the content view's `hitTest` must return nil everywhere the island isn't
/// drawn — otherwise the top of the screen stops accepting clicks.
@MainActor
final class NotchWindowManager {
    static let shared = NotchWindowManager()

    private var panel: NSPanel?
    private var screenObserver: NSObjectProtocol?
    private var cancellables: Set<AnyCancellable> = []
    private var activityJob: Task<Void, Never>?
    private var hoverJob: Task<Void, Never>?

    private weak var timer: PomodoroTimer?
    /// Last settings we reacted to, so a settings edit re-places the panel while
    /// a plain countdown tick does not.
    private var appliedSettings: (enabled: Bool, ears: NotchEarsMode, activity: Bool)?
    let model = NotchHUDModel()

    func install(timer: PomodoroTimer, coordinator: SharinganCoordinator) {
        self.timer = timer

        // Track the timer so the ears and progress bar follow it.
        timer.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self, weak timer] _ in
                guard let self, let timer else { return }
                self.syncTimer(timer)
                self.refreshIfSettingsChanged(timer.settings)
            }
            .store(in: &cancellables)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { NotchWindowManager.shared.refresh() }
        }

        syncTimer(timer)
        refresh()
    }

    /// Re-reads settings and screens: shows, hides or re-places the panel.
    func refresh() {
        guard let timer else { return }
        let settings = timer.settings
        appliedSettings = (settings.notchHUDEnabled, settings.notchEars,
                           settings.notchLiveActivity)
        model.state.enabled = settings.notchHUDEnabled
        model.state.liveActivityEnabled = settings.notchLiveActivity
        model.earsMode = settings.notchEars

        guard settings.notchHUDEnabled, let screen = Self.hudScreen() else {
            teardown()
            return
        }
        model.metrics = Self.metrics(for: screen)
        place(on: screen)
    }

    /// The timer publishes on every tick; only a *settings* edit needs the panel
    /// rebuilt, so filter the firehose down to the three keys we care about.
    private func refreshIfSettingsChanged(_ settings: PomodoroSettings) {
        let now = (settings.notchHUDEnabled, settings.notchEars, settings.notchLiveActivity)
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
    func setBreakOverlay(_ up: Bool) {
        model.state.breakOverlayUp = up
    }

    // MARK: - Screen

    /// The one screen the HUD lives on: the notched one if there is one, else
    /// the menu-bar screen. External displays never get it.
    static func hudScreen() -> NSScreen? {
        if let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notched
        }
        return NSScreen.screens.first
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
            notchHeight: notchHeight,
            isBuiltIn: notchHeight > 0)
    }

    // MARK: - Panel

    private func place(on screen: NSScreen) {
        let size = NotchGeometry.panelSize(model.metrics)
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,   // top-anchored (AppKit y-up)
            width: size.width, height: size.height)

        if let panel {
            panel.setFrame(frame, display: true)
            return
        }

        let panel = NotchPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                    .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.ignoresMouseEvents = false
        panel.isFloatingPanel = true
        // Above the menu bar — the whole point is to draw on the notch, which
        // the menu bar owns.
        panel.level = NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)

        guard let timer else { return }
        let host = NotchHostingView(
            rootView: NotchHUDView(model: model, timer: timer)
                .environmentObject(timer))
        host.model = model
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        self.panel = panel
        panel.orderFrontRegardless()
    }

    private func teardown() {
        hoverJob?.cancel()
        activityJob?.cancel()
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
    }

    // MARK: - Hover (debounced)

    /// Called by the hosting view's tracking area.
    func hoverChanged(_ inside: Bool) {
        guard model.state.hovering != inside else { return }
        hoverJob?.cancel()
        let delay = inside ? NotchGeometry.hoverOpenDelay : NotchGeometry.hoverCloseDelay
        hoverJob = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.model.state.hovering = inside
        }
    }
}

/// Never main, so the HUD does not become the app's main window. It *can* become
/// key (a `.nonactivatingPanel` takes key without activating the app) because the
/// expanded panel's buttons need clicks — see the report's note on this.
private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hit-testing is the safety-critical part: the panel covers ~356×260 at the top
/// of the screen, and anything it swallows is a menu-bar click the user loses.
/// Only the currently rendered island shape is hittable.
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
        guard NotchGeometry.hitTest(geometryPoint(local), metrics: model.metrics,
                                    size: model.state.size) else { return nil }
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
                                           size: model.state.size)
        NotchWindowManager.shared.hoverChanged(inside)
    }

    override func mouseExited(with event: NSEvent) {
        NotchWindowManager.shared.hoverChanged(false)
    }
}
