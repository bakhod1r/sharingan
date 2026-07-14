import AppKit
import SwiftUI
import SharinganCore

/// AppKit-based menu bar controller — creates NSStatusItem directly,
/// works reliably without Xcode/xcbuild (unlike SwiftUI MenuBarExtra
/// which sometimes fails to register at runtime with CLI toolchain).
@MainActor
final class MenuBarController: NSObject {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    weak var timer: PomodoroTimer?
    weak var coordinator: SharinganCoordinator?

    /// The state the current button image was drawn for — the bitmap is
    /// re-rendered only when this changes (integer percent / phase / idle),
    /// not on every 1 s tick.
    private struct IconKey: Equatable {
        var percent: Int?
        var phase: PomodoroPhase
        var rotationStep: Int
        var style: SharinganStyle
    }
    private var lastIconKey: IconKey?
    private let spinner = IconSpinner()
    private var dockAnimator: DockIconAnimator?

    /// The status item's autosave name and the defaults key macOS stores its
    /// menu-bar slot under. `rescueFromNotchIfHidden` seeds the key directly.
    private static let autosaveName = "sharingan.menubar"
    private static let positionKey = "NSStatusItem Preferred Position \(autosaveName)"

    func install(timer: PomodoroTimer, coordinator: SharinganCoordinator) {
        self.timer = timer
        self.coordinator = coordinator

        makeStatusItem()

        let popover = NSPopover()
        popover.behavior = .transient
        // NSPopover resolves its appearance from the view it's anchored to —
        // the status-item button in the system menu bar — NOT from
        // NSApp.appearance. Under system Light mode that renders the popover
        // chrome light while the content's dark-glass design hardcodes white
        // text (unreadable). Pin the popover itself to dark like the rest of
        // the app (see applicationDidFinishLaunching).
        popover.appearance = NSAppearance(named: .darkAqua)
        let hosting = NSHostingController(rootView: MenuBarView(timer: timer))
        // Let the popover size itself to the SwiftUI content's natural height
        // (the view fixes its own 360pt width). A hard-coded 720 was clipping the
        // content and making sections overlap.
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        self.popover = popover

        dockAnimator = DockIconAnimator()
        spinner.onFrame = { [weak self] angle, spinning in
            self?.updateTitle()
            self?.dockAnimator?.apply(angle: angle, spinning: spinning)
        }
        syncSpinner()

        // Sync coordinator services now that the menu bar is live.
        coordinator.syncAlarm()
        coordinator.installShortcuts()
        coordinator.syncCamera()
        // Restore the desktop today-panel if the user left it enabled (the
        // coordinator's initial syncAll ran before its controller was wired).
        coordinator.syncTodayPanel()
        // Same launch-order gap for the Floating widget: without this re-sync
        // the pill never appears on a fresh launch.
        coordinator.syncFloatingWidget()
        coordinator.installCLIBridge()

        // Refresh title every second.
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncSpinner()
                self?.syncVisibility()
                self?.updateTitle()
            }
        }

        // The button's window has a real menu-bar frame only after this
        // run-loop turn settles; check for the invisible-slot state then.
        // Also re-render the icon once: a styled (non-classic) iris rendered
        // during applicationDidFinishLaunching can come out as an empty
        // bitmap (the ImageRenderer quirk `menuBarIcon` documents), so one
        // settled re-render repairs the first frame.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.rescueFromNotchIfHidden()
            self?.lastIconKey = nil
            self?.updateTitle()
        }
    }

    /// Creates (or re-creates) the status item and wires its button. Split out
    /// of `install` so `rescueFromNotchIfHidden` can rebuild the item after
    /// re-seeding its menu-bar slot — macOS reads the slot at creation time.
    private func makeStatusItem() {
        if let old = statusItem { NSStatusBar.system.removeStatusItem(old) }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Persist the item's menu-bar slot. On notched MacBooks a crowded menu
        // bar pushes the newest (leftmost) status item under the camera housing
        // where it renders invisible; with an autosave name the position can be
        // seeded/moved (defaults key `Self.positionKey`) and any manual ⌘-drag
        // by the user sticks.
        item.autosaveName = Self.autosaveName
        if let button = item.button {
            button.imagePosition = .imageLeading
            button.action = #selector(togglePopover)
            button.target = self
        }
        statusItem = item
        lastIconKey = nil // fresh button — force the next icon render
        syncVisibility()
        updateTitle() // seeds both the title and the initial icon
    }

    /// Applies the "Show menu bar icon" setting. Turning it on also clears a
    /// stale `NSStatusItem Visible … = false` that macOS persists when the icon
    /// is ⌘-dragged off the bar — one of the two ways the icon silently
    /// disappears for good (the other is `rescueFromNotchIfHidden`).
    private func syncVisibility() {
        guard let item = statusItem else { return }
        let wanted = timer?.settings.showMenuBarIcon ?? true
        guard item.isVisible != wanted else { return }
        item.isVisible = wanted
        if wanted {
            // Re-shown items reappear in their stored slot, which may itself
            // be the hidden one — give AppKit a beat to place the window.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.rescueFromNotchIfHidden()
            }
        }
    }

    /// One-shot repair for the icon sitting in an invisible menu-bar slot on a
    /// notched MacBook. The rebrand renamed the item's autosaveName; Macs that
    /// launched a build before the defaults migration existed persisted a fresh
    /// leftmost slot, which a crowded menu bar parks under the camera housing.
    /// The migration can't heal those (the new key already exists), so detect
    /// the parked state at runtime: if the button's window overlaps the
    /// housing, re-seed the slot next to the system items — the rightmost spot
    /// third-party items can occupy, visible on every Mac — and rebuild the
    /// item so the bar reads the seeded position.
    private func rescueFromNotchIfHidden() {
        guard let item = statusItem, item.isVisible,
              let window = item.button?.window,
              let screen = window.screen,
              screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return }
        let housing = NSRect(x: left.maxX, y: left.minY,
                             width: right.minX - left.maxX,
                             height: max(left.height, right.height))
        guard window.frame.intersects(housing) else { return }
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
        // Distance from the screen's right edge — small means far right.
        UserDefaults.standard.set(6.0, forKey: Self.positionKey)
        makeStatusItem()
    }

    /// Pushes the settings switch into the spinner (1 s latency at most).
    private func syncSpinner() {
        spinner.enabled = timer?.settings.animateIcon ?? false
    }

    private func updateTitle() {
        guard let timer, let button = statusItem?.button else { return }
        // Keep the Dock artwork on the user's Sharingan style (no-op unless
        // the style actually changed).
        dockAnimator?.syncStyle(timer.settings.sharinganStyle)
        // Todoist-style minimal menu bar: just the stopwatch icon at rest, and
        // the icon + countdown only while a session is actually engaged
        // (running or paused mid-way). A fresh/reset timer shows the icon alone.
        let s = max(0, timer.remainingSeconds)
        let engaged = timer.isRunning
            || (timer.remainingSeconds > 0 && timer.remainingSeconds < timer.totalSeconds)
        let show = engaged && timer.settings.showMenuBarCountdown
        let title = show ? String(format: " %02d:%02d", Int(s) / 60, Int(s) % 60) : ""
        if button.title != title { button.title = title }

        // Progress ring around the iris while a session is engaged; the
        // rotation step quantises the spinner angle to the 5° frame grid
        // within the mark's 120° symmetry, so the bitmap is re-rendered
        // only when something visible changed.
        // The classic mark repeats every 120° (three tomoe); other styles
        // aren't 3-fold symmetric, so their frames only repeat per full turn.
        let style = timer.settings.sharinganStyle
        let symmetry: Double = style == .classic ? 120 : 360
        let key = IconKey(percent: engaged ? Int(timer.progress * 100) : nil,
                          phase: timer.phase,
                          rotationStep: Int(spinner.angle.truncatingRemainder(dividingBy: symmetry) / 5),
                          style: style)
        if key != lastIconKey {
            lastIconKey = key
            button.image = Self.menuBarIcon(
                progress: key.percent.map { Double($0) / 100 },
                phase: key.phase,
                rotationDegrees: spinner.angle,
                style: key.style)
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
    ///
    /// `rotationDegrees` spins the tomoe (clockwise) — the animated menu bar.
    ///
    /// `style` follows the user's Sharingan-eye pick: `.classic` keeps this
    /// hand-drawn CG mark (safe to render during launch), every other style
    /// rasterizes the same `MoveIrisView` the eyes/wallpaper/app icon use and
    /// composites it inside the CG ring — with the CG classic mark as the
    /// fallback if the rasterizer returns nothing.
    @MainActor
    static func menuBarIcon(progress: Double? = nil,
                            phase: PomodoroPhase = .focus,
                            rotationDegrees: Double = 0,
                            style: SharinganStyle = .classic) -> NSImage? {
        let side: CGFloat = 18
        // Rasterize the styled iris up front (not inside the NSImage drawing
        // closure — ImageRenderer is main-actor and the closure draws lazily).
        var styledIris: CGImage?
        if style != .classic {
            let renderer = ImageRenderer(content:
                MoveIrisView(diameter: side, spin: rotationDegrees, style: style))
            renderer.scale = 8 // 144px bitmap; crisp at 18pt on any backing scale
            styledIris = renderer.cgImage
        }
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

            // Styled (non-classic) iris: the pre-rendered MoveIrisView disc.
            if let styledIris {
                ctx.draw(styledIris, in: rect)
                return true
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

            // Pupil + three comma tomoe on the classic ring — head circle plus
            // a tail that tapers as it hooks along the ring, matching the
            // full-size vector art so the menu bar mark reads as a Sharingan.
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            let pupilR = 0.16 * r
            ctx.fillEllipse(in: CGRect(x: c.x - pupilR, y: c.y - pupilR, width: pupilR * 2, height: pupilR * 2))
            let ringR = 0.52 * r
            let tomoeR = 0.19 * r
            let sweep = 100.0 * .pi / 180.0
            let steps = 14
            for i in 0..<3 {
                let head = (-80.0 + Double(i) * 120.0 - rotationDegrees) * .pi / 180.0
                let p = CGPoint(x: c.x + ringR * cos(head), y: c.y + ringR * sin(head))
                ctx.fillEllipse(in: CGRect(x: p.x - tomoeR, y: p.y - tomoeR,
                                           width: tomoeR * 2, height: tomoeR * 2))

                let path = CGMutablePath()
                var edge: [CGPoint] = []
                var back: [CGPoint] = []
                for s in 0...steps {
                    let t = Double(s) / Double(steps)
                    let a = head + sweep * t
                    let w = Double(tomoeR) * (1 - t)
                    edge.append(CGPoint(x: c.x + (ringR + w) * cos(a),
                                        y: c.y + (ringR + w) * sin(a)))
                    back.append(CGPoint(x: c.x + (ringR - w) * cos(a),
                                        y: c.y + (ringR - w) * sin(a)))
                }
                path.addLines(between: edge + back.reversed())
                path.closeSubpath()
                ctx.addPath(path)
                ctx.fillPath()
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
    var coordinator: SharinganCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Accessory apps start with no main menu, and macOS dispatches the
        // standard editing key equivalents (⌘V/⌘C/⌘X/⌘A/⌘Z) through the Edit
        // menu — without one, paste is dead in every text field of the app.
        // The app flips to `.regular` while the main window is open (that's
        // what puts the Sharingan menu bar and Dock icon up), so this menu is
        // visible then — a full File / View / Timer / Window / Help bar, not
        // just the key-equivalent shim it started as.
        installMainMenu()

        // One-shot Blink → Sharingan storage rename.
        RebrandMigration.migrate()

        // Sharingan's entire UI is a dark-glass design: every surface hardcodes white
        // text and `Color.white.opacity(...)` chrome over dark gradients and
        // `.regularMaterial`. Under the system Light appearance the popover and
        // stats tab render that white-on-light (invisible), while the main
        // window's forced-dark gradient turns semantic `.primary` labels
        // black-on-dark. Pin the whole app to dark so every surface — popover,
        // windows, materials, semantic colors — resolves consistently. The
        // menu-bar icon is a template image and still tints to the real menu bar.
        NSApp.appearance = NSAppearance(named: .darkAqua)

        let timer = PomodoroTimer()
        let coord = SharinganCoordinator(timer: timer)
        coord.breakPresenter = BreakWindowManager.shared
        coord.todayPanelController = TodayPanelWindowManager.shared
        coord.floatingWidgetController = FloatingWidgetWindowManager.shared
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
        NotchWindowManager.shared.install(timer: timer, coordinator: coord)

        // Desktop widget (WidgetKit): keep the appex's snapshot file fresh.
        WidgetSnapshotPublisher.shared.install(timer: timer)

        // Without this, notify()/schedule() silently no-op on a fresh install:
        // UNUserNotificationCenter.add fails while status is .notDetermined.
        Task { await NotificationService.shared.requestAuthorization() }

        // One-shot cleanup for the Blink → Sharingan notification-id rename
        // (RebrandMigration only covers UserDefaults/App Support, not
        // already-pending UNUserNotificationCenter requests): sweep any
        // leftover "blink.task.*" due/pre reminders and reschedule the ones
        // that still apply. No-ops after the first successful run.
        Task { await TaskStore.shared.sweepLegacyNotificationsIfNeeded() }

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

    // The full main menu lives in MainMenu.swift (installMainMenu()).

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

    // Quitting mid-pomodoro is usually an accident — confirm before losing
    // the running session. Breaks and idle states quit silently.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let timer, timer.isRunning, timer.phase == .focus else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "Pomodoro isn't finished"
        alert.informativeText = "A focus session is still running. Quit anyway?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Keep Going")
        alert.addButton(withTitle: "Quit Anyway")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn ? .terminateCancel : .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Best-effort: never leave the user's Focus stuck on after quit.
        if let timer {
            DNDShortcutService.shared.deactivate(settings: timer.settings)
        }
        // …and never leave the desktop widget counting down a session that
        // died with the app.
        WidgetSnapshotPublisher.shared.publishFinal()
    }
}