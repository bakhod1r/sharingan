import SwiftUI
import BlinkCore

@main
struct BlinkApp: App {
    @StateObject private var timer: PomodoroTimer
    @StateObject private var coordinator: BlinkCoordinator
    @State private var settingsOpen = false

    init() {
        let timer = PomodoroTimer()
        _timer = StateObject(wrappedValue: timer)
        let coord = BlinkCoordinator(timer: timer)
        coord.breakPresenter = BreakWindowManager.shared
        coord.floatingController = FloatingWindowManager.shared
        _coordinator = StateObject(wrappedValue: coord)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(timer: timer)
        } label: {
            Label {
                Text(statusText)
            } icon: {
                Image(systemName: timer.phase.systemImage)
            }
            .labelStyle(.titleAndIcon)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(timer: timer, settings: $timer.settings)
        }
    }

    private var statusText: String {
        let s = max(0, timer.remainingSeconds)
        return String(format: "%02d:%02d", Int(s) / 60, Int(s) % 60)
    }
}