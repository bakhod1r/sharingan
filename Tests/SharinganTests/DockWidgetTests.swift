import Testing
import Foundation
@testable import SharinganCore

@Suite("Dock widget")
struct DockWidgetTests {

    // MARK: - Settings flag

    @Test("dockWidgetEnabled defaults to on")
    func defaultIsOn() {
        #expect(PomodoroSettings().dockWidgetEnabled == true)
    }

    @Test("dockWidgetEnabled survives a codable round trip")
    func codableRoundTrip() throws {
        var s = PomodoroSettings()
        s.dockWidgetEnabled = false
        let decoded = try JSONDecoder().decode(PomodoroSettings.self,
                                               from: JSONEncoder().encode(s))
        #expect(decoded.dockWidgetEnabled == false)
        #expect(decoded == s)
    }

    @Test("old settings blob without the key decodes to the default")
    func defensiveDecode() throws {
        let decoded = try JSONDecoder().decode(PomodoroSettings.self,
                                               from: Data("{}".utf8))
        #expect(decoded.dockWidgetEnabled == true)
    }

    // MARK: - Size / alignment / opacity / hover-expand

    @Test("new dock widget fields default to today's look")
    func newFieldDefaults() {
        let s = PomodoroSettings()
        #expect(s.dockWidgetSize == .medium)
        #expect(s.dockWidgetAlignment == .trailing)
        #expect(s.dockWidgetOpacity == 1.0)
        #expect(s.dockWidgetExpandOnHover == true)
    }

    @Test("DockWidgetSize preset pixel mapping is sane and strictly ordered")
    func presetPixelsSane() {
        for size in DockWidgetSize.allCases {
            #expect(size.width > 0)
            #expect(size.height > 0)
        }
        #expect(DockWidgetSize.small.width < DockWidgetSize.medium.width)
        #expect(DockWidgetSize.medium.width < DockWidgetSize.large.width)
        #expect(DockWidgetSize.small.height < DockWidgetSize.medium.height)
        #expect(DockWidgetSize.medium.height < DockWidgetSize.large.height)
    }

    @Test("new dock widget fields survive a settings codable round trip")
    func newFieldsRoundTrip() throws {
        var s = PomodoroSettings()
        s.dockWidgetSize = .large
        s.dockWidgetAlignment = .leading
        s.dockWidgetOpacity = 0.5
        s.dockWidgetExpandOnHover = false
        let decoded = try JSONDecoder().decode(PomodoroSettings.self,
                                               from: JSONEncoder().encode(s))
        #expect(decoded.dockWidgetSize == .large)
        #expect(decoded.dockWidgetAlignment == .leading)
        #expect(decoded.dockWidgetOpacity == 0.5)
        #expect(decoded.dockWidgetExpandOnHover == false)
        #expect(decoded == s)
    }

    @Test("old settings blob without the new keys decodes to the defaults")
    func newFieldsDefensiveDecode() throws {
        let decoded = try JSONDecoder().decode(PomodoroSettings.self,
                                               from: Data("{}".utf8))
        #expect(decoded.dockWidgetSize == .medium)
        #expect(decoded.dockWidgetAlignment == .trailing)
        #expect(decoded.dockWidgetOpacity == 1.0)
        #expect(decoded.dockWidgetExpandOnHover == true)
    }

