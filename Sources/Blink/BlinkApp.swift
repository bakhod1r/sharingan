import SwiftUI
import AppKit
import BlinkCore

/// Forces menu-bar-only behavior (no Dock icon) even when launched unbundled;
/// the bundled `.app` also declares `LSUIElement` in its Info.plist.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct BlinkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
                .onAppear {
                    coordinator.syncAlarm()
                    coordinator.installShortcuts()
                    coordinator.syncCamera()
                    coordinator.installCLIBridge()
                }
        } label: {
            Label {
                Text(menuBarText)
            } icon: {
                MenuBarLabelIcon()
            }
            .labelStyle(.titleAndIcon)
        }
        .menuBarExtraStyle(.window)

        Window("Blink", id: "main") {
            MainWindowView(timer: timer)
                .onAppear { NSApp.setActivationPolicy(.regular) }
                .onDisappear { NSApp.setActivationPolicy(.accessory) }
        }
        .defaultSize(width: 1040, height: 720)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView(timer: timer, settings: $timer.settings)
                .onChange(of: timer.settings.alarmSound) { _ in coordinator.syncAlarm() }
                .onChange(of: timer.settings.globalShortcutsEnabled) { _ in coordinator.installShortcuts() }
                .onChange(of: timer.settings.cameraEyeTrackingEnabled) { _ in coordinator.syncCamera() }
        }
    }

    /// Menu-bar title: just the time. The task name is intentionally omitted —
    /// long titles overflow the status item.
    private var menuBarText: String { statusText }

    private var statusText: String {
        let s = max(0, timer.remainingSeconds)
        return String(format: "%02d:%02d", Int(s) / 60, Int(s) % 60)
    }

}

/// Menu-bar glyph that swaps between the dark and light artwork the user
/// supplied so the eye stays visible on both light and dark menu bars.
private struct MenuBarLabelIcon: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: icon)
    }

    private var icon: NSImage {
        // Dark menu bar → light (white) eye; light menu bar → dark (black) eye.
        let name = colorScheme == .dark ? "menubar_dark" : "menubar_light"
        if let url = Bundle.module.url(forResource: "MenubarIcons/\(name)", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            let height: CGFloat = 15
            let aspect = img.size.width / max(img.size.height, 1)
            img.size = NSSize(width: height * aspect, height: height)
            return img
        }
        return NSImage(systemSymbolName: "eye.fill", accessibilityDescription: "Blink") ?? NSImage()
    }
}