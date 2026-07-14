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
