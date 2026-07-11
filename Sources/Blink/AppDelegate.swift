import AppKit
import SwiftUI
import BlinkCore

/// AppKit-based menu bar controller — creates NSStatusItem directly,
/// works reliably without Xcode/xcbuild (unlike SwiftUI MenuBarExtra
/// which sometimes fails to register at runtime with CLI toolchain).
@MainActor
final class MenuBarController: NSObject {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    weak var timer: PomodoroTimer?
    weak var coordinator: BlinkCoordinator?

    /// The state the current button image was drawn for — the bitmap is
    /// re-rendered only when this changes (integer percent / phase / idle),
    /// not on every 1 s tick.
    private struct IconKey: Equatable {
        var percent: Int?
        var phase: PomodoroPhase
    }
    private var lastIconKey: IconKey?

    func install(timer: PomodoroTimer, coordinator: BlinkCoordinator) {
        self.timer = timer
        self.coordinator = coordinator

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Persist the item's menu-bar slot. On notched MacBooks a crowded menu
        // bar pushes the newest (leftmost) status item under the camera housing
        // where it renders invisible; with an autosave name the position can be
        // seeded/moved (defaults key "NSStatusItem Preferred Position
        // blink.menubar") and any manual ⌘-drag by the user sticks.
        item.autosaveName = "blink.menubar"
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        let hosting = NSHostingController(rootView: MenuBarView(timer: timer))
        // Let the popover size itself to the SwiftUI content's natural height
        // (the view fixes its own 360pt width). A hard-coded 720 was clipping the
        // content and making sections overlap.
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        self.popover = popover

        if let button = item.button {
            button.imagePosition = .imageLeading
            button.action = #selector(togglePopover)
            button.target = self
        }
        updateTitle() // seeds both the title and the initial icon

        // Sync coordinator services now that the menu bar is live.
        coordinator.syncAlarm()
        coordinator.installShortcuts()
        coordinator.syncCamera()
        // Restore the desktop today-panel if the user left it enabled (the
        // coordinator's initial syncAll ran before its controller was wired).
        coordinator.syncTodayPanel()
        coordinator.installCLIBridge()

        // Refresh title every second.
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateTitle() }
        }
    }

    private func updateTitle() {
        guard let timer, let button = statusItem?.button else { return }
        // Todoist-style minimal menu bar: just the stopwatch icon at rest, and
        // the icon + countdown only while a session is actually engaged
        // (running or paused mid-way). A fresh/reset timer shows the icon alone.
        let s = max(0, timer.remainingSeconds)
        let engaged = timer.isRunning
            || (timer.remainingSeconds > 0 && timer.remainingSeconds < timer.totalSeconds)
        let show = engaged && timer.settings.showMenuBarCountdown
        button.title = show ? String(format: " %02d:%02d", Int(s) / 60, Int(s) % 60) : ""

        // Progress ring around the iris while a session is engaged.
        let key = IconKey(percent: engaged ? Int(timer.progress * 100) : nil,
                          phase: timer.phase)
        if key != lastIconKey {
            lastIconKey = key
            button.image = Self.menuBarIcon(
                progress: key.percent.map { Double($0) / 100 },
                phase: key.phase)
        }
    }

    /// The menu-bar icon: the app's own red Sharingan iris, kept in colour
    /// (not a template) so its identity carries into the menu bar. Drawn with
    /// CoreGraphics directly — SwiftUI's ImageRenderer produced a fully
    /// transparent bitmap when invoked during applicationDidFinishLaunching in
    /// the bundled accessory app, leaving the status item invisible (an empty
    /// clickable gap in the menu bar). Falls back to a template stopwatch glyph.
    ///
    /// With `progress` set (an engaged session) the iris shrinks and a thin
    /// ring draws around it: a dim full-circle track plus a bright elapsed arc
    /// sweeping clockwise from 12 o'clock — red-orange in focus, green on
    /// breaks, dimmed while paused.
    @MainActor
    private static func menuBarIcon(progress: Double? = nil,
                                    phase: PomodoroPhase = .focus) -> NSImage? {
        let side: CGFloat = 18
        let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { fullRect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let c = CGPoint(x: fullRect.midX, y: fullRect.midY)

            var rect = fullRect
            if let progress {
                let ringWidth: CGFloat = 1.6
                // Track: full dim circle, legible on light and dark menu bars.
                ctx.setStrokeColor(CGColor(gray: 0.55, alpha: 0.35))
                ctx.setLineWidth(ringWidth)
                ctx.strokeEllipse(in: fullRect.insetBy(dx: ringWidth / 2, dy: ringWidth / 2))

                // Elapsed arc, 12 o'clock clockwise (y-up coords: angles
                // decrease going visually clockwise).
                let clamped = max(0, min(1, progress))
                if clamped > 0.01 {
                    let arcColor: CGColor
                    switch phase {
                    case .focus:
                        arcColor = CGColor(red: 1.0, green: 0.38, blue: 0.22, alpha: 1)
                    case .shortBreak, .longBreak:
                        arcColor = CGColor(red: 0.30, green: 0.85, blue: 0.45, alpha: 1)
                    case .paused:
                        arcColor = CGColor(gray: 0.9, alpha: 0.5)
                    }
                    ctx.setStrokeColor(arcColor)
                    ctx.setLineWidth(ringWidth)
                    ctx.setLineCap(.round)
                    let start = CGFloat.pi / 2
                    ctx.addArc(center: c, radius: fullRect.width / 2 - ringWidth / 2,
                               startAngle: start,
                               endAngle: start - clamped * 2 * .pi,
                               clockwise: true)
                    ctx.strokePath()
                }
                // Iris sits inside the ring with a small gap.
                rect = fullRect.insetBy(dx: 3.2, dy: 3.2)
            }
            let r = rect.width / 2

            // Iris: bright-centre red radial gradient (brighter than the
            // full-size artwork so it stays legible at 18 pt on dark menu bars).
            let stops: [(CGFloat, CGColor)] = [
                (0.00, CGColor(red: 0.85, green: 0.10, blue: 0.10, alpha: 1)),
                (0.55, CGColor(red: 0.78, green: 0.08, blue: 0.08, alpha: 1)),
                (0.85, CGColor(red: 0.58, green: 0.03, blue: 0.03, alpha: 1)),
                (1.00, CGColor(red: 0.38, green: 0.01, blue: 0.02, alpha: 1)),
            ]
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: stops.map(\.1) as CFArray,
                locations: stops.map(\.0)
            ) {
                ctx.saveGState()
                ctx.addEllipse(in: rect)
                ctx.clip()
                ctx.drawRadialGradient(
                    gradient,
                    startCenter: c, startRadius: 0,
                    endCenter: c, endRadius: r,
                    options: []
                )
                ctx.restoreGState()
            }

            // Dark rim so the disc separates from light menu bars.
            ctx.setStrokeColor(CGColor(red: 0.10, green: 0, blue: 0, alpha: 0.9))
            ctx.setLineWidth(0.8)
            ctx.strokeEllipse(in: rect.insetBy(dx: 0.4, dy: 0.4))

            // Pupil + three tomoe dots on the classic ring.
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            let pupilR = 0.16 * r
            ctx.fillEllipse(in: CGRect(x: c.x - pupilR, y: c.y - pupilR, width: pupilR * 2, height: pupilR * 2))
            let ringR = 0.52 * r
            let tomoeR = 0.17 * r
            for i in 0..<3 {
                let a = (-80.0 + Double(i) * 120.0) * .pi / 180.0
                let p = CGPoint(x: c.x + ringR * cos(a), y: c.y + ringR * sin(a))
                ctx.fillEllipse(in: CGRect(x: p.x - tomoeR, y: p.y - tomoeR, width: tomoeR * 2, height: tomoeR * 2))
            }
            return true
        }
        img.isTemplate = false
        if img.size.width > 0 { return img }
        return NSImage(systemSymbolName: "stopwatch", accessibilityDescription: "Sharingan")
    }

    /// Opens the popover if it isn't already visible. Used on launch/reopen so
    /// starting a menu-bar-only app gives visible feedback instead of nothing.
    func showPopover() {
        guard let popover, let button = statusItem?.button, !popover.isShown else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var timer: PomodoroTimer?
    var coordinator: BlinkCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Blink's entire UI is a dark-glass design: every surface hardcodes white
        // text and `Color.white.opacity(...)` chrome over dark gradients and
        // `.regularMaterial`. Under the system Light appearance the popover and
        // stats tab render that white-on-light (invisible), while the main
        // window's forced-dark gradient turns semantic `.primary` labels
        // black-on-dark. Pin the whole app to dark so every surface — popover,
        // windows, materials, semantic colors — resolves consistently. The
        // menu-bar icon is a template image and still tints to the real menu bar.
        NSApp.appearance = NSAppearance(named: .darkAqua)

        let timer = PomodoroTimer()
        let coord = BlinkCoordinator(timer: timer)
        coord.breakPresenter = BreakWindowManager.shared
        coord.floatingController = FloatingWindowManager.shared
        coord.todayPanelController = TodayPanelWindowManager.shared
        coord.quickAddController = QuickAddWindowManager.shared
        self.timer = timer
        self.coordinator = coord
        // Views reach shared services (focus queue) through this; the
        // "What's next?" panel follows coordinator.needsTaskPick on its own.
        AppServices.coordinator = coord
        TaskPickWindowManager.shared.install(coordinator: coord)

        // Feed the AppKit-managed main window its SwiftUI content, otherwise
        // MainWindowManager.show() (used by the popover's "Open window" button
        // and the settings gear) bails at its `guard let content` and nothing
        // appears. This wiring was lost in the AppKit restructure.
        MainWindowManager.shared.content = { AnyView(MainWindowView(timer: timer)) }

        MenuBarController.shared.install(timer: timer, coordinator: coord)

        // Without this, notify()/schedule() silently no-op on a fresh install:
        // UNUserNotificationCenter.add fails while status is .notDetermined.
        Task { await NotificationService.shared.requestAuthorization() }

        // Eyes wallpaper: restore on launch if the user left it enabled.
        if timer.settings.eyesWallpaperEnabled {
            WallpaperWindowManager.shared.setEnabled(true, config: WallpaperConfig(from: timer.settings))
        }

        // A menu-bar-only app (LSUIElement) shows no window and no Dock icon,
        // so double-clicking Sharingan in Finder looks like "nothing happened".
        // Open the main window on launch so the user lands in the full app.
        DispatchQueue.main.async {
            MainWindowManager.shared.show()
        }
    }

    // sharingan:// URL scheme (Shortcuts/Raycast/browser automation). AppKit
    // installs the kAEGetURL Apple-event handler for us because the delegate
    // implements application(_:open:) — CFBundleURLTypes in Info.plist makes
    // LaunchServices route the scheme here (bundle builds via make-app.sh).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let command = URLCommandRouter.parse(url) else { continue }
            switch command {
            case .show:
                MainWindowManager.shared.show()
            default:
                coordinator?.handle(command)
            }
        }
    }

    // Finder/Launchpad re-launch of an already-running accessory app fires
    // reopen — surface the main window instead of silently doing nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowManager.shared.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Best-effort: never leave the user's Focus stuck on after quit.
        if let timer {
            DNDShortcutService.shared.deactivate(settings: timer.settings)
        }
    }
}