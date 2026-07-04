import SwiftUI
import BlinkCore

@main
struct BlinkApp: App {
    @StateObject private var timer: PomodoroTimer
    @StateObject private var coordinator: BlinkCoordinator
    @State private var settingsOpen = false
    @Environment(\.colorScheme) private var colorScheme

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
                .onAppear {
                    coordinator.syncAlarm()
                    coordinator.installShortcuts()
                    coordinator.syncCamera()
                }
        } label: {
            Label {
                Text(statusText)
            } icon: {
                menubarIcon
            }
            .labelStyle(.titleAndIcon)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(timer: timer, settings: $timer.settings)
                .onChange(of: timer.settings.alarmSound) { _ in coordinator.syncAlarm() }
                .onChange(of: timer.settings.globalShortcutsEnabled) { _ in coordinator.installShortcuts() }
                .onChange(of: timer.settings.cameraEyeTrackingEnabled) { _ in coordinator.syncCamera() }
        }
    }

    private var statusText: String {
        let s = max(0, timer.remainingSeconds)
        return String(format: "%02d:%02d", Int(s) / 60, Int(s) % 60)
    }

    private var menubarIcon: Image {
        let theme = colorScheme == .dark ? "black" : "white"
        let scale = Int(NSScreen.main?.backingScaleFactor ?? 1) == 2 ? 32 : 16
        if let url = Bundle.module.url(forResource: "MenubarIcons/menubar_\(theme)_\(scale)", withExtension: "png"),
           let nsImage = NSImage(contentsOf: url) {
            nsImage.isTemplate = true
            return Image(nsImage: nsImage)
        }
        return Image(systemName: timer.phase.systemImage)
    }
}