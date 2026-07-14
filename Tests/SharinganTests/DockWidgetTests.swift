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
}
