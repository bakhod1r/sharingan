import Testing
import Foundation
@testable import BlinkCore

@Suite("Today panel")
struct TodayPanelTests {

    // MARK: - Settings flag

    @Test("showTodayPanel defaults to off")
    func defaultIsOff() {
        #expect(PomodoroSettings().showTodayPanel == false)
    }

    @Test("showTodayPanel survives a codable round trip")
    func codableRoundTrip() throws {
        var s = PomodoroSettings()
        s.showTodayPanel = true
        let decoded = try JSONDecoder().decode(PomodoroSettings.self,
                                               from: JSONEncoder().encode(s))
        #expect(decoded.showTodayPanel == true)
        #expect(decoded == s)
    }

    @Test("old settings blob without the key decodes to the default")
    func defensiveDecode() throws {
        let decoded = try JSONDecoder().decode(PomodoroSettings.self,
                                               from: Data("{}".utf8))
        #expect(decoded.showTodayPanel == false)
    }

    // MARK: - Coordinator sync

    /// Records show/hide calls so the sync logic is assertable headless.
    @MainActor
    private final class SpyPanelController: TodayPanelController {
        var shown = 0
        var hidden = 0
        func showTodayPanel(timer: PomodoroTimer) { shown += 1 }
        func hideTodayPanel() { hidden += 1 }
    }

    @MainActor
    @Test("syncTodayPanel follows the settings flag, not the running state")
    func syncFollowsFlag() {
        let name = "blink-todaypanel-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let coordinator = BlinkCoordinator(timer: PomodoroTimer(),
                                           focusQueue: FocusQueue(defaults: defaults))
        let spy = SpyPanelController()
        coordinator.todayPanelController = spy

        // Flag off (the default) → hidden, even though nothing is running.
        coordinator.syncTodayPanel()
        #expect(spy.shown == 0)
        #expect(spy.hidden == 1)

        // Flag on → shown regardless of the timer's running state.
        coordinator.timer.settings.showTodayPanel = true
        coordinator.syncTodayPanel()
        #expect(spy.shown == 1)
        #expect(spy.hidden == 1)

        // Back off → hidden again.
        coordinator.timer.settings.showTodayPanel = false
        coordinator.syncTodayPanel()
        #expect(spy.shown == 1)
        #expect(spy.hidden == 2)
    }
}