    @Test("garbage dockWidgetSize/dockWidgetAlignment raw values fall back to the defaults")
    func garbageEnumsFallBack() throws {
        let decoded = try JSONDecoder().decode(
            PomodoroSettings.self,
            from: Data(#"{"dockWidgetSize":"gigantic","dockWidgetAlignment":"top"}"#.utf8))
        #expect(decoded.dockWidgetSize == .medium)
        #expect(decoded.dockWidgetAlignment == .trailing)
    }

    // MARK: - Coordinator sync

    /// Records show/hide calls so the sync logic is assertable headless.
    @MainActor
    private final class SpyDockWidget: DockWidgetController {
        var shown = 0
        var hidden = 0
        func showDockWidget(timer: PomodoroTimer) { shown += 1 }
        func hideDockWidget() { hidden += 1 }
    }

    @MainActor
    @Test("syncDockWidget follows the settings flag, not the running state")
    func syncFollowsFlag() {
        let name = "blink-dockwidget-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let coordinator = SharinganCoordinator(timer: PomodoroTimer(),
                                           focusQueue: FocusQueue(defaults: defaults))
        let spy = SpyDockWidget()
        coordinator.dockWidgetController = spy

        // Flag on (the default) → shown, even though nothing is running.
        coordinator.timer.settings.dockWidgetEnabled = true
        coordinator.syncDockWidget()
        #expect(spy.shown == 1)
        #expect(spy.hidden == 0)

        // Flag off → hidden regardless of the timer's running state.
        coordinator.timer.settings.dockWidgetEnabled = false
        coordinator.syncDockWidget()
        #expect(spy.shown == 1)
        #expect(spy.hidden == 1)
    }

    // MARK: - Placement geometry

    @Test("dock side detection: bottom, left, right, auto-hidden")
    func sideDetection() {
        let full = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        #expect(DockWidgetGeometry.side(visibleFrame: CGRect(x: 0, y: 70, width: 1600, height: 905), fullFrame: full) == .bottom)
        #expect(DockWidgetGeometry.side(visibleFrame: CGRect(x: 74, y: 0, width: 1526, height: 975), fullFrame: full) == .left)
        #expect(DockWidgetGeometry.side(visibleFrame: CGRect(x: 0, y: 0, width: 1526, height: 975), fullFrame: full) == .right)
        // Auto-hidden Dock: only the menu bar differs → bottom rules.
        #expect(DockWidgetGeometry.side(visibleFrame: CGRect(x: 0, y: 0, width: 1600, height: 975), fullFrame: full) == .bottom)
    }

    @Test("vertical docks center the pill instead of parking it in the corner")
    func verticalDockCenters() {
        let full = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let vis = CGRect(x: 74, y: 0, width: 1526, height: 975)
        let size = CGSize(width: 320, height: 56)
        let o = DockWidgetGeometry.origin(size: size, alignment: .trailing,
                                          visibleFrame: vis, fullFrame: full)
        #expect(o.x == vis.minX + 8)
        #expect(o.y == vis.midY - size.height / 2)
    }

    @Test("bottom dock honors the Position setting")
    func bottomDockAlignment() {
        let full = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let vis = CGRect(x: 0, y: 70, width: 1600, height: 905)
        let size = CGSize(width: 320, height: 56)
        for a in DockWidgetAlignment.allCases {
            let o = DockWidgetGeometry.origin(size: size, alignment: a,
                                              visibleFrame: vis, fullFrame: full)
            #expect(o.y == vis.minY + 4)
            switch a {
            case .leading:  #expect(o.x == vis.minX + 16)
            case .center:   #expect(o.x == vis.midX - size.width / 2)
            case .trailing: #expect(o.x == vis.maxX - size.width - 16)
            }
        }
    }

    @Test("hover expansion opens away from a vertical dock")
    func expandAnchorFollowsDock() {
        let full = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let left = CGRect(x: 74, y: 0, width: 1526, height: 975)
        let right = CGRect(x: 0, y: 0, width: 1526, height: 975)
        let bottom = CGRect(x: 0, y: 70, width: 1600, height: 905)
        #expect(DockWidgetGeometry.expandAnchor(alignment: .center, visibleFrame: left, fullFrame: full) == .leading)
        #expect(DockWidgetGeometry.expandAnchor(alignment: .center, visibleFrame: right, fullFrame: full) == .trailing)
        #expect(DockWidgetGeometry.expandAnchor(alignment: .center, visibleFrame: bottom, fullFrame: full) == .center)
    }

    // MARK: - Start → mini task picker decision

    @Test("paused always resumes immediately, even with tasks today")
    func pausedResumesImmediately() {
        #expect(DockWidgetStartAction.decide(isPaused: true, todayTaskCount: 3) == .startImmediately)
        #expect(DockWidgetStartAction.decide(isPaused: true, todayTaskCount: 0) == .startImmediately)
    }

    @Test("idle with an empty today list starts immediately (no empty picker)")
    func emptyTodayStartsImmediately() {
        #expect(DockWidgetStartAction.decide(isPaused: false, todayTaskCount: 0) == .startImmediately)
    }

    @Test("idle with today tasks shows the picker")
    func nonEmptyTodayShowsPicker() {
        #expect(DockWidgetStartAction.decide(isPaused: false, todayTaskCount: 1) == .showPicker)
        #expect(DockWidgetStartAction.decide(isPaused: false, todayTaskCount: 5) == .showPicker)
    }

    // MARK: - Draggable pill: custom-position clamp + hover anchor

    @Test("clamp keeps a dragged-in custom origin inside the visible frame")
    func clampKeepsCustomOriginOnScreen() {
        let vis = CGRect(x: 0, y: 70, width: 1600, height: 905)
        let size = CGSize(width: 320, height: 56)

        // Dragged off-screen to the bottom-left → pinned to the near edges.
        let low = DockWidgetGeometry.clamp(origin: CGPoint(x: -200, y: -50),
                                           size: size, visibleFrame: vis)
        #expect(low.x == vis.minX)
        #expect(low.y == vis.minY)

        // Dragged off-screen to the top-right → pinned to the far edges.
        let high = DockWidgetGeometry.clamp(origin: CGPoint(x: 3000, y: 3000),
                                            size: size, visibleFrame: vis)
        #expect(high.x == vis.maxX - size.width)
        #expect(high.y == vis.maxY - size.height)

        // Already inside → unchanged.
        let inside = CGPoint(x: 100, y: 200)
        #expect(DockWidgetGeometry.clamp(origin: inside, size: size, visibleFrame: vis) == inside)
    }

    @Test("custom-position hover anchor follows which screen half the pill sits in")
    func customExpandAnchorFollowsScreenHalf() {
        let vis = CGRect(x: 0, y: 70, width: 1600, height: 905)
        let size = CGSize(width: 320, height: 56)

        // Pill's midX left of the screen's midX → opens rightward.
        #expect(DockWidgetGeometry.expandAnchor(customOrigin: CGPoint(x: 0, y: 100),
                                                 size: size, visibleFrame: vis) == .leading)
        // Exactly at the midpoint → leading (boundary is inclusive, per spec).
        let atMid = CGPoint(x: vis.midX - size.width / 2, y: 100)
        #expect(DockWidgetGeometry.expandAnchor(customOrigin: atMid,
                                                 size: size, visibleFrame: vis) == .leading)
        // Pill's midX right of the screen's midX → opens leftward.
        #expect(DockWidgetGeometry.expandAnchor(customOrigin: CGPoint(x: 1200, y: 100),
                                                 size: size, visibleFrame: vis) == .trailing)
    }
}
